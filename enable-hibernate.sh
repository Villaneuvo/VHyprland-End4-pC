#!/usr/bin/env bash
# Opt-in: enable hibernation on Ubuntu 26.04 (not run by install.sh; it depends on the hardware).
# What it does (all reversible, see README "Hibernate"):
#   1. a second swap file /swap-hibernate.img (default 32G, bigger than RAM), highest priority
#   2. a polkit rule that overrides Ubuntu's "no hibernate" rule for the active local user
#   3. dracut's resume module in the initramfs of the running kernel (old initramfs kept as *.pre-hibernate)
# systemd >= 255 on EFI records the resume location in an EFI variable, so no kernel parameters are needed.
# Test it once, with your work saved: `systemctl hibernate`.
set -euo pipefail
SIZE=${SIZE:-32G}
K=$(uname -r)

[ -d /sys/firmware/efi ] || { echo "Needs an EFI boot (resume location is passed through an EFI variable)."; exit 1; }
grep -q '\[none\]' /sys/kernel/security/lockdown 2>/dev/null || [ ! -e /sys/kernel/security/lockdown ] ||
    { echo "Kernel lockdown is on (Secure Boot?): the kernel refuses to hibernate."; exit 1; }
sudo -v

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
echo 'add_dracutmodules+=" resume "' | sudo tee /etc/dracut.conf.d/90-hibernate-resume.conf >/dev/null
sudo update-initramfs -u -k "$K"
# The new initramfs must still unlock LUKS/LVM and must now contain the resume service
for m in crypt lvm systemd-cryptsetup resume; do
    sudo lsinitrd "$I" | sed -n '/dracut modules:/,/^=/p' | grep -qx "$m" ||
        { echo "Module '$m' missing from $I. Restoring the previous initramfs."; sudo cp -a "$I.pre-hibernate" "$I"; exit 1; }
done
sudo lsinitrd "$I" | grep -q systemd-hibernate-resume.service ||
    { echo "systemd-hibernate-resume missing. Restoring the previous initramfs."; sudo cp -a "$I.pre-hibernate" "$I"; exit 1; }

echo "CanHibernate: $(busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate)"
echo "Done. Save your work, then test once with: systemctl hibernate"
