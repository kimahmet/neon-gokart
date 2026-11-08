#!/usr/bin/env bash
# Builds android/build/NeonGokart.apk from ../index.html with the bare SDK tools (no Gradle).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SDK=${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}
JAR=$SDK/platforms/android-28/android.jar
BT=$(find "$SDK/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)
export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}
export PATH="$JAVA_HOME/bin:$PATH"   # d8 and apksigner call java from PATH
VERSION_CODE=${VERSION_CODE:-1}; VERSION_NAME=${VERSION_NAME:-0.1}
KEYSTORE=$PWD/neongokart.keystore
# keystore password: $GK_KEYPASS, else the untracked file .keypass next to this script
KEYPASS=${GK_KEYPASS:-$(cat .keypass 2>/dev/null || true)}
[[ -n $KEYPASS ]] || { echo "set GK_KEYPASS or write the keystore password to android/.keypass" >&2; exit 1; }

[[ -f $KEYSTORE ]] || { "$JAVA_HOME/bin/keytool" -genkeypair -keystore "$KEYSTORE" -alias gk -keyalg RSA -keysize 2048 \
  -validity 10000 -storepass "$KEYPASS" -keypass "$KEYPASS" -dname "CN=Neon Gokart" >/dev/null; echo "created signing key (keep it)"; }

# the game page: add a document head and use the bundled font instead of Google Fonts
python3 - <<'EOF'
src = open('../index.html', encoding='utf-8').read()
src = '\n'.join(l for l in src.split('\n') if 'fonts.googleapis.com' not in l and 'fonts.gstatic.com' not in l)
head = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">'
        '<style>@font-face{font-family:"Russo One";src:url("RussoOne-Regular.ttf") format("truetype");font-display:block}</style>')
open('assets/index.html', 'w', encoding='utf-8').write(head + src)
EOF
for d in xxhdpi:144 xxxhdpi:192; do python3 make_icon.py "res/mipmap-${d%%:*}/ic_launcher.png" "${d##*:}"; done

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/classes" build
"$BT/aapt2" compile --dir res -o "$WORK/res.zip"
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml "$WORK/res.zip" -A assets \
  --min-sdk-version 24 --target-sdk-version 28 --version-code "$VERSION_CODE" --version-name "$VERSION_NAME" -o "$WORK/app.apk"
"$JAVA_HOME/bin/javac" --release 8 -nowarn -encoding UTF-8 -classpath "$JAR" -d "$WORK/classes" $(find src -name '*.java')
"$BT/d8" --release --min-api 24 --lib "$JAR" --output "$WORK" $(find "$WORK/classes" -name '*.class')
(cd "$WORK" && zip -q -X app.apk classes.dex)
"$BT/zipalign" -f -p 4 "$WORK/app.apk" "$WORK/aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass "pass:$KEYPASS" --key-pass "pass:$KEYPASS" --out build/NeonGokart.apk "$WORK/aligned.apk"
"$BT/apksigner" verify build/NeonGokart.apk
echo "built build/NeonGokart.apk ($(wc -c < build/NeonGokart.apk | tr -d ' ') bytes)"
