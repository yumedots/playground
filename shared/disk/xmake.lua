function shared.mke2fs(find_tool)
    local tool = find_tool("mke2fs") or find_tool("mkfs.ext4")
    if tool then
        return tool.program
    end
    for _, p in ipairs({"/opt/homebrew/opt/e2fsprogs/sbin/mke2fs", "/usr/sbin/mke2fs", "/sbin/mke2fs", "/usr/bin/mke2fs"}) do
        if os.isfile(p) then
            return p
        end
    end
end

function shared.base_stamp(os)
    return tostring(os.filesize(shared.imagefile)) .. " " .. tostring(os.mtime(shared.imagefile))
end

function shared.overlay(os, find_tool, io, fresh)
    local stamp = path.join(shared.statedir, "rootfs.base")
    if os.isfile(shared.diskfile) and not fresh then
        local known = os.isfile(stamp) and io.readfile(stamp):trim() or ""
        if known == shared.base_stamp(os) then
            return
        end
        print("base image changed, resetting the disk overlay")
    end
    os.mkdir(shared.statedir)
    os.rm(shared.diskfile)
    os.execv(shared.qemu_img(os, find_tool), {"create", "-f", "qcow2", "-F", "qcow2", "-b", shared.imagefile, shared.diskfile})
    io.writefile(stamp, shared.base_stamp(os) .. "\n")
    print("overlay " .. shared.diskfile .. " on " .. shared.imagefile)
end

function shared.prepare(os, find_tool, io, fresh)
    shared.state(os)
    shared.image_ensure(os, find_tool, io)
    shared.payload_ensure(os, find_tool, io)
    shared.overlay(os, find_tool, io, fresh)
end
