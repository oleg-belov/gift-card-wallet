#!/usr/bin/env bash
# End-to-end smoke test: drives the REAL app on a running Android emulator
# through the full user journey via adb — no agent, no screenshots to read.
#
#   tool/e2e_smoke.sh [--build] [device-id]
#
#   --build   run `flutter build apk --debug` first (remember to re-apply
#             the tool/* pub-cache patches after pub changes)
#   device-id adb serial; defaults to the single connected device
#
# Journey (fresh install):
#   PIN setup → Scan tab → Image/PDF → SAF picker (Downloads) → voucher PDF
#   → unlock → import replay sheet → online check (fails against the WAF,
#   expected — see README) → Save anyway → duplicate re-import blocked.
#
# Assertions come from logcat markers ("E2E: …", debug builds only) and the
# network fetch log. Screenshots of every step land in build/e2e-artifacts/
# so a failure can be inspected afterwards.
#
# Screen coordinates are for a 1080x2400 emulator at 420dpi (Pixel-style
# AVD). The SAF picker is a native activity, so it is driven via
# uiautomator dump instead of fixed coordinates.
set -uo pipefail  # no -e: transient adb hiccups would kill the run silently; key steps are checked explicitly
cd "$(dirname "$0")/.."

PKG=ch.olegbelov.lidl_gift_card
ACTIVITY="$PKG/.MainActivity"
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
APP_PIN=1357
VOUCHER_PDF=test/fixtures/lidl_voucher_100chf_used.pdf
DEVICE_PDF_NAME=lidl_voucher.pdf
ART_DIR=build/e2e-artifacts

# 1080x2400 @ 420dpi
TAP_PIN_FIELD="540 1296"      # unlock screen field
TAP_UNLOCK="540 1570"         # Unlock button (no IME)
TAP_SETUP_PIN1="540 1104"     # setup: App PIN field
TAP_SETUP_PIN2="540 1376"     # setup: Repeat field (no IME — see below)
TAP_ENABLE="540 1878"         # Enable protection (no IME)
TAP_SCAN_TAB="407 2218"       # bottom nav Scan
TAP_MODE_FILE="890 355"       # Image/PDF mode chip
TAP_CHECK="540 2294"          # Check Balance & Save Card
TAP_SAVE_ANYWAY="540 2314"    # Save anyway

BUILD=0
if [[ "${1:-}" == "--build" ]]; then BUILD=1; shift; fi
DEVICE="${1:-}"

mkdir -p "$ART_DIR"

fail() {
  echo "FAIL: $1" >&2
  echo "Artifacts: $ART_DIR (last screenshot + full logcat)" >&2
  "$ADB" exec-out screencap -p > "$ART_DIR/FAIL-last-screen.png" 2>/dev/null || true
  "$ADB" logcat -d > "$ART_DIR/FAIL-logcat.txt" 2>/dev/null || true
  exit 1
}

shot() { "$ADB" exec-out screencap -p > "$ART_DIR/$1.png" 2>/dev/null; }
tap()  { "$ADB" shell input tap "$1"; }
text() { "$ADB" shell input text "$1"; }
close_ime() { "$ADB" shell input keyevent 4; }  # BACK dismisses the IME

# Waits until logcat contains the given marker (I flutter lines).
# Returns 1 on timeout (callers in retry loops handle it; plain call sites
# run under `set -e` so a bare failure aborts).
wait_marker() {
  local marker="$1" timeout="${2:-30}" started
  started=$(date +%s)
  while true; do
    if "$ADB" logcat -d 2>/dev/null | grep "I flutter" | grep -q "$marker"; then
      echo "  ✓ marker: $marker"
      return 0
    fi
    if (( $(date +%s) - started > timeout )); then
      echo "  ✗ marker not seen within ${timeout}s: $marker" >&2
      return 1
    fi
    sleep 2
  done
}

# Like wait_marker, but for markers that fire once per journey cycle:
# waits until logcat shows at least [min] occurrences.
wait_marker_count() {
  local marker="$1" min="$2" timeout="${3:-30}" started c
  started=$(date +%s)
  while true; do
    c=$("$ADB" logcat -d 2>/dev/null | grep "I flutter" | grep -c "$marker")
    if (( c >= min )); then
      echo "  ✓ marker: $marker (count $c ≥ $min)"
      return 0
    fi
    if (( $(date +%s) - started > timeout )); then
      echo "  ✗ $marker count $c < $min after ${timeout}s" >&2
      return 1
    fi
    sleep 2
  done
}

dump_ui() {
  "$ADB" shell uiautomator dump /sdcard/e2e-ui.xml >/dev/null 2>&1 || true
  "$ADB" pull /sdcard/e2e-ui.xml "$ART_DIR/ui.xml" >/dev/null 2>&1 || true
}

