# Neon Gokart

A neon, arcade drift racer for phones. One file of HTML5 canvas (`index.html`), wrapped as a tiny Android app.

## Play

- **Left half of the screen:** steer left. **Right half:** steer right. Gas is automatic.
- **Hold one side** to drift. **Let go** to fire a boost; longer drifts give bigger boosts.
- **Ride the racing line** (dashed line) for extra grip. Cut through the **apex** dots to raise your aim assist.
- Brushing a wall costs a little speed. A head-on hit costs more.
- Turn on **RIVAL BOT** (bottom-left of the track screen) to race a bot that drives the ideal line.
- Pause menu: switch between **first-person** and **top-down** view, and pick the sky: **Cyber City**, **Sunset** or **Classic**.

Keyboard: `A` / `D` or arrow keys.

## Run in a browser

Open `index.html`, or serve the folder:

```sh
python3 -m http.server 8080
```

## Build the Android APK

Needs the Android SDK command-line tools (`platforms;android-28`, `build-tools`) and JDK 17. No Gradle.

```sh
cd android
echo '<keystore password>' > .keypass   # or export GK_KEYPASS; .keypass is git-ignored
./build.sh                                # writes android/build/NeonGokart.apk
```

`build.sh` creates `android/neongokart.keystore` on the first run. Keep that file safe and out of git: Android only installs updates signed with the same key.

## Credits

Font: [Russo One](https://fonts.google.com/specimen/Russo+One) by Jovanny Lemonad, SIL Open Font License 1.1 (`android/assets/RussoOne-OFL.txt`).

Track layouts are stylised shapes inspired by real circuits. The circuit names belong to their owners.
