local shared = shared

local MONITOR_PY = "import socket,sys\n" ..
    "s=socket.socket(socket.AF_UNIX)\n" ..
    "s.settimeout(20)\n" ..
    "s.connect(sys.argv[1])\n" ..
    "def prompt(): \n" ..
    "    b=b''\n" ..
    "    while not b.endswith(b'(qemu) '):\n" ..
    "        c=s.recv(4096)\n" ..
    "        if not c: break\n" ..
    "        b+=c\n" ..
    "prompt()\n" ..
    "s.sendall((sys.argv[2]+'\\n').encode())\n" ..
    "prompt()\n" ..
    "s.close()\n"

local function quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

function shared.monitor(os, command)
    os.iorunv("python3", {"-c", MONITOR_PY, shared.monitorsock, command})
end

function shared.headless_pid(os)
    if not os.isfile(shared.pidfile) then
        return nil
    end
    return os.iorunv("cat", {shared.pidfile}):trim()
end

function shared.headless_running(os)
    local pid = shared.headless_pid(os)
    if not pid or pid == "" then
        return false
    end
    return os.execv("kill", {"-0", pid}, {try = true}) == 0
end

local LAUNCH_PY = "import subprocess,sys\n" ..
    "p=subprocess.Popen(sys.argv[3:],stdin=subprocess.DEVNULL,stdout=open(sys.argv[1],'w'),stderr=subprocess.STDOUT,start_new_session=True)\n" ..
    "open(sys.argv[2],'w').write(str(p.pid))\n"

function shared.headless_start(os, program, argv, envs)
    os.mkdir(shared.builddir)
    local parts = {"env"}
    for key, value in pairs(envs) do
        table.insert(parts, quote(key .. "=" .. value))
    end
    table.insert(parts, "python3 -c " .. quote(LAUNCH_PY))
    table.insert(parts, quote(shared.builddir .. "/headless.err"))
    table.insert(parts, quote(shared.pidfile))
    table.insert(parts, quote(program))
    for _, value in ipairs(argv) do
        table.insert(parts, quote(value))
    end
    os.iorunv("sh", {"-c", table.concat(parts, " ")})
    print("headless guest started, pid " .. shared.headless_pid(os) .. ", log " .. shared.logfile)
end

task("vmstatus")
on_run(function ()
    import("core.base.option")
    local state = shared.headless_running(os) and "running" or "stopped"
    print("vm        " .. state)
    if not os.isfile(shared.logfile) then
        print("boot      no serial log yet")
        return
    end
    local log = os.iorunv("cat", {shared.logfile})
    print("boot      " .. (log:find("login:", 1, true) and "login prompt up" or "not at login yet"))
    if log:find("provisioning failed", 1, true) then
        print("ready     provisioning FAILED, see /var/log/try-firstBoot.log in the guest")
    elseif log:find("finish provisioning", 1, true) and log:find("\u{2713} finish provisioning", 1, true) then
        print("ready     provisioning done")
    else
        print("ready     provisioning not finished")
    end
end)
set_menu {
    usage = "xmake vmstatus",
    description = "Show whether the headless guest runs, booted, and finished provisioning"
}

task("shot")
on_run(function ()
    import("core.base.option")
    local out = option.get("out")
    if not out then
        os.raise("usage: xmake shot --out=<file.png>")
    end
    if not shared.headless_running(os) then
        os.raise("headless guest is not running, start it with xmake vm --headless")
    end
    out = path.absolute(out)
    local ppm = path.join(shared.builddir, "shot.ppm")
    os.rm(ppm)
    os.rm(out)
    shared.monitor(os, "screendump " .. ppm)
    if not os.isfile(ppm) then
        os.raise("screendump failed, no frame written")
    end
    os.iorunv("sips", {"-s", "format", "png", ppm, "--out", out})
    os.rm(ppm)
    local magic = os.iorunv("od", {"-An", "-tx1", "-N4", out}):trim():gsub("%s+", " ")
    if magic ~= "89 50 4e 47" then
        os.raise("conversion failed, no PNG at " .. out)
    end
    print("saved " .. out)
end)
set_menu {
    usage = "xmake shot --out=<file.png>",
    description = "Save a PNG of the headless guest screen",
    options = {
        {nil, "out", "kv", nil, "Output PNG path"}
    }
}

task("vmstop")
on_run(function ()
    import("core.base.option")
    if not shared.headless_running(os) then
        print("vm        already stopped")
        return
    end
    shared.monitor(os, "quit")
    os.rm(shared.pidfile)
    print("vm        stopped")
end)
set_menu {
    usage = "xmake vmstop",
    description = "Stop the headless guest"
}
