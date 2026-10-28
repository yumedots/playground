local shared = shared

local function qemu_config(option, os, io, program)
    local settings = shared.settings(os, io)
    return {
        cores = option.get("cpus") or settings.cores,
        mem = option.get("mem") or settings.mem,
        audio = settings.audio,
        virtualization = shared.virtualization(os, io, program)
    }
end

local function qemu_args(option, os, config, io)
    local g = shared.guest()
    local mac = os.host() == "macosx"
    local accel = mac and "hvf" or "kvm"
    local headless = option.get("headless")
    local gl = not headless and not option.get("no-gl")
    local width, height = option.get("width"), option.get("height")
    if not width or not height then
        local screen_width, screen_height = shared.host_display(os, io)
        width = width or screen_width
        height = height or screen_height
    end
    local machine = "virt,accel=" .. accel .. ",highmem=on"
    if config.virtualization then
        machine = machine .. ",virtualization=on"
    end
    local argv = {
        "-machine", machine,
        "-cpu", "host",
        "-smp", config.cores,
        "-m", config.mem,
        "-kernel", shared.kernel,
        "-initrd", shared.initrd,
        "-append", "root=/dev/vda rw console=tty0 console=ttyAMA0",
        "-drive", "if=virtio,format=qcow2,file=" .. shared.diskfile,
        "-drive", "if=virtio,format=raw,readonly=on,file=" .. shared.payloadfile,
        "-device", (gl and "virtio-gpu-gl-pci" or "virtio-gpu-pci") ..
            ",xres=" .. width .. ",yres=" .. height,
        "-device", "virtio-rng-pci",
        "-device", "qemu-xhci",
        "-device", "usb-kbd",
        "-device", "usb-tablet",
        "-netdev", "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22",
        "-device", "virtio-net-pci,netdev=net0",
        "-chardev", "socket,id=serial0,path=" .. shared.serialsock .. ",server=on,wait=off,logfile=" .. shared.logfile .. ",logappend=on",
        "-serial", "chardev:serial0",
        "-no-reboot"
    }
    if config.audio == "on" then
        table.join2(argv, {"-audiodev", (mac and "coreaudio" or "pa") .. ",id=audio0",
            "-device", "intel-hda", "-device", "hda-output,audiodev=audio0"})
    end
    local sharedir = shared.qemu_sharedir(os)
    if sharedir then
        table.join2(argv, {"-L", sharedir})
    end
    if headless then
        table.join2(argv, {"-display", "none", "-monitor", "unix:" .. shared.monitorsock .. ",server,nowait"})
    elseif mac then
        table.join2(argv, {"-display", gl and "cocoa,gl=on,zoom-to-fit=on,full-grab=on,swap-opt-cmd=on" or
            "cocoa,zoom-to-fit=on,full-grab=on,swap-opt-cmd=on"})
    else
        table.join2(argv, {"-display", gl and "gtk,gl=on" or "gtk"})
    end
    return argv
end

