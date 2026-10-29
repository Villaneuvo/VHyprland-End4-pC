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

-- Super tapped alone toggles ii's search on its release ("searchToggleRelease"); a Super combo must interrupt that, or
-- releasing Super after Super+V / Super+. closes the overview it just opened (Hyprland 0.57 sends that release even
-- after a combo). ii's old config interrupted with a catchall bind, which Lua allows only in submaps, so every
-- Super + key bind made from here on also sends the interrupt. Loaded before hyprland/keybinds.lua for that reason.
local bind = hl.bind
hl.bind = function(keys, action, opts)
    local result = bind(keys, action, opts)
    if type(keys) == "string" then
        local parts = {}
        for p in keys:gmatch("[^+%s]+") do table.insert(parts, p) end
        local key, super = parts[#parts], false
        for i = 1, #parts - 1 do if parts[i] == "SUPER" then super = true end end
        if super and key ~= "SUPER_L" and key ~= "SUPER_R" and not key:match("^mouse") then
            bind(keys, hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
        end
    end
    return result
end
