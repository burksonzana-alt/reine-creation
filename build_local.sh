#!/usr/bin/env bash
# Compile l'APK sur une machine où Flutter + Android SDK fonctionnent
# (Termux / Ubuntu proot configuré, PC Linux/Mac/Windows-WSL).
set -e
cd "$(dirname "$0")"

if [ ! -d android ]; then
  flutter create --platforms=android --org com.reinecreation --project-name reine_creation .
fi
python3 tools/patch_android.py
flutter pub get
flutter build apk --release

APK=build/app/outputs/flutter-apk/app-release.apk
echo "APK prêt : $APK"

# Copie vers le stockage du téléphone (nécessite : termux-setup-storage, déjà fait)
for D in "$HOME/storage/downloads" "/sdcard/Download" "/storage/emulated/0/Download"; do
  if [ -d "$D" ] && [ -w "$D" ]; then
    cp "$APK" "$D/MadameZANACouture.apk"
    echo "Copié dans $D/MadameZANACouture.apk"
    break
  fi
done
