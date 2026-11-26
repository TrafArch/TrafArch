FROM debian:bookworm-20261123-slim@sha256:311f7a192fd9a92b165a86b32fa3aae9005b11849bfb1db2d4fd784559ee464f

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_HOME=/opt/android-sdk \
    FLUTTER_ROOT=/opt/flutter
ENV PATH="${FLUTTER_ROOT}/bin:${ANDROID_HOME}/cmdline-tools/19.0/bin:${ANDROID_HOME}/platform-tools:${PATH}"

RUN mkdir -p /usr/share/man/man1 \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates curl git libglu1-mesa openjdk-17-jdk-headless python3 unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.47.6
ARG FLUTTER_SHA256=f1631b9c2c8b3529323db412b0d1beacf4a748f8783b0d7cf599a8fd5f461675
# CNB can only map IDs up to 65535. Extract SDK files as the container user.
RUN curl -fL --retry 3 -o /tmp/flutter.tar.xz \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    && echo "${FLUTTER_SHA256}  /tmp/flutter.tar.xz" | sha256sum -c - \
    && tar --no-same-owner -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz

ARG ANDROID_TOOLS_REVISION=13114758
ARG ANDROID_TOOLS_SHA256=7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee
RUN curl -fL --retry 3 -o /tmp/cmdline-tools.zip \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_TOOLS_REVISION}_latest.zip" \
    && echo "${ANDROID_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c - \
    && mkdir -p "$ANDROID_HOME/cmdline-tools" \
    && unzip -q /tmp/cmdline-tools.zip -d "$ANDROID_HOME/cmdline-tools" \
    && mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/19.0" \
    && rm /tmp/cmdline-tools.zip

RUN yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses >/dev/null \
    && sdkmanager --sdk_root="$ANDROID_HOME" 'platform-tools' \
        'platforms;android-36' 'platforms;android-37.0' \
        'build-tools;36.0.0' 'build-tools;37.0.0' 'ndk;30.0.16248370' \
    && test -x "$ANDROID_HOME/platform-tools/adb" \
    && test -x "$ANDROID_HOME/build-tools/37.0.0/apksigner" \
    && test -f "$ANDROID_HOME/ndk/30.0.16248370/source.properties"

# Android plugins request these alongside the app's SDK and NDK during assembleRelease.
RUN sdkmanager --sdk_root="$ANDROID_HOME" \
        'ndk;28.2.13676358' 'platforms;android-35' 'cmake;3.22.1' \
    && test -f "$ANDROID_HOME/ndk/28.2.13676358/source.properties" \
    && test -f "$ANDROID_HOME/platforms/android-35/android.jar" \
    && test -x "$ANDROID_HOME/cmake/3.22.1/bin/cmake"

# Fail before CNB caches the image if a future SDK introduces an unmappable owner.
RUN bad_owner="$(find /opt -xdev \( -uid +65535 -o -gid +65535 \) -printf '%U:%G %p\n' -quit)" \
    && if [ -n "$bad_owner" ]; then echo "CNB cannot map $bad_owner" >&2; exit 1; fi
