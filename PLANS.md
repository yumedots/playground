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
  shared/        paths, pins, settings, tasks for the guest and disk
  qemu/          the QEMU argument list (xmake vm --print-args)
  guest/         firstBoot (Go), tryDisplay (Go), systemd units, packages
  xmake.lua      project entry
```

## Design

- Launcher: `MainWindow` shows the loading animation, Start/Stop, and cores/mem/audio settings.
- Start: `GuestProcess` runs `xmake vm --print-args`, parses `program=`, `arg=`, `env=` lines, and execs QEMU as a child process. Stop terminates it.
- Settings: `state/settings`, same `key=value` format as before.
- Display phase 1: QEMU opens its own window (cocoa on macOS, gtk on Linux). Mouse grab stays with QEMU.
- Not built from source: Qt, QEMU, the guest image. Qt comes from the host install, QEMU from the pinned bottle or PATH.

## Later

- Embed the guest framebuffer in Qt (separate decision).
- Debian agent mode (not started).
