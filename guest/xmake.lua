local shared = shared

target("firstboot")
set_kind("binary")
set_default(false)
set_targetdir(path.join(shared.builddir, "guest"))
set_filename("firstboot")
add_files(path.join(shared.firstbootdir, "*.go"))
on_build(function (target)
    import("lib.detect.find_tool")
    shared.build_firstboot(os, target:targetfile(), find_tool)
end)

target("trydisplay")
set_kind("binary")
set_default(false)
set_targetdir(path.join(shared.builddir, "guest"))
set_filename("tryDisplay")
add_files(path.join(shared.trydisplaydir, "*.go"))
on_build(function (target)
    import("lib.detect.find_tool")
    shared.build_trydisplay(os, target:targetfile(), find_tool)
end)

task("fetch")
on_run(function ()
    shared.fetch_latest(shared.guest(), os, io, true)
    if shared.qemu_keg(os) then
        shared.qemu_fetch(os, io, true)
    else
        print("qemu: no virgl bottle on this host, vm uses qemu-system-" .. shared.guest().arch .. " from PATH")
    end
end)
set_menu {
    usage = "xmake fetch",
    description = "Download the latest Arch Linux ARM tarball and the pinned qemu-virgl bottles"
}

task("image")
on_run(function ()
    import("lib.detect.find_tool")
    shared.image_build(os, find_tool, io)
end)
set_menu {
    usage = "xmake image",
    description = "Build the plain base image from the tarball (CI publishes it as the image release)"
}

task("reset")
on_run(function ()
    import("lib.detect.find_tool")
    shared.prepare(os, find_tool, io, true)
    print("next: xmake run (fresh overlay, the base image and payload stay cached)")
end)
set_menu {
    usage = "xmake reset",
    description = "Drop the disk overlay and keep the base image, payload and caches"
}
