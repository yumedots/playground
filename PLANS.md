# playground plan

Goal: run the Arch dotfiles desktop in a VM on the host, with a Qt6 launcher as the wrapper.

## Layout

```
playground/
  ui/            Qt6 C++20 launcher (xmake target "playground"), checks target "checks"
    src/         one concern per file
    tests/       checks.cpp, the self-checks
    vendor/      cute_aseprite.h, pinned by sha256
    resources.qrc  loading.aseprite
  shared/        paths, pins, settings, base image, payload disk, overlay, tasks
  qemu/          the QEMU argument list (xmake vm --print-args)
  guest/         firstBoot (Go), tryDisplay (Go), systemd units, packages
  .github/       actions/workflows/image.yml builds the plain base image
  xmake.lua      project entry
```

## Design

- Launcher: `MainWindow` shows the loading animation, Start/Stop, and cores/mem/audio settings.
- Start: `GuestProcess` runs `xmake vm --print-args`, parses `program=`, `arg=`, `env=` lines, and execs QEMU as a child process. Stop terminates it.
- Image: `.cache/base.qcow2` is a plain Arch Linux ARM rootfs plus firstBoot/tryDisplay and systemd units, no dotfiles. It is downloaded from the `image` release (`.github/workflows/image.yml`) or built locally once by `xmake image`.
- Disk: `state/rootfs.qcow2` is a qcow2 overlay on the base image, so reset is instant and the base is never dirtied.
- Payload: `.cache/payload.raw` is a small ext4 disk with `~/dotfiles` (minus `.git`), rebuilt only when dotfiles change and attached as `/dev/vdb`; firstBoot links it into the guest user.
- Packages: `guest/packages.txt` is baked into the image and installed by firstBoot on boot, so package changes rebuild the image but dotfile changes never do.
- Settings: `state/settings`, same `key=value` format as before.
- Display phase 1: QEMU opens its own window (cocoa on macOS, gtk on Linux). Mouse grab stays with QEMU.
- Not built from source: Qt, QEMU. Qt comes from the host install, QEMU from the pinned bottle or PATH.

## Later

- Embed the guest framebuffer in Qt (separate decision).
- Debian agent mode (not started).
