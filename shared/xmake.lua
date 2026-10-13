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
shared.statedir = os.getenv("PLAYGROUND_STATE_DIR") or path.join(shared.projectdir, "state")
shared.settingsfile = path.join(shared.statedir, "settings")
shared.diskfile = path.join(shared.statedir, "rootfs.qcow2")
shared.diskkeyfile = path.join(shared.statedir, "disk.key")
shared.resetsnapshot = "provisioned"
shared.rawfile = path.join(shared.builddir, "rootfs.raw")
shared.tree_new = shared.rootdir .. ".new"
shared.rootstamp = path.join(shared.cachedir, "root.stamp")
shared.disksize = "32G"
shared.dotfiles = os.getenv("HOME") and path.join(os.getenv("HOME"), "dotfiles") or nil
shared.firstbootdir = path.join(shared.projectdir, "guest/firstBoot")
shared.firstbootfile = path.join(shared.builddir, "guest/firstboot")
shared.trydisplaydir = path.join(shared.projectdir, "guest/tryDisplay")
shared.trydisplayfile = path.join(shared.builddir, "guest/tryDisplay")
shared.guest_arch = "arm64"

shared.qemudir = path.join(shared.cachedir, "qemu")
shared.qemurelease = "https://github.com/milesbuckton/homebrew-qemu-virgl/releases/download/latest"
shared.qemubottles = {
    {file = "qemu-master.arm64_tahoe.tgz",
     release = "https://github.com/yumedots/qemu/releases/download/qemu-7d46e13418ea8f3cae9fed5b8c6148877f1b5255",
     sha256 = "260d89ed4b544248fc072f68ea91e40ef1669b25a9f352e83453bfbc1eea35cf"},
    {file = "virglrenderer-main.arm64_golden_gate.bottle.tar.gz", opt = "virglrenderer",
     sha256 = "0db69830b601d38a2463a7545eedcd9a514b8974ba7e60ee38a739e196fe1f27"},
    {file = "libangle-main.arm64_golden_gate.bottle.tar.gz", opt = "libangle",
     sha256 = "a713cae333463de4e3fcad130507cf0de45c725bb77981252b47c276499fcaee"},
    {file = "libepoxy-angle-master.arm64_golden_gate.bottle.tar.gz", opt = "libepoxy-angle",
     sha256 = "a5bdd5810402baf826a427da4ab10b6236cbb23fe72ed77be635f9d2cf2045ab"}
}

function shared.settings(os, io)
    local gigabytes = math.floor((os.meminfo("totalsize") or 0) / 1024)
    local values = {
        cores = tostring(math.min(8, os.cpuinfo().ncpu)),
        mem = gigabytes >= 16 and "8G" or "4G",
        audio = os.host() == "macosx" and "on" or "off"
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
includes("rootfs")
includes("disk")
includes("build")
