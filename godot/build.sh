#!/usr/bin/env bash
# Builds build/NeonGokart.apk (release, arm64) with Godot 4.7 and the signing key shared with the old web wrapper.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
KS=$PWD/../android/neongokart.keystore
# keystore password: $GK_KEYPASS, else the untracked file android/.keypass
PASS=${GK_KEYPASS:-$(cat ../android/.keypass 2>/dev/null || true)}
[[ -n $PASS ]] || { echo "set GK_KEYPASS or write the keystore password to android/.keypass" >&2; exit 1; }
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$KS GODOT_ANDROID_KEYSTORE_RELEASE_USER=gk GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$PASS
mkdir -p build
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . -s res://tests/sim.gd | tail -1
godot --headless --path . --export-release Android build/NeonGokart.apk
ls -la build/NeonGokart.apk
