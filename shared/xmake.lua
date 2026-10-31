set_project("playground")
set_version("0.1.0")

shared = {
    projectdir = os.projectdir(),
    guests = {
        arm64 = {
            arch = "aarch64",
            tarball = "/os/ArchLinuxARM-aarch64-latest.tar.gz",
            mirror = "http://mirror.archlinuxarm.org",
            kernel = "boot/Image",
            initrd = "boot/initramfs-linux.img"
        }
    }
}

shared.builddir = path.join(shared.projectdir, "build")
shared.cachedir = path.join(shared.projectdir, ".cache")
shared.tarball = path.join(shared.cachedir, "archlinuxarm.tar.gz")
shared.md5file = path.join(shared.cachedir, "archlinuxarm.md5")
shared.rootdir = path.join(shared.cachedir, "root")
shared.logfile = path.join(shared.builddir, "guest.log")
shared.monitorsock = path.join(shared.builddir, "headless.sock")
shared.serialsock = path.join(shared.builddir, "serial.sock")
shared.pidfile = path.join(shared.builddir, "headless.pid")
shared.statedir = os.getenv("PLAYGROUND_STATE_DIR") or path.join(shared.projectdir, "state")
shared.settingsfile = path.join(shared.statedir, "settings")
shared.diskfile = path.join(shared.statedir, "rootfs.qcow2")
shared.rawfile = path.join(shared.builddir, "rootfs.raw")
shared.tree_new = shared.rootdir .. ".new"
shared.rootstamp = path.join(shared.cachedir, "root.stamp")
shared.disksize = "32G"
shared.imagefile = path.join(shared.cachedir, "base.qcow2")
shared.imagekeyfile = path.join(shared.cachedir, "base.key")
shared.bootdir = path.join(shared.cachedir, "boot")
shared.kernel = path.join(shared.bootdir, "Image")
shared.initrd = path.join(shared.bootdir, "initramfs-linux.img")
shared.payloadfile = path.join(shared.cachedir, "payload.raw")
shared.payloadkeyfile = path.join(shared.cachedir, "payload.key")
shared.payloadstage = path.join(shared.cachedir, "payload.tree")
shared.dotfiles = os.getenv("HOME") and path.join(os.getenv("HOME"), "dotfiles") or nil
shared.firstbootdir = path.join(shared.projectdir, "guest/firstBoot")
shared.firstbootfile = path.join(shared.builddir, "guest/firstboot")
shared.trydisplaydir = path.join(shared.projectdir, "guest/tryDisplay")
shared.trydisplayfile = path.join(shared.builddir, "guest/tryDisplay")
shared.guest_arch = "arm64"

shared.gpudir = path.join(shared.cachedir, "gpu")
shared.gpukit = {
    url = "https://github.com/yumedots/qemu/releases/download/gpu-f47ec30fe52e2e6ae72104784583ec4fd4980c0f/qemu-gpu-runtime.arm64.tgz",
    sha256 = "c4af275406b83182d2c0d3fd3c18bbbef19ca3c205807858f02bf1f68aee64ec"
}

function shared.settings(os, io)
    local gigabytes = math.floor((os.meminfo("totalsize") or 0) / 1024)
    local values = {
        cores = tostring(math.min(8, os.cpuinfo().ncpu)),
        mem = gigabytes >= 16 and "8G" or "4G",
        audio = os.host() == "macosx" and "on" or "off",
        nested = "off"
    }
    if os.isfile(shared.settingsfile) then
        for line in io.readfile(shared.settingsfile):gmatch("[^\r\n]+") do
            local key, value = line:match("^([%w_]+)=(.+)$")
            if key and values[key] then
                values[key] = value:trim()
            end
        end
    end
    return values
end

function shared.state(os)
    os.mkdir(shared.statedir)
end

includes("qemu")
includes("gpu")
includes("rootfs")
includes("image")
includes("payload")
includes("disk")
includes("build")
