"""The APK's e2e flow on a running Android emulator (#61): installs the test APK, starts the game in
its test mode and reads the flow's result from the game's own log: it must pass and end in the
state hash the headless run of the same commit ended in (#876). Run by CI inside the emulator
step. A start that never reports is retried once (#957).

    uv run --locked tools/replays/apk_e2e.py <test APK> <the headless run's final hash>
"""

import re
import subprocess
import sys
import time

PACKAGE = "io.github.coarisfinia.khovax"
# The result line game/test_mode.gd prints, nothing else.
RESULT_LINE = re.compile(r"KHOVAX_E2E: (PASS -?[0-9]+|FAIL .*)$")
WAIT_S = 180
POLL_S = 2


class AdbFailed(Exception):
    """An adb command the run can't go on without failed; carries its exit code."""

    def __init__(self, code: int) -> None:
        super().__init__(code)
        self.code = code


def adb(*args: str, capture: bool = False, check: bool = True) -> tuple[int, str]:
    """Runs adb, returning its exit code and, when captured, its stdout as text (carriage returns
    kept); otherwise its output goes straight to the log. Its stderr always does."""
    done = subprocess.run(
        ["adb", *args], stdout=subprocess.PIPE if capture else None, check=False
    )
    if check and done.returncode != 0:
        raise AdbFailed(done.returncode)
    return done.returncode, (done.stdout or b"").decode("utf-8", "replace")


def last_result(log: str) -> str:
    """The log's last result line, or "" when the game hasn't reported."""
    found = ""
    for line in log.split("\n"):
        match = RESULT_LINE.search(line)
        if match:
            found = match.group(0)
    return found


def play(activity: str) -> str:
    """Starts the game and waits for its result line: "" when it never reported. Stops early when
    Godot dies at startup (!_start_success), which the emulator does now and then (#957)."""
    adb("logcat", "-c")
    print(f"launching {activity}", flush=True)
    # The test APK plays its flow on every start (game/test_mode.gd). A launch adb itself fails
    # counts as a start that never reported, so it gets the retry too.
    if adb("shell", "am", "start", "-n", activity, check=False)[0] != 0:
        print("the launch itself failed", flush=True)
        return ""
    result = ""
    deadline = time.monotonic() + WAIT_S
    while not result and time.monotonic() < deadline:
        time.sleep(POLL_S)
        # Only the game's log tag; a failing read counts as no result yet.
        _, log = adb("logcat", "-d", "-s", "godot:I", capture=True, check=False)
        result = last_result(log)
        if not result and "!_start_success" in log:
            break
    return result


def run(apk: str, expected: str) -> int:
    adb("install", "-r", apk)
    # The app's launcher activity, as the device resolves it: Godot's activity class itself isn't
    # exported, the launcher entry is. adb ends its lines with carriage returns.
    _, resolved = adb(
        "shell",
        "cmd",
        "package",
        "resolve-activity",
        "--brief",
        "-c",
        "android.intent.category.LAUNCHER",
        PACKAGE,
        capture=True,
    )
    activity = resolved.removesuffix("\n").split("\n")[-1].replace("\r", "")

    result = play(activity)
    if not result:
        # A game that never reported gets one more start (#957): the emulator's flaky startup
        # passes on a second try, and a real crash fails both. Its device log first, folded, since
        # the retry clears it.
        print("no result on the first start: the game never reported; retrying once (#957)")
        print("::group::the first start's device log", flush=True)
        adb("logcat", "-d", check=False)
        print("::endgroup::", flush=True)
        adb("shell", "am", "force-stop", PACKAGE)
        result = play(activity)
    print(result or f"no result within {WAIT_S} s: the game never reported", flush=True)
    if result != f"KHOVAX_E2E: PASS {expected}":
        if result.startswith("KHOVAX_E2E: PASS "):
            print(f"the headless run ended in state {expected}", flush=True)
        # The whole device log since the last start, every tag (#848): the game's own lines alone
        # don't show why it never started. Uncapped: logcat's own ring buffer already bounds it,
        # and a cap could cut the startup lines that matter.
        adb("logcat", "-d", check=False)
        return 1
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2
    try:
        return run(sys.argv[1], sys.argv[2])
    except AdbFailed as failed:
        return failed.code


if __name__ == "__main__":
    sys.exit(main())
