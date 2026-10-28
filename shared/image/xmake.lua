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
    local remote = os.iorunv("git", {"remote", "get-url", "origin"}):trim()
    local repo = remote:match("github%.com[:/]([%w._%-/]+)")
    return repo and repo:gsub("%.git$", "") or nil
end

function shared.image_download(os, io, repo)
    local gh = os.iorunv("sh", {"-c", "command -v gh 2>/dev/null || true"}):trim()
    if gh == "" then
        return false, "gh is not installed, it downloads the image artifact (brew install gh)"
    end
    if os.execv(gh, {"auth", "status"}, {try = true}) ~= 0 then
        return false, "gh is not logged in, the image artifact needs it (gh auth login)"
    end
    local run = os.iorunv("sh", {"-c", gh .. " run list --repo " .. repo ..
        " --workflow=image --status success --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true"}):trim()
    if run == "" then
        return false, "the image workflow has no successful run yet"
    end
    local dir = path.join(shared.cachedir, "image-download")
    if os.isdir(dir) then
        os.rmdir(dir)
    end
    os.mkdir(dir)
    print("download the image artifact from run " .. run)
    if os.execv(gh, {"run", "download", run, "--repo", repo, "--name", "image", "--dir", dir}, {try = true}) ~= 0 then
        os.rmdir(dir)
        return false, "the image artifact download failed"
    end
    local sums = path.join(dir, "image.sha256")
    if not os.isfile(sums) then
        os.rmdir(dir)
        return false, "the image artifact has no image.sha256"
    end
    local expected = {}
    for line in io.readfile(sums):gmatch("[^\r\n]+") do
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
    local missing = {}
    for _, asset in ipairs(wanted) do
        if not os.isfile(path.join(dir, asset.name)) then
            missing[#missing + 1] = asset.name
        end
    end
    if #missing > 0 then
        os.rmdir(dir)
        return false, "the image artifact has no " .. table.concat(missing, ", ")
    end
    os.mkdir(path.directory(shared.kernel))
    for _, asset in ipairs(wanted) do
        local actual = hash.sha256(path.join(dir, asset.name))
        if actual ~= expected[asset.name] then
            os.rmdir(dir)
            return false, "the image artifact checksum for " .. asset.name .. " does not match image.sha256"
        end
        os.rm(asset.dest)
        os.mv(path.join(dir, asset.name), asset.dest)
    end
    os.rmdir(dir)
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
            print("image downloaded from the " .. repo .. " image workflow artifact")
            return
        end
    elseif repo and os.isfile(shared.imagefile) then
        why = "the local base image is older than guest/ and shared/rootfs/xmake.lua"
    end
    print("building the base image locally: " .. why)
    shared.image_build(os, find_tool, io)
end
