#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

grep -qxF helix "$ROOT/install/omarchy-base.packages" || fail "base packages include Helix"
grep -qxF yazi "$ROOT/install/omarchy-base.packages" || fail "base packages include Yazi"
grep -qxF chafa "$ROOT/install/omarchy-base.packages" || fail "base packages include Yazi and Lazycut previews"
if grep -qxE 'nvim|omarchy-nvim' "$ROOT/install/omarchy-base.packages"; then
  fail "base packages no longer ship Neovim"
fi
pass "base packages ship the Helix and Yazi toolchain"

python3 - "$ROOT" <<'PY'
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
for relative in (
  "config/helix/config.toml",
  "config/yazi/yazi.toml",
  "config/yazi/keymap.toml",
):
  with (root / relative).open("rb") as config:
    tomllib.load(config)
PY
lua -e 'local _, err = loadfile(arg[1]); assert(not err, err); os.exit(0)' "$ROOT/config/yazi/init.lua"
pass "Helix and Yazi defaults have valid syntax"

grep -qxF 'inode/directory=yazi.desktop' "$ROOT/default/applications/mimeapps.list" || fail "Yazi is the directory MIME default"
if grep -qF '=nvim.desktop' "$ROOT/default/applications/mimeapps.list"; then
  fail "text MIME defaults no longer use Neovim"
fi
grep -qxF 'text/plain=Helix.desktop' "$ROOT/default/applications/mimeapps.list" || fail "Helix is the text MIME default"
pass "desktop MIME defaults use Helix and Yazi"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/home" "$tmpdir/bin"

cat >"$tmpdir/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
command -v "$1" >/dev/null 2>&1
SH
cat >"$tmpdir/bin/helix" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_OUTPUT"
SH
cat >"$tmpdir/bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$TEST_OUTPUT"
SH
cat >"$tmpdir/bin/omarchy-cmd-terminal-cwd" <<'SH'
#!/bin/bash
printf '%s\n' "$TEST_CWD"
SH
cat >"$tmpdir/bin/yazi" <<'SH'
#!/bin/bash
for arg in "$@"; do
  if [[ $arg == --cwd-file=* ]]; then
    printf '%s' "$TEST_CWD" >"${arg#*=}"
  fi
done
SH
chmod +x "$tmpdir/bin"/*

editor=$(HOME="$tmpdir/home" PATH="$tmpdir/bin:$ROOT/bin:$PATH" omarchy-default-editor)
[[ $editor == "helix" ]] || fail "Helix is the editor fallback" "actual: $editor"
pass "Helix is the default editor"

TEST_OUTPUT="$tmpdir/editor-output" HOME="$tmpdir/home" PATH="$tmpdir/bin:$ROOT/bin:$PATH" omarchy-launch-editor --inline "two words.txt"
[[ $(cat "$tmpdir/editor-output") == "two words.txt" ]] || fail "editor launcher preserves path arguments"
pass "editor launcher falls back to Helix"

TEST_OUTPUT="$tmpdir/yazi-output" HOME="$tmpdir/home" PATH="$tmpdir/bin:$ROOT/bin:$PATH" omarchy-launch-yazi
mapfile -t yazi_args <"$tmpdir/yazi-output"
[[ ${yazi_args[0]} == "yazi" && ${yazi_args[1]} == "$tmpdir/home" ]] || fail "Yazi launcher opens the home directory"

TEST_OUTPUT="$tmpdir/yazi-cwd-output" TEST_CWD="$tmpdir/home/cwd with spaces" HOME="$tmpdir/home" PATH="$tmpdir/bin:$ROOT/bin:$PATH" omarchy-launch-yazi-cwd
mapfile -t yazi_cwd_args <"$tmpdir/yazi-cwd-output"
[[ ${yazi_cwd_args[0]} == "yazi" && ${yazi_cwd_args[1]} == "$tmpdir/home/cwd with spaces" ]] || fail "Yazi cwd launcher preserves spaces"
pass "Yazi launchers preserve their target directories"

mkdir -p "$tmpdir/start" "$tmpdir/selected directory"
shell_cwd=$(TEST_CWD="$tmpdir/selected directory" HOME="$tmpdir/home" PATH="$tmpdir/bin:$ROOT/bin:$PATH" TERM=dumb bash -c '
  source "$1"
  builtin cd "$2"
  y
  pwd
' bash "$ROOT/default/bash/aliases" "$tmpdir/start")
[[ $shell_cwd == "$tmpdir/selected directory" ]] || fail "Yazi shell wrapper changes to the selected directory"
pass "Yazi shell wrapper carries the selected directory back to Bash"

migration_home="$tmpdir/migration-home"
mkdir -p "$migration_home/.config" "$migration_home/.local/state/omarchy/defaults"
cat >"$migration_home/.config/mimeapps.list" <<'EOF'
[Default Applications]
inode/directory=org.gnome.Nautilus.desktop
text/plain=nvim.desktop
EOF
printf '%s\n' nvim >"$migration_home/.local/state/omarchy/defaults/editor"

cat >"$tmpdir/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$tmpdir/bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$tmpdir/bin/omarchy-pkg-add" "$tmpdir/bin/omarchy-pkg-drop"

HOME="$migration_home" OMARCHY_PATH="$ROOT" PATH="$tmpdir/bin:$ROOT/bin:$PATH" bash -euo pipefail "$ROOT/migrations/1784820442.sh" >/dev/null
[[ $(cat "$migration_home/.local/state/omarchy/defaults/editor") == "helix" ]] || fail "migration selects Helix"
[[ -f $migration_home/.config/helix/config.toml ]] || fail "migration seeds Helix config"
[[ -f $migration_home/.config/yazi/yazi.toml && -f $migration_home/.config/yazi/keymap.toml && -f $migration_home/.config/yazi/init.lua ]] || fail "migration seeds Yazi config"
grep -qxF 'inode/directory=yazi.desktop' "$migration_home/.config/mimeapps.list" || fail "migration selects Yazi MIME default"
grep -qxF 'text/plain=Helix.desktop' "$migration_home/.config/mimeapps.list" || fail "migration selects Helix MIME default"
pass "migration updates existing Omarchy editor and file-manager defaults"
