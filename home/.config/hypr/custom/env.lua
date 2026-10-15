-- Intel+NVIDIA laptop: render Hyprland on the iGPU, keep the dGPU for outputs wired to it.
-- The /dev/dri/*-gpu symlinks come from /etc/udev/rules.d/61-hypr-gpu.rules (made by install.sh);
-- only list the ones that exist, so this file is safe on machines without them.
local gpus = {}
for _, dev in ipairs({ "/dev/dri/intel-igpu", "/dev/dri/nvidia-dgpu" }) do
    if is_file_exists(dev) then table.insert(gpus, dev) end
end
if #gpus > 0 then hl.env("AQ_DRM_DEVICES", table.concat(gpus, ":")) end

-- gcr-ssh-agent socket (already enabled system-wide); plain Hyprland sessions may not export it
hl.env("SSH_AUTH_SOCK", os.getenv("XDG_RUNTIME_DIR") .. "/gcr/ssh")
