# Mirrors the PATH setup from ~/.zshrc so fish (kitty/foot under Hyprland) finds the same tools.
# conf.d is excluded from dots-hyprland's sync, so ii updates won't overwrite this file.

fish_add_path -g $HOME/.local/bin

# bun
set -gx BUN_INSTALL $HOME/.bun
fish_add_path -g $BUN_INSTALL/bin

# go
set -gx GOPATH $HOME/go
fish_add_path -g -a $GOPATH/bin $HOME/.local/go/bin

# pnpm
set -gx PNPM_HOME $HOME/.local/share/pnpm
fish_add_path -g $PNPM_HOME/bin

# node: managed by nvm.fish (see fisher-path.fish), separate from zsh's ~/.nvm

alias chrome google-chrome-stable
