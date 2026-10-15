#!/usr/bin/env bash
# Opt-in: enable hibernation on Ubuntu 26.04 (not run by install.sh; it depends on the hardware).
# What it does (all reversible, see README "Hibernate"):
#   1. a second swap file /swap-hibernate.img (default 32G, bigger than RAM), highest priority
#   2. a polkit rule that overrides Ubuntu's "no hibernate" rule for the active local user
#   3. dracut's resume module + lz4 in the initramfs of the running kernel (old initramfs kept as *.pre-hibernate)
#   4. lz4 instead of lzo for the image: faster to write, much faster to read back on resume
#   5. Sleep = suspend-then-hibernate: lid, sleep key, Super+Shift+L and the session menu suspend at once and
#      hibernate after $DELAY (Hibernate in the session menu still hibernates straight away)
# systemd >= 255 on EFI records the resume location in an EFI variable, so no kernel parameters are needed.
# Test it once, with your work saved: `systemctl hibernate`.
set -euo pipefail
SIZE=${SIZE:-32G}
DELAY=${DELAY:-2h}
K=$(uname -r)

[ -d /sys/firmware/efi ] || { echo "Needs an EFI boot (resume location is passed through an EFI variable)."; exit 1; }
grep -q '\[none\]' /sys/kernel/security/lockdown 2>/dev/null || [ ! -e /sys/kernel/security/lockdown ] ||
    { echo "Kernel lockdown is on (Secure Boot?): the kernel refuses to hibernate."; exit 1; }
sudo true # asks for the password once (sudo -v would ask even with NOPASSWD)

if [ ! -f /swap-hibernate.img ]; then
    sudo fallocate -l "$SIZE" /swap-hibernate.img
    sudo chmod 600 /swap-hibernate.img
    sudo mkswap -L hibernate /swap-hibernate.img >/dev/null
fi
grep -q '^/swap-hibernate.img' /etc/fstab || printf '/swap-hibernate.img\tnone\tswap\tsw,pri=10\t0\t0\n' | sudo tee -a /etc/fstab >/dev/null
swapon --show=NAME --noheadings | grep -q swap-hibernate || sudo swapon --priority 10 /swap-hibernate.img

sudo tee /etc/polkit-1/rules.d/40-allow-hibernate.rules >/dev/null <<'EOF'
// Ubuntu blocks hibernation in /usr/share/polkit-1/rules.d/com.ubuntu.desktop.rules.
// Rules run in file-name order, so this one answers first: allow it for the active, local user.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.login1.hibernate" ||
         action.id == "org.freedesktop.login1.handle-hibernate-key" ||
         action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
         action.id == "org.freedesktop.upower.hibernate") &&
        subject.active && subject.local) {
        return polkit.Result.YES;
    }
});
EOF

I=/boot/initrd.img-$K
[ -f "$I.pre-hibernate" ] || sudo cp -a "$I" "$I.pre-hibernate"
# lz4 is a module on Ubuntu: the initramfs needs it to read an lz4 image back
printf '%s\n' 'add_dracutmodules+=" resume "' 'add_drivers+=" lz4 "' | sudo tee /etc/dracut.conf.d/90-hibernate-resume.conf >/dev/null
sudo update-initramfs -u -k "$K"
# The new initramfs must still unlock LUKS/LVM and must now contain the resume service and lz4.
# Read the listing once: piping lsinitrd into `grep -q` can fail under pipefail (SIGPIPE) even on a match.
L=$(sudo lsinitrd "$I")
mods=$(sed -n '/dracut modules:/,/^=/p' <<<"$L")
restore() { echo "$1 missing from $I. Restoring the previous initramfs."; sudo cp -a "$I.pre-hibernate" "$I"; exit 1; }
for m in crypt lvm systemd-cryptsetup resume; do grep -qx "$m" <<<"$mods" || restore "Module '$m'"; done
grep -q 'systemd-hibernate-resume\.service' <<<"$L" || restore "systemd-hibernate-resume"
grep -q '/crypto/lz4\.ko' <<<"$L" || restore "lz4"

# Write images with lz4 from now on (only after the initramfs above can read them)
echo 'w /sys/module/hibernate/parameters/compressor - - - - lz4' | sudo tee /etc/tmpfiles.d/hibernate-lz4.conf >/dev/null
sudo systemd-tmpfiles --create /etc/tmpfiles.d/hibernate-lz4.conf

# Sleep = suspend now, hibernate after $DELAY
sudo mkdir -p /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d
printf '[Sleep]\nHibernateDelaySec=%s\n' "$DELAY" | sudo tee /etc/systemd/sleep.conf.d/90-suspend-then-hibernate.conf >/dev/null
printf '[Login]\nHandleLidSwitch=suspend-then-hibernate\nHandleLidSwitchExternalPower=suspend-then-hibernate\nHandleSuspendKey=suspend-then-hibernate\n' |
    sudo tee /etc/systemd/logind.conf.d/90-suspend-then-hibernate.conf >/dev/null
sudo systemctl reload systemd-logind # reload, not restart: a restart ends the graphical session
# Ubuntu's NVIDIA driver ships this unit disabled; without it the dGPU isn't saved before suspend-then-hibernate
systemctl list-unit-files nvidia-suspend-then-hibernate.service >/dev/null 2>&1 &&
    sudo systemctl enable nvidia-suspend-then-hibernate.service

lc() { busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager "$1"; }
echo "CanHibernate: $(lc CanHibernate)  CanSuspendThenHibernate: $(lc CanSuspendThenHibernate)"
echo "Compressor: $(cat /sys/module/hibernate/parameters/compressor)"
echo "Done. Save your work, then test once with: systemctl hibernate"
