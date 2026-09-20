#!/usr/bin/env bash
#
# TripSplit development container entrypoint.
#
# Responsibilities:
#   - make the Android SDK visible to Flutter/Gradle
#   - resolve Flutter packages before forwarding the requested command
#
# The source tree is bind-mounted at /workspace, so all state that must survive
# container rebuilds (pub cache, Gradle cache) is expected on named volumes.

set -euo pipefail

# Android SDK discovery --------------------------------------------------------
# The base image installs the SDK under /opt/android-sdk-linux; respect any
# override supplied via environment.
SDK_DIR=""
for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /opt/android-sdk-linux /opt/android-sdk; do
  if [ -n "${candidate}" ] && [ -d "${candidate}/platform-tools" ]; then
    SDK_DIR="${candidate}"
    break
  fi
done

if [ -n "${SDK_DIR}" ]; then
  export ANDROID_HOME="${SDK_DIR}"
  export ANDROID_SDK_ROOT="${SDK_DIR}"
  for tool_dir in "${SDK_DIR}/cmdline-tools/latest/bin" "${SDK_DIR}/cmdline-tools/bin" "${SDK_DIR}/platform-tools" "${SDK_DIR}/build-tools/36.0.0"; do
    if [ -d "${tool_dir}" ] && [[ ":${PATH}:" != *":${tool_dir}:"* ]]; then
      export PATH="${tool_dir}:${PATH}"
    fi
  done
fi

# JDK discovery ----------------------------------------------------------------
# Prefer an explicit JAVA_HOME, then fall back to any JVM installed under
# /usr/lib/jvm so Gradle does not fail on an unset/missing JDK.
if [ -z "${JAVA_HOME:-}" ] && [ -d /usr/lib/jvm ]; then
  JAVA_HOME="$(ls -d /usr/lib/jvm/java-* 2>/dev/null | sort -V | tail -n 1 || true)"
  if [ -n "${JAVA_HOME}" ]; then
    export JAVA_HOME
    if [ -d "${JAVA_HOME}/bin" ]; then
      export PATH="${JAVA_HOME}/bin:${PATH}"
    fi
  fi
fi

# Install dependencies when running inside a mounted project -------------------
if [ -f "pubspec.lock" ] && [ ! -f ".dart_tool/package_config.json" ]; then
  flutter pub get >/dev/null
fi

exec "$@"