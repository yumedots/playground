function shared.qemu_program(os, find_tool)
    if shared.gpu_host(os) then
        return shared.gpu_program()
    end
    local tool = find_tool("qemu-system-" .. shared.guest().arch)
    return tool and tool.program
end

function shared.qemu_img(os, find_tool)
    if shared.gpu_host(os) then
        local program = path.join(shared.gpudir, "bin", "qemu-img")
        if not os.isfile(program) then
            os.raise("missing " .. program .. ", run xmake fetch")
        end
        return program
    end
    local tool = find_tool and find_tool("qemu-img") or nil
    return tool and tool.program or "qemu-img"
end

function shared.virtualization(os, io, program)
    if not program or not shared.gpu_host(os) then
        return false
    end
    if tonumber(os.iorunv("sw_vers", {"-productVersion"}):match("^(%d+)")) < 26 then
        return false
    end
    local stamp = path.join(shared.cachedir, "virtualization")
    if os.isfile(stamp) then
        return io.readfile(stamp):trim() == "on"
    end
    local ok = os.iorunv("sh", {"-c", "printf 'quit\\n' | '" .. program ..
        "' -nodefaults -machine virt,accel=hvf,virtualization=on -cpu host -display none -S -monitor stdio >/dev/null 2>&1 && echo on || echo off"}):trim()
    print("nested virtualization " .. ok)
    os.mkdir(shared.cachedir)
    io.writefile(stamp, ok .. "\n")
    return ok == "on"
end
