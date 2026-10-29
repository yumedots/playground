# playground

Boots an Arch Linux ARM guest with your dotfiles in a QEMU window, driven by a small Qt launcher.

## Build and run

- `xmake` builds the launcher (`playground`). Needs Qt 6 (Homebrew `qt` on macOS, `qt6-base` on Linux) and `qemu-system-aarch64` on PATH.
- `xmake run playground` opens the launcher. Start boots the guest, Stop shuts it down.
- The guest disk is a qcow2 overlay on a plain base image (`xmake image`), downloaded from the `image` pre-release of this repo or built once from the Arch tarball. Dotfiles live in a small payload disk (`~/dotfiles`) that is rebuilt on boot and injected by the guest, so editing dotfiles never rebuilds the image.
- SDDM greets you; log in as `alarm` with password `alarm`. The session starts Hyprland with the dotfiles' quickshell bar (yudaemond is built on first boot).
- `xmake reset` drops the overlay, `xmake vm --fresh` does it once, `xmake vm --no-gl` skips the virgl bottle.
- `xmake build checks && xmake run checks` runs the self-checks.
- `xmake vm --dry-run` prints the QEMU command the launcher runs.

Settings (cores, mem, audio) live in `state/settings`. Set `PLAYGROUND_STATE_DIR` to move the state.
