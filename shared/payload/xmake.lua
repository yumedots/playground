function shared.payload_inputs(os)
    if not shared.dotfiles or not os.isdir(shared.dotfiles) then
        os.raise("dotfiles source missing or submodule not populated: " .. tostring(shared.dotfiles))
    end
    local lines = {}
    for _, file in ipairs(os.files(path.join(shared.dotfiles, "**"))) do
        lines[#lines + 1] = file .. " " .. tostring(os.filesize(file)) .. " " .. tostring(os.mtime(file))
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

function shared.payload_build(os, find_tool, io)
    if os.isdir(shared.payloadstage) then
        os.rmdir(shared.payloadstage)
    end
    os.mkdir(path.join(shared.payloadstage, "dotfiles"))
    os.execv("sh", {"-c", "tar -cf - --exclude=.git --exclude=.DS_Store -C '" .. shared.dotfiles ..
        "' . | tar -xf - -C '" .. path.join(shared.payloadstage, "dotfiles") .. "'"})
    local stage = path.join(shared.payloadstage, "dotfiles")
    local patch = path.join(shared.projectdir, "patches/hyprlandLooknfeel.patch")
    if os.isfile(patch) then
        os.execv("sh", {"-c", "cd '" .. stage .. "' && patch -p1 -N -s -i " .. patch .. " >/dev/null 2>&1 || true"})
    end
    os.execv("python3", {path.join(shared.projectdir, "scripts/preparePayload.py"), stage})
    local mke2fs = shared.mke2fs(find_tool)
    if not mke2fs then
        os.raise("mke2fs not found, install e2fsprogs")
    end
    local started = os.time()
    os.rm(shared.payloadfile)
    os.execv(shared.qemu_img(os, find_tool), {"create", "-f", "raw", shared.payloadfile, "1G"})
    os.execv(mke2fs, {"-t", "ext4", "-F", "-L", "payload", "-d", shared.payloadstage, shared.payloadfile})
    os.rmdir(shared.payloadstage)
    io.writefile(shared.payloadkeyfile, shared.payload_inputs(os) .. "\n")
    print("payload " .. shared.payloadfile .. " ready in " .. (os.time() - started) .. "s")
end

function shared.payload_ensure(os, find_tool, io)
    local key = os.isfile(shared.payloadkeyfile) and io.readfile(shared.payloadkeyfile):trim() or ""
    if os.isfile(shared.payloadfile) and key == shared.payload_inputs(os) then
        return
    end
    shared.payload_build(os, find_tool, io)
end
