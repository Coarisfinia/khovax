"""Tests that gdstyle.py (#2215) gives up on a stalled download, and that every failed install ends
with one clean message and a non-zero exit, never a traceback, and caches nothing (#2244). Each
run downloads from a local stand-in for GitHub's release, in its own cache, against a stand-in
repository whose pin and checksum match the archive served.

    uv run --locked --package khovax-game-build src/game-build/test_gdstyle.py
"""

import hashlib
import importlib.util
import io
import json
import os
import socket
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("gdstyle.py")
VERSION = "0.0.0-test"
# The test's own download timeout: short, so a stalled download gives up quickly.
TIMEOUT_SECONDS = 1
# A run still going after this is hanging.
RUN_LIMIT_SECONDS = 30


def archive(members: dict[str, bytes]) -> bytes:
    """A .tar.gz holding `members`, each a file."""
    out = io.BytesIO()
    with tarfile.open(fileobj=out, mode="w:gz") as tar:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o755
            tar.addfile(info, io.BytesIO(data))
    return out.getvalue()


class Release(BaseHTTPRequestHandler):
    """Serves the server's `body`, or with `stall` sends the headers and then nothing, or with
    `cut` the first ten bytes of it and then closes."""

    def do_GET(self) -> None:
        body: bytes = self.server.body  # type: ignore[attr-defined]
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.flush()
        if self.server.stall:  # type: ignore[attr-defined]
            self.server.release.wait()  # type: ignore[attr-defined]
            return
        if self.server.cut:  # type: ignore[attr-defined]
            self.wfile.write(body[:10])
            self.wfile.flush()
            self.connection.shutdown(socket.SHUT_RDWR)
            return
        self.wfile.write(body)

    def log_message(self, *_arguments: object) -> None:
        pass


def child(root: str, url: str) -> int:
    """Runs gdstyle.py's main against the stand-in repository at `root` and release at `url`, with
    the test's timeout: the test runs this in a subprocess, so a hanging download can be timed."""
    spec = importlib.util.spec_from_file_location("gdstyle", SCRIPT)
    assert spec is not None and spec.loader is not None
    gdstyle = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gdstyle)
    gdstyle.ROOT = Path(root)
    gdstyle.RELEASE = url
    gdstyle.TIMEOUT_SECONDS = TIMEOUT_SECONDS
    sys.argv = [str(SCRIPT), "--version"]
    return gdstyle.main()


class GdstyleDownloadTest(unittest.TestCase):
    def run_install(
        self, body: bytes, sha256: str | None = None, *, stall: bool = False, cut: bool = False
    ) -> tuple[int | None, str, Path]:
        """gdstyle.py's exit code (None when it was still running), its output and its cache,
        served `body`, with the stand-in repository pinning `sha256` (the body's by default)."""
        server = ThreadingHTTPServer(("127.0.0.1", 0), Release)
        server.daemon_threads = True
        server.body, server.stall, server.cut = body, stall, cut  # type: ignore[attr-defined]
        server.release = threading.Event()  # type: ignore[attr-defined]
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.addCleanup(server.release.set)  # type: ignore[attr-defined]
        folder = Path(self.enterContext(tempfile.TemporaryDirectory()))
        root = folder / "repository"
        (root / "tools/scoop").mkdir(parents=True)
        (root / "tools/scoop/gdstyle.json").write_text(json.dumps({"version": VERSION}), encoding="utf-8")
        (root / ".github/workflows").mkdir(parents=True)
        checksum = sha256 or hashlib.sha256(body).hexdigest()
        (root / ".github/workflows/ci.yml").write_text(f"env:\n  GDSTYLE_SHA256: {checksum}\n", encoding="utf-8")
        cache = folder / "cache"
        port = server.server_address[1]
        url = f"http://127.0.0.1:{port}/v{{version}}/gdstyle.tar.gz"
        try:
            done = subprocess.run(
                [sys.executable, "-I", __file__, "--child", str(root), url],
                env={**os.environ, "XDG_CACHE_HOME": str(cache)},
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=RUN_LIMIT_SECONDS,
                check=False,
            )
        except subprocess.TimeoutExpired as late:
            return None, (late.output or b"").decode("utf-8", "replace"), cache
        return done.returncode, done.stdout.decode("utf-8", "replace"), cache

    def assert_fails_cleanly(self, code: int | None, output: str, cache: Path) -> None:
        self.assertIsNotNone(code, f"still running after {RUN_LIMIT_SECONDS} s:\n{output}")
        self.assertNotEqual(code, 0, output)
        self.assertNotIn("Traceback", output)
        lines = output.strip().splitlines()
        self.assertEqual(len(lines), 1, output)
        self.assertTrue(lines[0].startswith("gdstyle.py: "), output)
        self.assertEqual([path for path in cache.rglob("*") if path.is_file()], [], "something was cached")

    def test_installs_and_runs(self) -> None:
        code, output, _cache = self.run_install(archive({"gdstyle": b"#!/bin/sh\necho stand-in gdstyle\n"}))
        self.assertEqual(code, 0, output)
        self.assertEqual(output.strip(), "stand-in gdstyle")

    def test_stalled_download_gives_up(self) -> None:
        started = time.monotonic()
        code, output, cache = self.run_install(archive({"gdstyle": b"x"}), stall=True)
        self.assert_fails_cleanly(code, output, cache)
        self.assertLess(time.monotonic() - started, RUN_LIMIT_SECONDS)

    def test_cut_download(self) -> None:
        self.assert_fails_cleanly(*self.run_install(archive({"gdstyle": b"x" * 4096}), cut=True))

    def test_wrong_checksum(self) -> None:
        self.assert_fails_cleanly(*self.run_install(archive({"gdstyle": b"x"}), "0" * 64))

    def test_archive_without_gdstyle(self) -> None:
        self.assert_fails_cleanly(*self.run_install(archive({"other": b"x"})))

    def test_truncated_archive(self) -> None:
        # Its checksum matches, so only unpacking finds the gzip stream ends early.
        whole = archive({"gdstyle": os.urandom(65536)})
        self.assert_fails_cleanly(*self.run_install(whole[: len(whole) // 2]))

    def test_not_an_archive(self) -> None:
        self.assert_fails_cleanly(*self.run_install(b"not a tar file"))


if __name__ == "__main__":
    if sys.argv[1:2] == ["--child"]:
        sys.exit(child(sys.argv[2], sys.argv[3]))
    unittest.main()
