# Handoff: GPU display

## Status

Solved. `xmake vm` boots on virgl by default: `virtio-gpu-gl-pci` with
`cocoa,gl=on` on try-omarchy's QEMU runtime, Hyprland reports
`Renderer: virgl (Apple M3 Pro)`. `xmake vm --2d` is the optional llvmpipe
fallback on the keg QEMU.

## How the GL path works

- QEMU: the runtime from try-omarchy's `TryOmarchyKit.zip` (v1.3.0, sha256
  pinned in `shared/xmake.lua`, fetched by `shared/gpu/xmake.lua` into
  `.cache/gpu`). QEMU 11.1.1 with their cocoa GL scanout, dynamic display and
  hvf timing patches, patched virglrenderer, ANGLE and epoxy, all loaded from
  `@executable_path/../lib`, Developer ID signed with the hvf entitlement. It
  ships no option ROMs (devices get `romfile=`) and no coreaudio (audio is
  `sdl`). The local fork in `~/qemu` and `xmake vminstall` are no longer needed.
- Guest: Hyprland's `quirks:skip_non_kms_dmabuf_formats` defaults to true and
  drops every dmabuf format the virtio-gpu plane cannot scan out (it only does
  XRGB8888). Mesa then exposed no EGL config with alpha, so quickshell's
  transparent full-screen overlays (`wallpaper`, `powermenu`, `launcher`) came
  out opaque black over the desktop. `scripts/preparePayload.py` prepends
  `hl.config({ quirks = { skip_non_kms_dmabuf_formats = false } })` to
  `hypr/hyprland.lua`.
- Size: `tryDisplay` is enabled (`graphical.target.wants`) and applies the
  window's EDID mode and density scale to Hyprland on every resize, so a 1072x635
  window on a 2x screen gives 2144x1206 at scale 2.

## Benchmark

M3 Pro, 8 vCPUs, 8 GB, 20 s samples. Load is two foot windows with workspace
switching every 0.2 s. Host GPU is `ioreg` "Device Utilization %" for the
whole machine, 14% with no VM running.

| Path | Load | Host QEMU CPU | Guest Hyprland CPU | Host GPU |
| --- | --- | --- | --- | --- |
| GL (default) | idle | 1% | ~0% | 15% |
| GL (default) | switching | 18% | 3.2% | 21% |
| 2D (`--2d`) | idle | 1% | ~0% | 14% |
| 2D (`--2d`) | switching | 497% | 463% | 16% |

## Guest access

`ssh -p 2222 alarm@127.0.0.1`, password `alarm`; root password is `root`.
Logging in over ssh before first-boot provisioning finishes starts the user
manager early and `yudaemond` hits its start limit.

## Environment gotchas

- macOS 26, arm64. The kit runtime needs arm64 macOS; elsewhere `vm` uses the
  QEMU from PATH with `gtk,gl=on`.
- `xmake prune --all` drops the extracted root tree, `--disk` drops the guest
  overlay (next boot re-provisions in ~4 min).
- A fresh disk shows Hyprland's own background: the dotfiles ship no
  wallpapers (`~/Documents/Wallpaper` is empty).

## File map

| Path | Purpose |
| --- | --- |
| `shared/gpu/xmake.lua` | fetch and verify the try-omarchy kit runtime |
| `qemu/xmake.lua` | QEMU args, `vm` (GL default, `--2d`), `doctor` |
| `shared/qemu/xmake.lua` | keg bottles for `--2d` and `qemu-img` |
| `shared/image/xmake.lua` | base image: units, autologin, `tryDisplay` enable |
| `scripts/preparePayload.py` | dotfiles patches, including the dmabuf quirk |
| `guest/tryDisplay/*.go` | follows the window size and density in the guest |
