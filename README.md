# playground

Boots an Arch Linux ARM guest with your dotfiles in a QEMU window, driven by a small Qt launcher.

## Build and run

- `xmake` builds the launcher (`playground`). Needs Qt 6 (Homebrew `qt` on macOS, `qt6-base` on Linux) and `qemu-system-aarch64` on PATH.
- `xmake run playground` opens the launcher. Start boots the guest, Stop shuts it down.
- `xmake build checks && xmake run checks` runs the self-checks.
- `xmake vm --dry-run` prints the QEMU command the launcher runs.

Settings (cores, mem, audio) live in `state/settings`. Set `PLAYGROUND_STATE_DIR` to move the state.
