#!/bin/bash
# Push the verified OOS 11 rollback package to the phone's internal storage with the exact name the
# OnePlus local installer requires, and verify the copy on the phone.
set -eu
N=/srv/nord2-pmos; SER=${SERIAL:?set SERIAL to the phone serial}
ADB="$N/platform-tools/adb -s $SER"
F=$N/firmware-vendor/oos11-rollback/oplus_ota_downgrade_EU.zip
grep -q VERIFY-OK ~/nord2-dl.log || { echo "package not verified, aborting"; exit 1; }
$ADB shell 'getprop ro.build.display.id; dumpsys battery | grep level; df -h /sdcard | tail -1'
$ADB push "$F" /sdcard/oplus_ota_downgrade.zip
L=$(sha256sum "$F" | cut -d" " -f1)
R=$($ADB shell sha256sum /sdcard/oplus_ota_downgrade.zip | cut -d" " -f1)
echo "local=$L"; echo "phone=$R"
[ "$L" = "$R" ] && echo PUSH-OK || echo PUSH-MISMATCH
