# syntax=docker/dockerfile:1

# Stable, maintained Flutter + Android toolchain image used as the base for the
# TripSplit development environment. It provides the Flutter/Dart SDK, a
# Gradle-compatible JDK, and the Android command-line tools.
FROM ghcr.io/cirruslabs/flutter:stable

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
# Tool-generated state (`.dart_tool`, pub cache, Gradle cache) is kept out of
# the bind-mounted workspace via volumes in docker-compose, so host and
# container never race over the same package-resolution files.
ENV WORKSPACE=/workspace \
    PUB_CACHE=/root/.pub-cache \
    GRADLE_USER_HOME=/root/.gradle \
    PATH="${PATH}:/workspace/docker/scripts"

WORKDIR ${WORKSPACE}

# ---------------------------------------------------------------------------
# System tooling required by the toolchain (idempotent, mirrors upstream image
# contents so the layer stays small).
# ---------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        curl \
        git \
        unzip \
        zip \
        file \
        ca-certificates \
        libsqlite3-dev \
        libsqlite3-0 \
        clang \
        cmake \
        ninja-build \
        pkg-config \
        libgtk-3-dev \
        liblzma-dev \
    && rm -rf /var/lib/apt/lists/*

# Be explicit about the Android SDK location for reproducibility, regardless of
# how the base image lays its files out.
ARG ANDROID_SDK_DEFAULT=/opt/android-sdk-linux
ENV ANDROID_HOME=${ANDROID_SDK_DEFAULT} \
    ANDROID_SDK_ROOT=${ANDROID_SDK_DEFAULT} \
    ANDROID_SDK_ROOT_DEFAULT=${ANDROID_SDK_DEFAULT}

# Accept all Android SDK licenses up-front so `flutter doctor` and Gradle do
# not block on interactive prompts.
RUN yes | flutter doctor --android-licenses > /dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Project source is mounted at runtime via docker-compose (bind mount). Keep
# the image free of project files so it stays reusable.
# ---------------------------------------------------------------------------

ENTRYPOINT ["/workspace/docker/scripts/entrypoint.sh"]
CMD ["flutter", "--version"]