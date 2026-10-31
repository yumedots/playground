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

`scripts/bench.sh` against a running `xmake vm` (it brings the window to the
front, since macOS throttles an occluded QEMU window to about 11 FPS). M3 Pro,
8 vCPUs, 8 GB, 2144x1206 at 120 Hz, 15 s per scenario. Host GPU is `ioreg`
"Device Utilization %" for the whole machine, 10-14% with no VM running.

| Scenario | Before (nested, userspace GIC) | Now | Host GPU now | Notes |
| --- | --- | --- | --- | --- |
| idle | 1% | 1% | 10% | |
| workspaces, 3 foot, every 0.2 s | 20% | 14% | 22% | Hyprland 4% in guest |
| es2gears | 18%, 106 FPS | 13%, 120 FPS | 29% | |
| glmark2 build | 21%, 522 FPS | 24%, 1367 FPS | 49% | |
| foot flooding `seq` | 407% | ~400% | 30% | guest pty work, not display |
| 2D `--2d`, workspaces | 497% | not rerun | 16% | llvmpipe |

What moved it:

- Nested virtualization off by default (`nested=on` in `state/settings`
  brings it back for guest `/dev/kvm`). Under EL2 every guest exit is
  emulated by Hypervisor.framework: gears used 22% and glmark2 34% with it.
- `-accel hvf,kernel-irqchip=on`: the in-kernel GICv3 cuts the vCPU
  exits, which are most of the workspace switching cost (20% to 14%).
- `-cpu host,pmu=off`, matching try-omarchy.
- 60 Hz EDID would cut gears to about 10% but halves smoothness; not applied.
- 4 vCPUs instead of 8 gives the same display numbers and cuts the flood to
  323%.

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
