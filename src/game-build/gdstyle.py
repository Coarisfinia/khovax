"""Runs the gdstyle the repository pins (#2215), for Linux and WSL, without installing anything
system-wide: the first run downloads CI's release into the user's cache and checks its checksum.
The version comes from tools/scoop/gdstyle.json and the checksum from CI's GDSTYLE_SHA256, the
same two sources CI uses. Arguments go to gdstyle, which runs in the caller's folder:

    uv run --locked ../game-build/gdstyle.py fmt .
"""

import hashlib
import http.client
import json
import os
import platform
import re
import stat
import sys
import tarfile
import tempfile
import urllib.request
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELEASE = "https://github.com/atelico/gdstyle/releases/download/v{version}/gdstyle-x86_64-unknown-linux-gnu.tar.gz"
SHA256 = re.compile(r"^ *GDSTYLE_SHA256: *([0-9a-f]{64}) *$", re.MULTILINE)
# Per connection attempt and per read: a download that stalls this long gives up rather than hang.
TIMEOUT_SECONDS = 60
# Every way a download or an archive can fail: each ends in one clean message, never a traceback.
FAILURES = (
    OSError,
    EOFError,
    ValueError,
    KeyError,
    zlib.error,
    http.client.HTTPException,
    tarfile.TarError,
)


def install(version: str, sha256: str, binary: Path) -> None:
    """Downloads the release, checks it, and puts the binary at `binary` with one rename, so a
    parallel run sees either no binary or a whole one."""
    binary.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=binary.parent) as folder:
        archive = Path(folder) / "gdstyle.tar.gz"
        with urllib.request.urlopen(RELEASE.format(version=version), timeout=TIMEOUT_SECONDS) as response:
            # A whole read: a download cut short raises IncompleteRead rather than passing short.
            data = response.read()
        archive.write_bytes(data)
        actual = hashlib.sha256(data).hexdigest()
        if actual != sha256:
            raise ValueError(f"the download's checksum is {actual}, CI's is {sha256}")
        unpacked = Path(folder) / "gdstyle"
        # The release is a .tar.gz; naming it keeps a refusal to one line, unlike auto-detection.
        with tarfile.open(archive, "r:gz") as tar:
            member = tar.extractfile("gdstyle")
            if member is None:
                raise ValueError("the archive's gdstyle isn't a file")
            unpacked.write_bytes(member.read())
        unpacked.chmod(unpacked.stat().st_mode | stat.S_IXUSR)
        unpacked.replace(binary)


def main() -> int:
    if (platform.system(), platform.machine()) != ("Linux", "x86_64"):
        print("gdstyle.py: only for x86-64 Linux; elsewhere install tools/scoop/gdstyle.json", file=sys.stderr)
        return 1
    version = json.loads((ROOT / "tools/scoop/gdstyle.json").read_text(encoding="utf-8"))["version"]
    found = SHA256.search((ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8"))
    if found is None:
        print("gdstyle.py: no GDSTYLE_SHA256 in .github/workflows/ci.yml", file=sys.stderr)
        return 1
    sha256 = found.group(1)
    # Keyed by the checksum, and outside the repository so that every worktree shares one download.
    cache = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache")
    binary = cache / "khovax" / "gdstyle" / f"{version}-{sha256}" / "gdstyle"
    if not os.access(binary, os.X_OK):
        try:
            install(version, sha256, binary)
        except FAILURES as error:
            print(f"gdstyle.py: {type(error).__name__}: {error}", file=sys.stderr)
            return 1
    os.execv(binary, [str(binary), *sys.argv[1:]])


if __name__ == "__main__":
    sys.exit(main())
