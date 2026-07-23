echo "Switching the default editor and file manager to Helix and Yazi"

omarchy-pkg-add helix yazi chafa ffmpeg 7zip resvg
omarchy-pkg-drop omarchy-nvim neovim

mkdir -p "$HOME/.config/helix/themes"
if [[ ! -f $HOME/.config/helix/config.toml ]]; then
  cp "$OMARCHY_PATH/config/helix/config.toml" "$HOME/.config/helix/config.toml"
fi
ln -sfn "$HOME/.local/state/omarchy/current/theme/helix.toml" "$HOME/.config/helix/themes/omarchy.toml"

mkdir -p "$HOME/.config/yazi"
for config in yazi.toml keymap.toml init.lua; do
  if [[ ! -f $HOME/.config/yazi/$config ]]; then
    cp "$OMARCHY_PATH/config/yazi/$config" "$HOME/.config/yazi/$config"
  fi
done

editor_file="$HOME/.local/state/omarchy/defaults/editor"
if [[ ! -f $editor_file ]] || grep -qxF nvim "$editor_file"; then
  mkdir -p "$(dirname "$editor_file")"
  printf '%s\n' helix >"$editor_file"
fi

mimeapps="$HOME/.config/mimeapps.list"
if [[ -f $mimeapps ]]; then
  sed -i \
    -e 's/=nvim\.desktop$/=Helix.desktop/' \
    -e 's/^inode\/directory=org\.gnome\.Nautilus\.desktop$/inode\/directory=yazi.desktop/' \
    "$mimeapps"
fi
