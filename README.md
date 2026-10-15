# hyprland-dotfiles

My Hyprland desktop on **Ubuntu 26.04**: [illogical-impulse](https://github.com/end-4/dots-hyprland) with the
[end4-pC](https://github.com/pctrade/end4-pC) shell, the **himeko** preset (Honkai: Star Rail), and a set of fixes
and extras that make it behave like a complete desktop on Ubuntu.

## New machine

```bash
sudo apt install gh && gh auth login     # the repo is private: log in first (GitHub.com → HTTPS → browser)
gh repo clone Villaneuvo/hyprland-dotfiles ~/hyprland-dotfiles
cd ~/hyprland-dotfiles
./install.sh
```

Run it **from a terminal inside your normal (GNOME) session**, as your user. It asks for your sudo password,
takes a while (it builds Quickshell), and is safe to re-run. When it finishes, log out and pick the
**Hyprland** session on the login screen (not "Hyprland (uwsm-managed)").

After that, set the AI sidebar keys again (`Super+A`, then `/key`): keys live in the keyring, not in this repo.

## Keeping the repo up to date

```bash
cd ~/hyprland-dotfiles
./sync.sh                       # copies the live files listed in manifest.txt into home/
git commit -m "Update dotfiles" && git push
```

On another machine: `git pull && ./install.sh files` copies only the config files.

## What install.sh does

| Step | Why |
|---|---|
| PPAs `cppiber/hyprland`, `marin-m/songrec` (keys in `keys/`) | Ubuntu ships Hyprland 0.53; the Lua config needs ≥ 0.55. SongRec isn't in Ubuntu. |
| apt packages from `packages.txt` | Everything dots-hyprland's Arch packages would pull in, mapped to Ubuntu names. Removes Ubuntu's `libudis86-0` first: the PPA's `libudis86.1` clashes with it. |
| Builds Quickshell at the commit dots-hyprland pins | Not packaged for Ubuntu. Built with Ubuntu's QML path and without the crash handler (no `cpptrace`). |
| uv, matugen, Material Symbols / Rubik / Readex Pro / JetBrains Mono Nerd fonts, adw-gtk3, Darkly | Not in Ubuntu's repos. |
| dots-hyprland `./setup install --skip-alldeps` with a local `os-release` saying `ID=arch` | Its installer forces a broken Nix route on Ubuntu. |
| Patches ii (`FluentWinUI3` import) and end4-pC (`var double`) | Ubuntu's Qt 6.10 rejects both; the shells don't load otherwise. `custom/scripts/end4pc-qt610-fix.sh` re-applies the end4-pC patch at every login, because end4-pC's updater re-clones itself. |
| Copies `home/` (see `manifest.txt`) | All the customizations below. Replaced files are backed up to `~/.dotfiles-backup/`. |
| Masks `waybar`, `swaync`, `hypridle`, `hyprsunset` user services | They start via `graphical-session.target` and fight end4-pC or duplicate ii's autostart. |
| `plasma-applications.menu` symlink | Dolphin's "Open with" list is empty without it. |
| Intel + NVIDIA laptops: udev rule for `/dev/dri/intel-igpu` and `nvidia-dgpu` | Hyprland renders on the iGPU (`custom/env.lua`). Skipped on other hardware. |
| fisher + nvm.fish, nwg-displays 0.4.4 (venv), mpvpaper | Node in fish, advanced monitor settings (Ubuntu's 0.3.x can't write Lua), video wallpapers. |

Pinned versions (top of `install.sh`): dots-hyprland `2f2a376`, end4-pC `96b45aa`, matugen 4.2.0, nwg-displays 0.4.4.
Try newer ones with `DOTS_REF=main END4_REF=main ./install.sh`, at your own risk: newer upstream may need a newer Hyprland/Qt than Ubuntu has.

## What's customized

Everything lives in files dots-hyprland never overwrites (`~/.config/hypr/custom/`, `monitors.lua`, `xdph.conf`, fish `conf.d`).

**Keys and UI**
- `Super+Esc`: end4-pC settings / dashboard (presets, wallpapers)
- `Super+Alt+P`: **Display Navigation**, a Win+P style picker (PC only / Duplicate / Extend / Second screen only), Himeko themed
- **Display Settings** (launcher): drag-to-arrange monitors, resolution, refresh rate, scale, orientation, on/off,
  **primary display** (workspace 1 + cursor start there), **Identify** (big number on each screen), auto-revert after 15 s
- `Super+Alt+Shift+P`: reset displays to the configured layout
- Volume keys play GNOME's tick; `Print`, `Ctrl+Print` and `Super+Shift+S` all notify and play a shutter;
  `Super+Shift+S` also saves to `~/Pictures/Screenshots`

**Autostart (`custom/execs.lua`)**: hyprsunset, notification sounds, screenshot notifications, SMART disk warnings,
USB automount (udiskie), evolution alarms, update-notifier, a GNOME-compatible idle-time service for apps like
GajiHub TimeTracker (`custom/scripts/idle-monitor-shim.py`, physical input only).

**Other**
- `xdph.conf`: `force_shm` (screen sharing works on Intel+NVIDIA), restore token pre-ticked
- `hyprland-mimeapps.list`: Image Viewer for images, VLC for video (GNOME's own list is ignored under Hyprland)
- fish: same PATH as `.zshrc`, nvm.fish in `~/.local/share/fisher` (dots-hyprland wipes `~/.config/fish/functions`)
- end4-pC: himeko preset, sounds on, `apt` update command, Gemini 3.8 Flash (high thinking) in the AI sidebar

## Machine-specific bits

- `home/.config/hypr/monitors.lua` holds this laptop's layout (LG ULTRAGEAR above the built-in screen). Harmless
  elsewhere: unknown monitors fall back to automatic placement. Use **Display Settings** to redo it.
- GajiHub TimeTracker is not included: download its AppImage to `~/Applications/` and add a launcher.

## Troubleshooting

- **Bar, wallpaper and widgets gone** after updating end4-pC: log out and back in, or run
  `~/.config/hypr/custom/scripts/end4pc-qt610-fix.sh`.
- **After updating dots-hyprland** (`./setup install`): it resyncs `~/.config/quickshell`, which deletes end4-pC.
  Run `./install.sh` again (it re-clones and re-patches).
- **apt upgraded Qt**: rebuild Quickshell (delete `~/src/quickshell/build`, re-run `./install.sh`).
- Check the Hyprland config: `Hyprland --verify-config`. Shell logs: `qs log -c end4-pC`.

## Credits

end-4 (illogical-impulse), pctrade (end4-pC), the end4-pC presets community (himeko preset by @Blapples).
Himeko artwork © its creators / HoYoverse; kept here for personal use, which is one reason this repo is private.
