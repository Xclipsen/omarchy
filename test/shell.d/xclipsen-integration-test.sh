#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
native_pid=""
replay_pid=""
trap '[[ -z $native_pid ]] || kill "$native_pid" 2>/dev/null || true; [[ -z $replay_pid ]] || kill "$replay_pid" 2>/dev/null || true; rm -rf "$tmp"' EXIT

stub_bin="$tmp/bin"
mkdir -p "$stub_bin" "$tmp/home/Videos" "$tmp/runtime/omarchy/screenrecording"
chmod 0700 "$tmp/runtime" "$tmp/runtime/omarchy" "$tmp/runtime/omarchy/screenrecording"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
command -v "$1" >/dev/null
SH

cat >"$stub_bin/gh" <<'SH'
#!/bin/bash
set -euo pipefail
asset=""
directory=""
while (($# > 0)); do
  case $1 in
    --pattern) asset=$2; shift 2 ;;
    --dir) directory=$2; shift 2 ;;
    *) shift ;;
  esac
done
printf 'verified package payload' >"$directory/$asset"
SH

cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$PKEXEC_LOG"
if [[ ${PKEXEC_MUTATE_SOURCE:-false} == "true" ]]; then
  source_file=${@: -3:1}
  printf '%s\n' changed >"$source_file"
