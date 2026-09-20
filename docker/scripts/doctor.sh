#!/usr/bin/env bash
#
# TripSplit environment diagnostics.
#
# Runs the full Flutter toolchain check and summarizes the Android SDK state.
# Warnings caused by unavailable GUI/emulator components are expected and are
# not treated as failures.

set -uo pipefail

echo "=================================================================="
echo " TripSplit development environment doctor"
echo "=================================================================="
echo
echo "Flutter SDK   : $(flutter --version | head -n 1)"
echo "Dart SDK      : $(dart --version 2>&1)"
echo "Android SDK   : ${ANDROID_HOME:-not set}"
echo "Java          : $(java -version 2>&1 | head -n 1)"
echo

echo "--- flutter doctor ---"
flutter doctor -v
FLUTTER_DOCTOR_EXIT=$?
echo

echo "--- android licenses ---"
yes | flutter doctor --android-licenses >/dev/null 2>&1 && echo "Android licenses: accepted" || echo "Android licenses: needs manual acceptance"

if [ "${FLUTTER_DOCTOR_EXIT}" -ne 0 ]; then
  echo "flutter doctor reported issues (see above)."
fi

exit ${FLUTTER_DOCTOR_EXIT}