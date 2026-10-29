set_project("playground")
set_version("0.1.0")

includes("shared")
includes("guest")
includes("qemu")
includes("ui")

local shared = shared

task("clean")
on_run(function ()
    import("core.base.option")
    os.rmdir(shared.builddir)
    print("deleted " .. shared.builddir)
    if option.get("cache") then
        os.execv("sh", {"-c", "chmod -R u+w " .. shared.cachedir .. " 2>/dev/null; rm -rf " .. shared.cachedir})
        print("deleted " .. shared.cachedir)
    else
        print("kept " .. shared.cachedir .. " (tarball + tree, drop with: xmake clean --cache)")
        print("kept " .. shared.statedir .. " (guest disk + settings, xmake reset rolls the disk back)")
    end
end)
set_menu {
    usage = "xmake clean [--cache]",
    description = "Delete build/, keeping the download and tree cache in .cache/",
    options = {
        {nil, "cache", "k", nil, "Also delete .cache/ (tarball + extracted tree)"}
    }
}

task("prune")
on_run(function ()
    import("core.base.option")
    import("lib.detect.find_tool")
    local function megabytes(target)
        local text = os.iorunv("sh", {"-c", "du -sm '" .. target .. "' 2>/dev/null | cut -f1 || true"}):trim()
        return tonumber(text) or 0
    end
    local before = megabytes(shared.cachedir) + megabytes(shared.builddir) + megabytes(shared.statedir)
    if os.exists(shared.builddir) then
        os.rmdir(shared.builddir)
    end
    for _, item in ipairs({"payload.tree", "parts", "go-build", "go-mod"}) do
        local target = path.join(shared.cachedir, item)
        if os.exists(target) then
            os.execv("sh", {"-c", "chmod -R u+w '" .. target .. "' 2>/dev/null; rm -rf '" .. target .. "'"})
        end
    end
    for _, pattern in ipairs({"*.tar.gz", "*.tgz"}) do
        for _, archive in ipairs(os.files(path.join(shared.cachedir, pattern)) or {}) do
            os.rm(archive)
        end
    end
    if option.get("all") and os.isdir(shared.rootdir) then
        os.rmdir(shared.rootdir)
        print("dropped " .. shared.rootdir .. ", the next image build downloads the tarball again")
    elseif os.isdir(shared.rootdir) then
        print("kept " .. shared.rootdir .. " (" .. megabytes(shared.rootdir) .. " MB), add --all to drop it")
    end
    if option.get("disk") then
        shared.prepare(os, find_tool, io, true)
    else
        print("kept the base image, the payload disk and the guest overlay, add --disk to drop the overlay too")
    end
    local after = megabytes(shared.cachedir) + megabytes(shared.builddir) + megabytes(shared.statedir)
    print("pruned " .. math.max(before - after, 0) .. " MB, " .. after .. " MB left in cache, build and state")
end)
set_menu {
    usage = "xmake prune [--all] [--disk]",
    description = "Drop build leftovers, downloads and extracted staging, and report the space left",
    options = {
        {nil, "all", "k", nil, "Also drop the extracted root tree, the next image build downloads the tarball"},
        {nil, "disk", "k", nil, "Also drop the guest overlay, the next boot provisions again"}
    }
}
