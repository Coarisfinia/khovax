#!/usr/bin/env bash
# The APK's e2e flow on a running Android emulator (#61): installs the test APK, starts the game in
# its test mode and reads the flow's result from the game's own log. Run by CI inside the emulator
# step.
set -euo pipefail
apk=${1:-build/khovax-test.apk}
package=io.github.flixbox.khovax
# The result line game/test_mode.gd prints, nothing else.
result_line='KHOVAX_APK_E2E: (PASS|FAIL .*)$'

adb install -r "$apk"
adb logcat -c
# The app's launcher activity, as the device resolves it: Godot's activity class itself isn't
# exported, the launcher entry is. adb ends its lines with carriage returns.
activity=$(adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$package" \
  | tail -1 | tr -d '\r')
echo "launching $activity"
# The test APK plays its flow on every start (game/test_mode.gd).
adb shell am start -n "$activity"
result=""
deadline=$((SECONDS + 180))
while [ -z "$result" ] && [ "$SECONDS" -lt "$deadline" ]; do
  sleep 2
  # Only the game's log tag, read into a variable first: grep on a pipe under pipefail can fail
  # the whole test for the wrong reason.
  log=$(adb logcat -d -s godot:I || true)
  result=$(grep -oE "$result_line" <<< "$log" | tail -1 || true)
done
echo "${result:-no result within 180 s: the game never reported}"
if [ "$result" != "KHOVAX_APK_E2E: PASS" ]; then
  adb logcat -d -s godot:V | tail -100
  exit 1
fi