# Native UI elements carry text in the uiautomator dump; returns 0 and taps
# the element's center when found.
tap_native_if_present() {
  local needle="$1" bounds nums x1 y1 x2 y2 cx cy
  dump_ui
  bounds=$(grep -o "text=\"$needle\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" \
    "$ART_DIR/ui.xml" 2>/dev/null | head -1 |
    grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' || true)
  [[ -n "$bounds" ]] || return 1
  nums=$(echo "$bounds" | grep -o '[0-9]\+' | tr '\n' ' ')
  read -r x1 y1 x2 y2 <<< "$nums"
  cx=$(( (x1 + x2) / 2 )); cy=$(( (y1 + y2) / 2 ))
  tap "$cx $cy"
  echo "  ✓ tapped native '$needle' at $cx,$cy"
  return 0
}

# Cold starts on a freshly cleared emulator occasionally trip the ANR
# dialog (Impeller shader compilation); handle it the way a human would.
dismiss_anr() {
  dump_ui
  if grep -q "isn't responding" "$ART_DIR/ui.xml" 2>/dev/null; then
    echo "  ⚠ ANR dialog — tapping Wait"
    tap_native_if_present "Wait" || tap "322 1396"
    sleep 4
  fi
}

# Picks the voucher PDF in the SAF picker, navigating Recent → drawer →
# Downloads when pm clear reset the picker's memory.
saf_pick_pdf() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8; do
    dismiss_anr
    if tap_native_if_present "$DEVICE_PDF_NAME"; then return 0; fi
    if tap_native_if_present "Downloads"; then sleep 3; continue; fi
    dump_ui
    if grep -q "Manual check" "$ART_DIR/ui.xml" 2>/dev/null; then
      echo "  ⚠ manual check open — closing"
      tap_native_if_present "Close" || "$ADB" shell input keyevent 4
      sleep 3; continue
    fi
    if grep -q "Try out your stylus" "$ART_DIR/ui.xml" 2>/dev/null; then
      echo "  ⚠ stylus panel — dismissing"
      tap_native_if_present "Cancel" || "$ADB" shell input keyevent 4
      sleep 3; continue
    fi
    if grep -q "Scan a gift card\|No active cards\|active card" "$ART_DIR/ui.xml" 2>/dev/null; then
      echo "  ⚠ app visible but not in SAF — re-entering picker"
      tap "$TAP_SCAN_TAB"; sleep 3
      tap "$TAP_MODE_FILE"; sleep 6
      continue
    fi
    tap "72 202"   # hamburger menu
    sleep 3
  done
  fail "voucher PDF not reachable in the SAF picker"
}

# Prints "x y" tap coordinates for a UI node, found adaptively:
#   tap_ui "Enable protection"  → by text or content-desc
#   tap_ui "edit:1"             → the 2nd EditText field (0-based)
# Handles Flutter's variable IME layouts — no fixed coordinates.
tap_ui() {
  local selector="$1"
  dump_ui
  python3 - "$selector" "$ART_DIR/ui.xml" << 'PYINNER'
import re, sys
selector, path = sys.argv[1], sys.argv[2]
s = open(path, encoding='utf-8', errors='ignore').read()
if selector.startswith('edit:'):
    idx = int(selector.split(':')[1])
    fields = re.findall(
        r'class="android\.widget\.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', s)
    if idx < len(fields):
        x1, y1, x2, y2 = map(int, fields[idx])
        print(f"{(x1 + x2) // 2} {(y1 + y2) // 2}")
else:
    for pat in (f'content-desc="{selector}"', f'text="{selector}"'):
        m = re.search(re.escape(pat) + r'[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', s)
        if m:
            x1, y1, x2, y2 = map(int, m.groups())
            print(f"{(x1 + x2) // 2} {(y1 + y2) // 2}")
            break
PYINNER
}

do_setup() {
  local attempt pos
  for attempt in 1 2 3; do
    adb logcat -c || true
    dismiss_anr
    pos=$(tap_ui "edit:0"); tap "${pos:-540 1104}"; sleep 1
    text "$APP_PIN"; sleep 1
    pos=$(tap_ui "edit:1"); tap "${pos:-540 1376}"; sleep 1
    text "$APP_PIN"; sleep 1
    pos=$(tap_ui "Enable protection"); tap "${pos:-540 1878}"; sleep 5
    dismiss_anr
    if wait_marker "E2E: wallet setup done" 25; then return 0; fi
    echo "  retrying setup…"
  done
  fail "wallet setup did not complete"
}

UNLOCK_SEQ=0
REPLAY_SEQ=0
PICK_SEQ=0

unlock_wallet() {
  local attempt target=$(( UNLOCK_SEQ + 1 )) pos
  for attempt in 1 2 3; do
    dismiss_anr
    pos=$(tap_ui "edit:0"); tap "${pos:-540 1296}"; sleep 1
    text "$APP_PIN"; sleep 1
    pos=$(tap_ui "Unlock"); tap "${pos:-540 1570}"; sleep 4
    dismiss_anr
    if wait_marker_count "E2E: wallet unlocked" "$target" 25; then
      UNLOCK_SEQ=$target
      return 0
    fi
    echo "  retrying unlock…"
  done
  fail "wallet did not unlock"
}

