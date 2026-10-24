# Decisions

_Newest first. Log the why, not just the what._

### 2026-10-24 · JDK 21 from Homebrew's keg-only formula
- Context: the Android build needs JDK 17+ (AGP 9.1, Gradle 9.3.1, Java 17 target), and the Firebase emulators used by the rules tests need JDK 21+.
- Options: A) Temurin cask (installs into `/Library/Java`, needs an admin password); B) Homebrew `openjdk@21` formula (keg-only, no password); C) Android Studio's bundled JBR (pulls in the whole IDE).
- Decision: B, JDK 21, wired in via `JAVA_HOME` in `~/.zshrc` and `flutter config --jdk-dir`.
- Why: one JDK covers both Gradle and the emulators, and installing it needs no sudo. Revisit if a tool insists on `/usr/libexec/java_home` finding a system JDK. The fix then is `sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk`.
- Made by: claude-opus-5-5

### 2026-10-24 · Android SDK from command-line tools, not Android Studio
- Context: the app needs an Android SDK to build and an emulator to run without a phone.
- Options: A) Android Studio (GUI, several GB, manages its own SDK); B) `android-commandlinetools` cask plus `sdkmanager`.
- Decision: B, with the SDK at `/opt/homebrew/share/android-commandlinetools` and only the packages Flutter 3.47.7 asks for (android-36, build-tools 36.1.0, NDK 28.2.13676358) plus an emulator image.
- Why: smaller, scriptable, and enough for `flutter build` and `flutter run`. Android Studio can still be added later and pointed at this SDK.
- Made by: claude-opus-5-5