task("doctor")
on_run(function ()
    import("core.base.option")
    import("lib.detect.find_tool")
    local g = shared.guest()
    local program = shared.qemu_program(os, find_tool)
    local mke2fs = shared.mke2fs(find_tool)
    print("host      " .. os.host() .. "/" .. os.arch())
    print("guest     " .. g.arch)
    if program then
        local version = os.iorunv("sh", {"-c", program .. " --version 2>/dev/null | head -1 || true"}):trim()
        print("qemu      " .. program .. (version ~= "" and " " .. version or " (needs the keg env to run)"))
    else
        print("qemu      missing qemu-system-" .. g.arch)
    end
    if os.host() == "macosx" then
        print("gpu       " .. (shared.qemu_keg(os) and "virtio-gpu-gl-pci, hvf, cocoa,gl=on, bottle in " .. shared.qemudir or
            "no virgl bottle (arm64 tahoe only), use --no-gl with a QEMU from PATH"))
    else
        print("gpu       virtio-gpu-gl-pci, kvm, gtk,gl=on, system qemu-system-" .. g.arch)
    end
    local settings = shared.settings(os, io)
    print("settings  cores " .. settings.cores .. ", mem " .. settings.mem .. ", audio " .. settings.audio)
    print("nested    " .. (shared.virtualization(os, io, program) and "on, guest gets /dev/kvm" or "off"))
    print("state     " .. shared.statedir)
    print("mke2fs    " .. (mke2fs or "missing e2fsprogs"))
    if os.isfile(shared.tarball) then
        local local_md5 = hash.md5(shared.tarball)
        local want = shared.remote_md5(g.tarball, os)
        print("tarball   " .. local_md5 .. (want == nil and "" or (want == local_md5 and " up to date" or " stale, rerun xmake fetch")))
    else
        print("tarball   missing, run xmake fetch")
    end
    print("rootfs    " .. (os.isfile(path.join(shared.rootdir, "etc/passwd")) and "extracted" or "not extracted"))
    print("image     " .. (os.isfile(shared.imagefile) and (shared.image_ready(os, io) and "base.qcow2 current" or "base.qcow2 stale, xmake image") or "missing, xmake vm builds it"))
    print("payload   " .. (os.isfile(shared.payloadfile) and "dotfiles.raw built" or "missing, built on the next boot"))
    if os.isfile(shared.diskfile) then
        local snapshots = os.iorunv("sh", {"-c", shared.qemu_img(os, find_tool) .. " snapshot -l '" .. shared.diskfile .. "' 2>/dev/null || true"})
        print("disk      overlay qcow2" .. (snapshots:trim() ~= "" and "\n" .. snapshots or ""))
    else
        print("disk      overlay missing, made on the next boot")
    end
    print("dotfiles  " .. (shared.dotfiles or "none") .. " -> injected at boot from the payload disk")
    print("log       " .. shared.logfile)
    if program and os.isfile(shared.diskfile) then
        print("run       " .. program .. " " .. table.concat(qemu_args(option, os, qemu_config(option, os, io, program), io), " "))
    end
end)
set_menu {
    usage = "xmake doctor",
    description = "Show host, tools, base image, payload disk, overlay and snapshots"
}

task("vminstall")
on_run(function ()
    import("core.base.option")
    local repo = option.get("repo") or os.getenv("HOME") .. "/qemu"
    local keg = shared.qemu_keg(os)
    if not keg then
        os.raise("no arm64 tahoe keg on this host")
    end
    local arch = shared.guest().arch
    local built = path.join(repo, "build", "qemu-system-" .. arch)
    if not os.isfile(built) then
        os.raise("missing " .. built .. ", build the fork first (ninja in its build dir)")
    end
    local entitlements = path.join(repo, "accel", "hvf", "entitlements.plist")
    if not os.isfile(entitlements) then
        os.raise("missing " .. entitlements)
    end
    local dest = path.join(keg, "bin", "qemu-system-" .. arch)
    os.execv("sh", {"-c", string.format([[
      set -e
      rm -f %s
      cp %s %s
      chmod 755 %s
      xattr -c %s
      install_name_tool -add_rpath %s %s 2>/dev/null || true
      codesign --force --sign - --entitlements %s %s
    ]], dest, built, dest, dest, dest, path.join(keg, "opt/libangle/lib"), dest, entitlements, dest)})
    print("installed " .. dest)
end)
set_menu {
    usage = "xmake vminstall [-r|--repo=DIR]",
    description = "Install the fork build into the qemu-virgl keg (rpath + hvf entitlement fix)",
    options = {
        {"r", "repo", "kv", nil, "Fork repo with build/qemu-system-<arch>, defaults to ~/qemu"}
    }
}

function shared.host_display(os, io)
    local cached = path.join(shared.cachedir, "hostDisplay")
    if os.isfile(cached) then
        local text = io.readfile(cached)
        local width, height = text:match("(%d+)x(%d+)")
        if width then
            return tonumber(width), tonumber(height)
        end
    end
    local width, height = 2560, 1440
    for _, line in ipairs(os.iorunv("system_profiler", {"SPDisplaysDataType"}):split("\n")) do
        local foundWidth, foundHeight = line:match("Resolution:%s*(%d+)%s*x%s*(%d+)")
        if foundWidth then
            width, height = tonumber(foundWidth), tonumber(foundHeight)
            break
        end
    end
    os.mkdir(shared.cachedir)
    io.writefile(cached, width .. "x" .. height)
    return width, height
