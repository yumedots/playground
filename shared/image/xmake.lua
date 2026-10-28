function shared.image_inputs(os, io)
    local lines = {shared.disksize}
    for _, pattern in ipairs({path.join(shared.projectdir, "guest/**"), path.join(shared.projectdir, "shared/rootfs/xmake.lua")}) do
        for _, file in ipairs(os.files(pattern)) do
            lines[#lines + 1] = file .. " " .. tostring(os.filesize(file)) .. " " .. tostring(os.mtime(file))
        end
    end
    table.sort(lines)
    lines[#lines + 1] = os.isfile(shared.md5file) and io.readfile(shared.md5file):trim() or ""
    return table.concat(lines, "\n"):trim()
end

function shared.image_repo(os)
    if shared.imagerepo then
        return shared.imagerepo
    end
    local remote = os.iorunv("git", {"remote", "get-url", "origin"}):trim()
    local repo = remote:match("github%.com[:/]([%w._%-/]+)")
    return repo and (repo:gsub("%.git$", "")) or nil
end

function shared.image_download(os, io, repo)
    local base = "https://github.com/" .. repo .. "/releases/download/image/"
    local sums = os.iorunv("sh", {"-c", "curl -fsSL --max-time 30 " .. base .. "image.sha256 2>/dev/null || true"})
    if sums:trim() == "" then
        return false, "no " .. repo .. "/releases/tag/image release yet (run the image workflow)"
    end
    local expected = {}
    for line in sums:gmatch("[^\r\n]+") do
        local sha, name = line:match("^(%x+)%s+%*?(.+)$")
        if sha then
            expected[name] = sha
        end
    end
    local wanted = {
        {name = "base.qcow2", dest = shared.imagefile},
        {name = "Image", dest = shared.kernel},
        {name = "initramfs-linux.img", dest = shared.initrd}
    }
    for _, asset in ipairs(wanted) do
        if not expected[asset.name] then
            return false, "the " .. repo .. " image release has no " .. asset.name
        end
    end
    os.mkdir(path.directory(shared.kernel))
    for _, asset in ipairs(wanted) do
        print("download " .. asset.name)
        os.execv("curl", {"-fL", "--retry", "3", "-o", asset.dest, base .. asset.name})
        local actual = hash.sha256(asset.dest)
        if actual ~= expected[asset.name] then
            os.rm(asset.dest)
            return false, asset.name .. " does not match the sha256 in " .. repo .. "/releases/tag/image"
        end
    end
    return true
end

function shared.image_build(os, find_tool, io)
    local total = os.time()
    local g = shared.guest()
    shared.fetch_latest(g, os, io)
    shared.extract_tree(g, os, io)
    local firstboot = shared.build_firstboot(os, nil, find_tool)
    local trydisplay = shared.build_trydisplay(os, nil, find_tool)
    local prov = path.join(shared.rootdir, "usr/local/lib/try")
    if os.isdir(prov) then
        os.rmdir(prov)
    end
    os.mkdir(prov)
    os.cp(firstboot, path.join(prov, "firstboot"))
    os.cp(trydisplay, path.join(prov, "tryDisplay"))
    os.cp(path.join(shared.projectdir, "guest/packages.txt"), prov)
    io.writefile(path.join(prov, "special-modes.txt"), shared.special_modes(os, shared.tarball))
    os.execv("chmod", {"755", path.join(prov, "firstboot"), path.join(prov, "tryDisplay")})
    for _, unit in ipairs({"firstBoot.service", "tryDisplay.service", "hyprland.service", "run-payload.mount"}) do
        os.cp(path.join(shared.projectdir, "guest", unit), path.join(shared.rootdir, "etc/systemd/system", unit))
    end
    local wants = path.join(shared.rootdir, "etc/systemd/system/multi-user.target.wants")
    os.mkdir(wants)
    os.execv("ln", {"-sf", "/etc/systemd/system/firstBoot.service", path.join(wants, "firstBoot.service")})
    local graphical_wants = path.join(shared.rootdir, "etc/systemd/system/graphical.target.wants")
    os.mkdir(graphical_wants)
    os.execv("ln", {"-sf", "/etc/systemd/system/tryDisplay.service", path.join(graphical_wants, "tryDisplay.service")})
    os.execv("ln", {"-sf", "/etc/systemd/system/hyprland.service", path.join(graphical_wants, "hyprland.service")})

    os.mkdir(shared.bootdir)
    os.cp(path.join(shared.rootdir, g.kernel), shared.kernel)
    os.cp(path.join(shared.rootdir, g.initrd), shared.initrd)

    local mke2fs = shared.mke2fs(find_tool)
    if not mke2fs then
        os.raise("mke2fs not found, install e2fsprogs")
    end
    local img = shared.qemu_img(os, find_tool)
    print("create " .. shared.rawfile .. " " .. shared.disksize)
    os.rm(shared.rawfile)
    os.execv(img, {"create", "-f", "raw", shared.rawfile, shared.disksize})
    os.execv(mke2fs, {"-t", "ext4", "-F", "-E", "lazy_itable_init=1,lazy_journal_init=1", "-J", "size=64", "-d", shared.rootdir, shared.rawfile})
    print("convert " .. shared.rawfile .. " -> " .. shared.imagefile)
    os.rm(shared.imagefile)
    os.execv(img, {"convert", "-O", "qcow2", "-m", "8", "-W", shared.rawfile, shared.imagefile})
    os.rm(shared.rawfile)
    io.writefile(shared.imagekeyfile, shared.image_inputs(os, io) .. "\n")
    print("image ready in " .. (os.time() - total) .. "s, size " ..
        os.iorunv("sh", {"-c", "ls -lh " .. shared.imagefile .. " | awk '{print $5}'"}):trim())
end

function shared.image_ready(os, io)
    if not os.isfile(shared.imagefile) or not os.isfile(shared.kernel) or not os.isfile(shared.initrd) then
        return false
    end
    local key = os.isfile(shared.imagekeyfile) and io.readfile(shared.imagekeyfile):trim() or ""
    return key == shared.image_inputs(os, io)
end

function shared.image_ensure(os, find_tool, io)
    if shared.image_ready(os, io) then
        return
    end
    local repo = shared.image_repo(os)
    local why = "there is no local base image"
    if repo and not os.isfile(shared.imagefile) then
        local downloaded
        downloaded, why = shared.image_download(os, io, repo)
        if downloaded then
            io.writefile(shared.imagekeyfile, shared.image_inputs(os, io) .. "\n")
            print("image downloaded from " .. repo .. "/releases/tag/image")
            return
        end
    elseif repo and os.isfile(shared.imagefile) then
        why = "the local base image is older than guest/ and shared/rootfs/xmake.lua"
    end
    print("building the base image locally: " .. why)
    shared.image_build(os, find_tool, io)
end
