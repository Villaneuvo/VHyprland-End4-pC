# Fisher plugins live outside ~/.config/fish: dots-hyprland's install syncs that dir with --delete
# (only conf.d is spared), which would wipe functions/ and completions/ on every ii update.
set -g fisher_path $HOME/.local/share/fisher
set fish_function_path $fish_function_path[1] $fisher_path/functions $fish_function_path[2..-1]
set fish_complete_path $fish_complete_path[1] $fisher_path/completions $fish_complete_path[2..-1]

# Global (not universal) so it survives ii wiping fish_variables; must be set before nvm.fish's conf.d runs
set -g nvm_default_version v24.21.0

for file in $fisher_path/conf.d/*.fish
    source $file
end