end

task("vm")
on_run(function ()
    import("core.base.option")
    import("lib.detect.find_tool")
    local g = shared.guest()
    local printing = option.get("print-args")
    shared.state(os)
    if option.get("headless") and shared.headless_running(os) then
        os.raise("headless guest already running, see xmake vmstatus")
    end
    local started = os.time()
    shared.prepare(os, find_tool, io, option.get("fresh"))
    if os.time() - started > 2 then
        print("guest image in " .. (os.time() - started) .. "s")
        print("first boot: the guest installs its packages, the login screen appears after that")
    end
    if not option.get("no-gl") and not option.get("headless") then
        shared.qemu_fetch(os, io)
    end
    local program = shared.qemu_program(os, find_tool)
    if not program then
        os.raise("qemu-system-" .. g.arch .. " is not in PATH")
    end
    local config = qemu_config(option, os, io, program)
    local argv = qemu_args(option, os, config, io)
    if printing then
        print("program=" .. program)
        for _, value in ipairs(argv) do
            print("arg=" .. value)
        end
        for key, value in pairs(shared.qemu_env(os) or {}) do
            print("env=" .. key .. "=" .. value)
        end
        return
    end
    if option.get("dry-run") then
        print(program .. " " .. table.concat(argv, " "))
        return
    end
    if option.get("headless") then
        shared.headless_start(os, program, argv, shared.qemu_env(os) or {})
        return
    end
    print("booting " .. g.arch .. " with " .. config.cores .. " cores, " .. config.mem .. ", log " .. shared.logfile)
    os.execv(program, argv, {envs = shared.qemu_env(os) or {}})
end)
set_menu {
    usage = "xmake vm [options]",
    description = "Boot the guest in its own QEMU window",
    options = {
        {nil, "width", "kv", nil, "Guest screen width, defaults to the host screen"},
        {nil, "height", "kv", nil, "Guest screen height, defaults to the host screen"},
        {nil, "mem", "kv", nil, "Guest RAM, defaults to the saved setting"},
        {nil, "cpus", "kv", nil, "Guest cores, defaults to the saved setting"},
        {nil, "print-args", "k", nil, "Print program= and arg= lines for the launcher to run"},
        {nil, "fresh", "k", nil, "Drop the disk overlay and start again from the base image"},
        {nil, "no-gl", "k", nil, "Skip the virgl bottle and use a QEMU from PATH without virtio-gpu-gl"},
        {nil, "headless", "k", nil, "Run in the background with no window; use xmake vmstatus, shot, vmstop"},
        {"n", "dry-run", "k", nil, "Print the QEMU command instead of running it"}
    }
}

task("snapshot")
on_run(function ()
    import("core.base.option")
    import("lib.detect.find_tool")
    local name = option.get("name")
    if not name then
        os.raise("usage: xmake snapshot --name=<name>")
    end
    local img = shared.qemu_img(os, find_tool)
    os.execv(img, {"snapshot", "-c", name, shared.diskfile})
    print(os.iorunv(img, {"snapshot", "-l", shared.diskfile}))
end)
set_menu {
    usage = "xmake snapshot --name=<name>",
    description = "Save a snapshot of the guest disk (shut the VM down first)",
    options = {
        {nil, "name", "kv", nil, "Snapshot name"}
    }
}

task("restore")
on_run(function ()
    import("core.base.option")
    import("lib.detect.find_tool")
    local name = option.get("name")
    if not name then
        os.raise("usage: xmake restore --name=<name>")
    end
    os.execv(shared.qemu_img(os, find_tool), {"snapshot", "-a", name, shared.diskfile})
    print("restored " .. name)
end)
set_menu {
    usage = "xmake restore --name=<name>",
    description = "Roll the guest disk back to a snapshot (shut the VM down first)",
    options = {
        {nil, "name", "kv", nil, "Snapshot name"}
    }
}

includes("headless.lua")
