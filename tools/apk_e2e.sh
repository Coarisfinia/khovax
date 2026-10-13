#!/usr/bin/env bash
# The APK's e2e flow on a running Android emulator (#61): installs the test APK, starts the game in
# its test mode and reads the flow's result from the device log. Run by CI inside the emulator step.
set -euo pipefail
apk=${1:-build/khovax-test.apk}
package=io.github.flixbox.khovax

adb install -r "$apk"
adb logcat -c
# The flag reaches the game as a command-line argument through the launch intent.
adb shell am start -n "$package/com.godot.game.GodotApp" --esa command_line_params --khovax-apk-test
for _ in $(seq 1 90); do
  if adb logcat -d | grep -q "KHOVAX_APK_E2E:"; then
    break
  fi
  sleep 2
done
result=$(adb logcat -d | grep "KHOVAX_APK_E2E:" || true)
echo "${result:-no result: the game never reported (see the log below)}"
if ! grep -q "KHOVAX_APK_E2E: PASS" <<< "$result"; then
  adb logcat -d | grep -iE "godot|khovax" | tail -100
  exit 1
fi
