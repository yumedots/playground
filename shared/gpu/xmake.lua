function shared.gpu_host(os)
    return os.host() == "macosx" and os.arch() == "arm64"
end

function shared.gpu_program()
    return path.join(shared.gpudir, "bin", "qemu-system-" .. shared.guest().arch)
end

function shared.gpu_fetch(os, io)
    local stamp = path.join(shared.gpudir, ".sha256")
    if os.isfile(shared.gpu_program()) and os.isfile(stamp) and io.readfile(stamp):trim() == shared.gpukit.sha256 then
        return shared.gpu_program()
    end
    local archive = path.join(shared.cachedir, "gpuRuntime.tgz")
    os.mkdir(shared.cachedir)
    if not os.isfile(archive) or hash.sha256(archive) ~= shared.gpukit.sha256 then
        print("download " .. shared.gpukit.url)
        os.execv("curl", {"-fL", "--retry", "3", "-o", archive, shared.gpukit.url})
    end
    local actual = hash.sha256(archive)
    if actual ~= shared.gpukit.sha256 then
        os.rm(archive)
        os.raise("gpu runtime mismatch: want " .. shared.gpukit.sha256 .. ", got " .. actual)
    end
    if os.isdir(shared.gpudir) then
        os.rmdir(shared.gpudir)
    end
    os.mkdir(shared.gpudir)
    os.execv("tar", {"-xzf", archive, "-C", shared.gpudir})
    os.rm(archive)
    io.writefile(stamp, shared.gpukit.sha256 .. "\n")
    print("gpu qemu ready " .. shared.gpu_program())
    return shared.gpu_program()
end
