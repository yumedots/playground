local shared = shared

local function quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function headless_helper(os)
    return path.join(shared.projectdir, "qemu/headless.py")
end

function shared.monitor(os, command)
    local result = os.iorunv("python3", {headless_helper(os), "monitor", shared.monitorsock, command})
    return result
end

function shared.headless_pid(os)
    if not os.isfile(shared.pidfile) then
        return nil
    end
    return os.iorunv("cat", {shared.pidfile}):trim()
end

function shared.headless_running(os)
    if not os.isfile(shared.monitorsock) then
        return false
    end
    return os.execv("python3", {headless_helper(os), "running", shared.monitorsock}, {try = true}) == 0
end

function shared.headless_start(os, program, argv, envs)
    if shared.headless_running(os) then
        os.raise("headless guest already running, see xmake vmstatus")
    end
    os.mkdir(shared.builddir)
    os.rm(shared.pidfile)
    os.rm(shared.monitorsock)
    os.rm(shared.serialsock)
    os.rm(shared.logfile)
    local parts = {"env"}
    for key, value in pairs(envs) do
        table.insert(parts, quote(key .. "=" .. value))
    end
    table.insert(parts, quote("python3"))
    table.insert(parts, quote(headless_helper(os)))
    table.insert(parts, quote("launch"))
    table.insert(parts, quote(shared.builddir .. "/headless.err"))
    table.insert(parts, quote(shared.pidfile))
    table.insert(parts, quote(shared.monitorsock))
    table.insert(parts, quote(program))
    for _, value in ipairs(argv) do
        table.insert(parts, quote(value))
    end
    local pid = os.iorunv("sh", {"-c", table.concat(parts, " ")})
    print("headless guest started, pid " .. pid:trim() .. ", log " .. shared.logfile)
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
    elseif (log:find("finish provisioning", 1, true) and log:find("\u{2713} finish provisioning", 1, true)) or log:find("TRY_PROVISIONED=1", 1, true) then
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
    local result = os.iorunv("python3", {headless_helper(os), "stop", shared.monitorsock, shared.pidfile})
    os.rm(shared.pidfile)
    os.rm(shared.monitorsock)
    os.rm(shared.serialsock)
    print("vm        " .. result:trim())
end)
set_menu {
    usage = "xmake vmstop",
    description = "Stop the headless guest"
}
