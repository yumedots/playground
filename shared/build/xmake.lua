function shared.go(os, find_tool)
    local tool = find_tool and find_tool("go") or nil
    if tool then
        return tool.program
    end

    local host = os.host() == "macosx" and "darwin" or "linux"
    local arch = os.arch() == "x86_64" and "amd64" or os.arch()
    local toolchain_dir = path.join(shared.cachedir, "toolchains/go")
    local go = path.join(toolchain_dir, "go/bin/go")
    if os.isfile(go) then
        return go
    end

    local version = os.iorunv("curl", {"-fsSL", "https://go.dev/VERSION?m=text"}):split("\n")[1]
    local archive_url = "https://go.dev/dl/" .. version .. "." .. host .. "-" .. arch .. ".tar.gz"

    os.mkdir(toolchain_dir)
    local archive = path.join(toolchain_dir, path.filename(archive_url))
    print("download Go toolchain " .. archive_url)
    os.execv("curl", {"-fL", "--retry", "3", "-o", archive, archive_url})
    os.execv("tar", {"-xzf", archive, "-C", toolchain_dir})
    os.rm(archive)
    if not os.isfile(go) then
        os.raise("Go toolchain extraction failed")
    end
    return go
end

function shared.build_guest_go(os, dir, target, find_tool)
    local go = shared.go(os, find_tool)
    os.mkdir(path.directory(target))
    os.execv(go, {"build", "-trimpath", "-ldflags=-s -w", "-o", target, "."}, {
        curdir = dir,
        envs = {
            GOOS = "linux",
            GOARCH = shared.guest_arch,
            CGO_ENABLED = "0",
            GO111MODULE = "on",
            GOCACHE = path.join(shared.cachedir, "go-build"),
            GOMODCACHE = path.join(shared.cachedir, "go-mod"),
            GOPATH = path.join(shared.cachedir, "go-path")
        }
    })
    os.execv("chmod", {"755", target})
    return target
end

function shared.build_firstboot(os, target, find_tool)
    return shared.build_guest_go(os, shared.firstbootdir, target or shared.firstbootfile, find_tool)
end

function shared.build_trydisplay(os, target, find_tool)
    return shared.build_guest_go(os, shared.trydisplaydir, target or shared.trydisplayfile, find_tool)
end

function shared.pigz(os)
    local bin = path.join(shared.cachedir, "bin/pigz")
    if os.isfile(bin) then
        return bin
    end
    if not os.isdir(shared.cachedir) then
        os.mkdir(shared.cachedir)
    end
    local src = path.join(shared.cachedir, "pigz.tar.gz")
    local dir = path.join(shared.cachedir, "pigz")
    print("building pigz (parallel gzip) into .cache/bin, no install needed")
    os.execv("sh", {"-c", "curl -fsSL -o " .. src .. " https://zlib.net/pigz/pigz.tar.gz" ..
        " && tar -xzf " .. src .. " -C " .. shared.cachedir ..
        " && mkdir -p " .. path.directory(bin) ..
        " && make -s -C " .. dir .. " pigz && cp " .. path.join(dir, "pigz") .. " " .. bin .. " || true"})
    if os.isfile(bin) then
        return bin
    end
    print("pigz build failed, falling back to tar")
    return nil
end
