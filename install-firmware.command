#!/bin/bash
# Builds the MicroPad firmware (QMK) and flashes it to the Creator Micro.
cd "$(dirname "$0")"
HERE="$(pwd)"
# Everything printed in the Terminal is also saved here:
exec > >(tee "$HERE/log-firmware.txt") 2>&1
trap 'RC=$?; if [ $RC -ne 0 ]; then echo; echo "Something went wrong (see above). Press Return to close."; read -r _; else echo; echo "Done: you can close this window."; fi' EXIT
set -e

[ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
[ -x /usr/local/bin/brew ] && eval "$(/usr/local/bin/brew shellenv)"

echo "== MicroPad · firmware =="

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh, then run this script again."
  exit 1
fi

# The qmk command may also live in a dedicated Python venv (see below).
[ -x "$HOME/.micropad-qmk/bin/qmk" ] && export PATH="$HOME/.micropad-qmk/bin:$PATH"

if ! qmk --version >/dev/null 2>&1; then
  echo "Installing QMK (this takes a few minutes)…"
  # QMK and the keyboard MCU toolchains live in third-party taps.
  # Recent Homebrew versions require trusting them explicitly.
  for TAP in osx-cross/avr osx-cross/arm qmk/qmk; do
    brew tap "$TAP"
    brew trust "$TAP" 2>/dev/null || true
  done
  brew install qmk/qmk/qmk || true
  brew link --overwrite qmk 2>/dev/null || true
fi

if ! qmk --version >/dev/null 2>&1; then
  echo "Homebrew's qmk command doesn't work: installing it with Python in ~/.micropad-qmk…"
  PY="$(brew --prefix)/bin/python3"
  [ -x "$PY" ] || PY="$(command -v python3)"
  rm -rf "$HOME/.micropad-qmk"
  "$PY" -m venv "$HOME/.micropad-qmk"
  "$HOME/.micropad-qmk/bin/pip" install --upgrade pip qmk
  export PATH="$HOME/.micropad-qmk/bin:$PATH"
fi

# The AVR/ARM toolchains installed by Homebrew may not be on PATH.
for F in avr-gcc@8 arm-none-eabi-gcc@8 avr-binutils arm-none-eabi-binutils; do
  P="$(brew --prefix "$F" 2>/dev/null)/bin"
  if [ -d "$P" ]; then export PATH="$P:$PATH"; fi
done

hash -r
echo "qmk: $(command -v qmk) $(qmk --version 2>&1)"
echo "avr-gcc: $(command -v avr-gcc || echo 'not found')"

QMK_HOME="$HOME/qmk_firmware"
if [ ! -d "$QMK_HOME/keyboards/work_louder/micro" ]; then
  echo "Downloading QMK into $QMK_HOME…"
  qmk setup -y -H "$QMK_HOME"
fi

KEYMAP="$QMK_HOME/keyboards/work_louder/micro/keymaps/micropad"
rm -rf "$KEYMAP"
mkdir -p "$KEYMAP"
cp "$HERE/firmware/micropad/"* "$KEYMAP/"

echo "Building…"
qmk compile -kb work_louder/micro -km micropad
cp "$QMK_HOME/work_louder_micro_micropad.hex" "$HERE/firmware/prebuilt/" 2>/dev/null || true

echo
echo "Now put the pad in bootloader mode:"
echo "  unplug the cable, hold the top-left encoder and plug it back in"
echo "  (or press the small reset button on the back of the PCB)."
echo "The script waits for the pad and flashes the firmware automatically."
echo
qmk flash -kb work_louder/micro -km micropad

echo
echo "Done. Unplug the pad and plug it back in."