fi
privileged_script=${3/export PATH=\/usr\/bin:\/bin/export PATH=$TEST_ROOT_PATH}
"$1" "$2" "$privileged_script" "${@:4}"
SH

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$PACMAN_LOG"
exit 0
SH
cat >"$stub_bin/bsdtar" <<'SH'
#!/bin/bash
printf 'pkgname = %s\n' "${FAKE_ARCHIVE_PACKAGE:-example}"
SH
chmod +x "$stub_bin"/*

asset=example-1.0.0-1-any.pkg.tar.zst
digest=$(printf 'verified package payload' | sha256sum | cut -d' ' -f1)
export PKEXEC_LOG="$tmp/pkexec.log"
export PACMAN_LOG="$tmp/pacman.log"
export TEST_ROOT_PATH="$stub_bin:/usr/bin"

PATH="$stub_bin:/usr/bin" bash "$ROOT/bin/omarchy-pkg-github-release-add" \
  Xclipsen/example v1.0.0 "$asset" "$digest" example

[[ -s $PKEXEC_LOG ]] || fail "checksum-pinned GitHub package invokes pkexec after verification"
grep -q -- "-U --noconfirm --needed" "$PACMAN_LOG" || fail "GitHub package helper installs the root-owned archive"
grep -q 'Package changed before privileged installation' "$PKEXEC_LOG" || fail "privileged package install repeats checksum verification"
grep -q 'Unexpected package identity' "$PKEXEC_LOG" || fail "privileged package install verifies archive identity"
pass "checksum-pinned GitHub release package reaches pacman"

rm -f "$PKEXEC_LOG"
if PATH="$stub_bin:/usr/bin" bash "$ROOT/bin/omarchy-pkg-github-release-add" \
  Xclipsen/example v1.0.0 "$asset" "$(printf '0%.0s' {1..64})" example >/dev/null 2>&1; then
  fail "GitHub package helper rejects a checksum mismatch"
fi
[[ ! -e $PKEXEC_LOG ]] || fail "checksum mismatch must fail before privilege escalation"
pass "checksum mismatch fails before pkexec"

rm -f "$PKEXEC_LOG"
export PKEXEC_MUTATE_SOURCE=true
if PATH="$stub_bin:/usr/bin" bash "$ROOT/bin/omarchy-pkg-github-release-add" \
  Xclipsen/example v1.0.0 "$asset" "$digest" example >/dev/null 2>&1; then
  fail "root-side checksum verification should reject a changed archive"
fi
unset PKEXEC_MUTATE_SOURCE
pass "privileged verification rejects a package changed after authorization"

rm -f "$PKEXEC_LOG"
export FAKE_ARCHIVE_PACKAGE=unexpected
if PATH="$stub_bin:/usr/bin" bash "$ROOT/bin/omarchy-pkg-github-release-add" \
  Xclipsen/example v1.0.0 "$asset" "$digest" example >/dev/null 2>&1; then
  fail "package identity mismatch should fail"
fi
unset FAKE_ARCHIVE_PACKAGE
[[ ! -e $PKEXEC_LOG ]] || fail "identity mismatch must fail before privilege escalation"
pass "package identity mismatch fails before pkexec"

cat >"$stub_bin/lab-backup-setup" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$stub_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
touch "$PACKAGE_DROP_MARKER"
SH
chmod +x "$stub_bin/lab-backup-setup" "$stub_bin/omarchy-pkg-drop"
export PACKAGE_DROP_MARKER="$tmp/package-dropped"
remove_script="$tmp/omarchy-remove-service-lab-backup"
sed "s#/usr/bin/lab-backup-setup#$stub_bin/lab-backup-setup#" \
  "$ROOT/bin/omarchy-remove-service-lab-backup" >"$remove_script"
if PATH="$stub_bin:/usr/bin" bash "$remove_script"; then
  fail "cancelled Lab Backup removal should fail"
fi
[[ ! -e $PACKAGE_DROP_MARKER ]] || fail "cancelled Lab Backup removal dropped the package"
pass "cancelled Lab Backup removal preserves the package"

bash -c 'exec -a gpu-screen-recorder sleep 30' &
native_pid=$!
native_start=$(awk '{print $22}' "/proc/$native_pid/stat")
printf '%s %s\n' "$native_pid" "$native_start" >"$tmp/runtime/omarchy/screenrecording/pid"
HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/runtime" bash "$ROOT/bin/omarchy-capture-screenrecording" --status || \
  fail "screen recording status recognizes its tracked native recorder"
pass "screen recording status recognizes the tracked native PID"
kill "$native_pid"
wait "$native_pid" 2>/dev/null || true
native_pid=""

bash -c 'exec -a gsr-replay-buffer sleep 30' &
replay_pid=$!
replay_start=$(awk '{print $22}' "/proc/$replay_pid/stat")
printf '%s %s\n' "$replay_pid" "$replay_start" >"$tmp/runtime/omarchy/screenrecording/pid"
if HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/runtime" bash "$ROOT/bin/omarchy-capture-screenrecording" --status; then
  fail "screen recording status ignores the replay buffer"
fi
pass "screen recording status ignores the replay process"

printf '%s %s\n' "$replay_pid" "$((replay_start + 1))" >"$tmp/runtime/omarchy/screenrecording/pid"
if HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/runtime" bash "$ROOT/bin/omarchy-capture-screenrecording" --status; then
  fail "screen recording status accepts a reused PID with the wrong start time"
fi
pass "screen recording state rejects reused PIDs"

mkdir -p "$tmp/unsafe-runtime"
chmod 0777 "$tmp/unsafe-runtime"
if HOME="$tmp/home" XDG_RUNTIME_DIR="$tmp/unsafe-runtime" bash "$ROOT/bin/omarchy-capture-screenrecording" --status >/dev/null 2>&1; then
  fail "screen recording should reject a shared runtime directory"
fi
pass "screen recording rejects shared runtime state"

grep -q 'gpu-screen-recorder .*9>&-' "$ROOT/bin/omarchy-capture-screenrecording" || \
  fail "screen recorder child inherits the state lock"
pass "screen recorder child closes the state lock descriptor"

if grep -R -E "(pgrep|pkill|killall).*gpu-screen-recorder" \
  "$ROOT/bin/omarchy-capture-screenrecording" \
  "$ROOT/shell/plugins/bar/indicators/ScreenRecording.qml" \
  "$ROOT/default/omarchy/omarchy-menu.jsonc"; then
  fail "screen recording integration contains a broad recorder process match"
fi
pass "screen recording integration has no broad recorder process match"

for command in \
  omarchy-capture-replay \
  omarchy-install-service-lab-backup \
  omarchy-remove-service-lab-backup \
  omarchy-setup-lab-backup \
  omarchy-install-gaming-gsr-replay \
  omarchy-remove-gaming-gsr-replay \
  omarchy-setup-gsr-replay; do
  [[ -x $ROOT/bin/$command ]] || fail "$command is executable"
done
pass "Xclipsen integration commands are executable"

grep -q '/usr/bin/lab-backup-setup' "$ROOT/bin/omarchy-setup-lab-backup" || \
  fail "Lab Backup setup does not use the packaged absolute path"
grep -q 'E81E0C941E0C5DC6' "$ROOT/bin/omarchy-setup-gsr-replay" || \
  fail "GSR Replay setup does not pin the Toshiba filesystem UUID"
grep -q 'GSR_REPLAY_ENFORCED_FS_UUID' "$ROOT/bin/omarchy-setup-gsr-replay" || \
  fail "GSR Replay setup does not persist the required filesystem UUID"
grep -q 'gsr-replay-configured' "$ROOT/bin/omarchy-installed-service-gsr-replay" || \
  fail "GSR Replay controls do not require completed setup"
grep -q 'verify-output.*E81E0C941E0C5DC6' "$ROOT/bin/omarchy-installed-service-gsr-replay" || \
  fail "GSR Replay controls do not verify configured storage"
pass "packaged helpers and Toshiba filesystem identity are pinned"

menu="$ROOT/default/omarchy/omarchy-menu.jsonc"
for id in \
  install.service.lab-backup \
  setup.lab-backup \
  remove.service.lab-backup \
  install.gaming.gsr-replay \
  setup.gsr-replay \
  remove.gaming.gsr-replay \
  trigger.capture.replay-save \
  trigger.capture.replay-toggle; do
  grep -q "\"$id\"" "$menu" || fail "menu contains $id"
done
pass "menu exposes Lab Backup and GSR Replay lifecycle actions"

grep -q '"when":"omarchy-installed-service-gsr-replay"' "$menu" || \
  fail "replay controls are visible before validated setup"
pass "replay controls require validated setup"

grep -q 'omarchy-capture-replay toggle' "$ROOT/shell/plugins/bar/widgets/GsrReplay.qml" || \
  fail "GSR Replay widget bypasses validated replay controls"
! grep -q 'runAction("/usr/bin/gsr-replay' "$ROOT/shell/plugins/bar/widgets/GsrReplay.qml" || \
  fail "GSR Replay widget invokes the recorder directly"
pass "GSR Replay widget routes actions through storage validation"

grep -q '"id": "omarchy.gsr-replay"' "$ROOT/shell/plugins/bar/widgets/GsrReplay.manifest.json" || \
  fail "GSR Replay widget manifest is discoverable"
pass "GSR Replay widget is manifest-backed"