pick_pdf() {
  tap "$TAP_SCAN_TAB"; sleep 4
  tap "$TAP_MODE_FILE"; sleep 7
  saf_pick_pdf
  sleep 6
  PICK_SEQ=$(( PICK_SEQ + 1 ))
}

"$ADB" start-server >/dev/null 2>&1 || true

if [[ -z "$DEVICE" ]]; then
  # Default to an emulator, never a personal device — the run wipes the
  # app's data and taps blindly. Pass an explicit serial to target a phone.
  DEVICE=$("$ADB" devices | awk 'NR>1 && $1 ~ /^emulator-/ && $2 == "device" {print $1; exit}')
fi
[[ -n "$DEVICE" ]] || fail "no emulator connected — start one first (flutter emulators --launch <id>), or pass a device serial"
ADB_ARGS=()
[[ -n "$DEVICE" ]] && ADB_ARGS=(-s "$DEVICE")
adb() { "$ADB" "${ADB_ARGS[@]}" "$@"; }

# The default 256KB ring buffer evicts earlier markers within a couple of
# minutes (the device logs constantly); widen it so count-based waits work.
adb logcat -G 4M >/dev/null 2>&1 || true

# Disable every soft keyboard for the run: with no IME no input window can
# pop up (Google voice typing otherwise hijacks the bottom of the screen),
# so every tap coordinate is deterministic, and `input text` still fills
# focused fields (it injects characters directly, no IME involved).
# All keyboards are re-enabled on exit.
IME_IDS=$(adb shell ime list -s 2>/dev/null || true)
restore_ime() {
  for id in $IME_IDS; do
    adb shell ime enable "$id" >/dev/null 2>&1 || true
  done
}
if [[ -n "$IME_IDS" ]]; then
  for id in $IME_IDS; do
    adb shell ime disable "$id" >/dev/null 2>&1 || true
  done
  trap restore_ime EXIT
fi

echo "E2E smoke on $DEVICE"
if (( BUILD )); then
  echo "  building debug apk…"
  flutter build apk --debug || fail "apk build failed"
fi
[[ -f build/app/outputs/flutter-apk/app-debug.apk ]] || fail "app-debug.apk missing — run with --build"

adb install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null || fail "install failed"
adb shell pm clear "$PKG" >/dev/null || echo "  (pm clear failed — continuing)"
# pm clear resets runtime permissions; the scan tab would otherwise open
# the camera-permission dialog right before the SAF picker.
adb shell pm grant "$PKG" android.permission.CAMERA >/dev/null 2>&1 || true
adb push "$VOUCHER_PDF" "/sdcard/Download/$DEVICE_PDF_NAME" >/dev/null
adb logcat -c || true
adb shell am start -n "$ACTIVITY" >/dev/null || fail "app start failed"
sleep 12
dismiss_anr
shot 01-setup

# --- 1. PIN setup ----------------------------------------------------------
do_setup
shot 02-wallet

# --- 2. PDF import: scan tab → picker → unlock → replay sheet --------------
pick_pdf
unlock_wallet
wait_marker_count "E2E: pdf extracted" "$PICK_SEQ" 15 || fail "pdf import did not extract"
REPLAY_SEQ=$(( REPLAY_SEQ + 1 ))
wait_marker_count "E2E: replay sheet opened" "$REPLAY_SEQ" 30 || fail "import sheet did not replay"
shot 03-import-sheet

# --- 3. Online check → save (auto-retry inside the app shifts the timing) --
tap "$TAP_CHECK"
wait_marker "CHECK RESULT" 240 || fail "online check did not return (WAF or network)"
shot 04-check-failed
# The app runs up to two full ladders before showing "Save anyway", and
# auto-saves on success — keep offering the save until it persists. Tap by
# uiautomator bounds, never blind: "Open balance page" sits right below.
SAVED=0
for i in $(seq 1 12); do
  if adb logcat -d 2>/dev/null | grep "I flutter" | grep -q "E2E: card saved"; then
    SAVED=1; break
  fi
  if tap_native_if_present "Save anyway"; then
    sleep 6
  elif tap_ui "Save anyway"; then
    sleep 6
  else
    tap "$TAP_SAVE_ANYWAY"; sleep 6
  fi
done
[[ "$SAVED" == "1" ]] || fail "save anyway did not persist"
shot 05-wallet-with-card

# --- 4. Duplicate re-import is blocked -------------------------------------
pick_pdf
unlock_wallet
REPLAY_SEQ=$(( REPLAY_SEQ + 1 ))
wait_marker_count "E2E: replay sheet opened" "$REPLAY_SEQ" 30 || fail "import sheet did not replay"
wait_marker "duplicate blocked" 15 || fail "duplicate import was not blocked"
shot 06-duplicate-blocked

echo "PASS — all markers seen. Artifacts in $ART_DIR"
