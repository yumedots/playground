# Handoff: GPU display is still black

## Objective

Show the guest desktop through the GPU (virgl) path instead of the working 2D
software fallback. `xmake vm` must open a window that renders Hyprland with
`+virgl` active and low host CPU.

Status: **not done**. The GPU renders (guest side works, CPU drops from 70% to
1% of a core), but the cocoa window stays black. Everything below is what was
implemented, what was measured, and the exact experiments left.

## What works right now

- `xmake vm` (default, **2D llvmpipe**): autologin on tty1 into Hyprland with the
  quickshell bar. Verified screenshot: `docs/evidence/desktop2d.png`.
- Image pipeline: CI builds `base.qcow2` + kernel + initramfs and publishes them
  to the `image` pre-release of this repo; `xmake vm` downloads and sha256-checks
  them (839 MB, ~2 min).
- First boot installs the full desktop stack from `guest/packages.txt`
  (Hyprland, quickshell, zig-built `yudaemond`, foot, sddm, xorg, ...), mirrors
  `hypr/` and `quickshell/` into `~/.config`, sets the alarm password (`alarm`)
  and writes the Hyprland session entry.
- Disk pruning: `xmake prune`, `--all`, `--disk`; builds drop the tarball, bottle
  archives and payload staging automatically.
- `xmake fetch` no longer clobbers a fork build in the keg (it reinstalls
  `~/qemu/build/qemu-system-aarch64` when present, `TRY_QEMU_REPO` overrides the
  path).

Commits on `main`: `29d7bf9` (autologin, latest), `1fc9533` (pruning),
`6bde546`, plus the SDDM/session/dotfiles/GPU series before them.
Fork `~/qemu`, branch `omarchy-gpu`: `4357a8f497` (ported cocoa GL stack),
`e860c3fb01` (`TRY_FIXED_MODE`). The fork is **local only**, not pushed.

## What was ported from try-omarchy

Source: `.cache/try-omarchy` (clone of github.com/omacom/try-omarchy).

- `macos/patches/qemu-texture-borrowing-11.1.patch` plus
  `qemu-cocoa-dynamic-display`, `qemu-darwin-gpu-fence-poll`,
  `qemu-cocoa-no-app-nap`, `qemu-darwin-main-loop-qos`,
  `qemu-cocoa-minimum-guest-size`.
- Applied to pristine QEMU `c3d48b7d1e89604920e5b81b91140c2ad39a1943` first, then
  the touched files were copied into our fork: `ui/cocoa.m`,
  `hw/display/virtio-gpu-virgl.c`, `ui/console.c`, `ui/egl-helpers.c`,
  `ui/egl-headless.c`, `ui/sdl2*.c`, `include/ui/*`, `system/main.c`, shaders.
  Our fork's own `meson.build` / `ui/meson.build` were kept (they already had the
  `egl` split; theirs referenced `have_hmp` and broke the build).
- Build (in `~/qemu`, keg deps):
  ```sh
  KEG=/Users/gabriel/try/.cache/qemu
  export PKG_CONFIG_PATH="$KEG/opt/libangle/lib/pkgconfig:$KEG/opt/libepoxy-angle/lib/pkgconfig:$KEG/opt/virglrenderer/lib/pkgconfig"
  ./configure --target-list=aarch64-softmmu --enable-cocoa --enable-opengl \
    --enable-virglrenderer --enable-slirp --enable-curses --disable-dbus-display \
    --disable-sdl --disable-gtk --disable-docs --disable-guest-agent --disable-bsd-user \
    --disable-tools --disable-plugins --disable-pvg \
    --extra-cflags="-I$KEG/opt/libangle/include -I$KEG/opt/libepoxy-angle/include -I$KEG/opt/virglrenderer/include -I$KEG/opt/virglrenderer/include/virgl" \
    --extra-ldflags="-L$KEG/opt/libangle/lib -L$KEG/opt/libepoxy-angle/lib -L$KEG/opt/virglrenderer/lib -Wl,-rpath,$KEG/opt/libangle/lib -Wl,-rpath,$KEG/opt/libepoxy-angle/lib -Wl,-rpath,$KEG/opt/virglrenderer/lib"
  cd build && ninja qemu-system-aarch64
  cd /Users/gabriel/try && xmake vminstall
  ```
  **Note:** `~/qemu/build` is currently deleted to save disk; rebuild with the
  block above (≈15 min). `--disable-dbus-display` is required: our fork's
  `ui/dbus-console.c` still has the old `dpy_gl_scanout_texture` signature.
- Their virglrenderer: source `ca50e008863837e094747a69974dde3ae148aeaa`, plus 21
  patches from `startergo/homebrew-virglrenderer` (tap commit
  `e7daef144d249a38d6206153e6146539f893eae2`) and their `virgl-native-opengl` and
  `virgl-ctx0-upload-flush`. Built with `-Ddrm-renderers=[] -Dvenus=false
  -Dtests=false -Dvideo=false`. Installed over
  `.cache/qemu/opt/virglrenderer/lib/libvirglrenderer.1.dylib` (580 KB, the
  bottle was 2 MB) after fixing its install name:
  `install_name_tool -change '@@HOMEBREW_PREFIX@@/opt/libepoxy-angle/lib/libepoxy.0.dylib' $KEG/opt/libepoxy-angle/lib/libepoxy.0.dylib ...`.
- Their pinned `libepoxy 1.0.5` and `ANGLE 1.0.16` bottles were swapped into the
  keg (`opt/libepoxy-angle`, `opt/libangle`) because the milesbuckton epoxy lacks
  `_epoxy_glVertexAttrib4fv`.

**Keg state now:** the bottle QEMU + bottle libs (a `xmake fetch` re-extracted
them; `vminstall` then failed because `~/qemu/build` is gone). So the GL stack
must be reconstituted with the steps above before retrying GL.

## How to run the GL path

```sh
xmake vm --print-args --gl > /tmp/pargs.txt
sed -n 's/^arg=//p' /tmp/pargs.txt > /tmp/argv.txt
# then rewrite two arguments:
#   virtio-gpu-gl-pci,...            -> virtio-gpu-gl-pci,max_outputs=1,hostmem=256M,xres=1512,yres=982
#   cocoa,gl=on,...                  -> cocoa,gl=es,zoom-to-fit=on,full-grab=on,swap-opt-cmd=off
# and run the printed program with those args, plus:
#   -monitor unix:/tmp/mon.sock,server=on,wait=off
# env: TRY_FIXED_MODE=1512x982   (pins the guest mode, fork commit e860c3fb01)
```

Guest access while it runs: `ssh -p 2222 alarm@127.0.0.1`, password `alarm`
(sshd is enabled; `alarm` is **not** in sudoers).

## Measurements that matter

- Guest: `[drm] features: +virgl +edid +resource_blob +host_visible` (with
  `hostmem`), hyprland log says `Renderer: virgl (Apple M3 Pro)`, no Xorg,
  active VT tty1, Hyprland CPU ≈ 1% of a core (2D path: 70%).
- Fences are healthy: `-trace virtio_gpu_fence_resp` logged 706 responses in a
  minute, so the guest is not stalled.
- `COCOA_GL_TRACE=1` on a GL boot prints, every frame:
  ```
  scanout texture id=190 region=800x600+0+0
  refresh: triggering render dirty=0 scanout=1 egl_surface=1
  render start size=700x524 dirty=0 scanout=1 filter=nearest
  initial draw FBO=0
  before bind borrow fb=0 fb_status=0x8cd5 tex=10
  after texture blit fb=0 err=0x0
  render end: GL_NO_ERROR
  eglSwapBuffers: GL_NO_ERROR
  ```
  `0x8cd5` is `GL_FRAMEBUFFER_COMPLETE`, so the host believes it worked, yet the
  window is black.
- A temporary `glReadPixels` dump of the window framebuffer (env `TRY_GL_DUMP`,
  removed again) captured the **console** frame at start-up, i.e. the 2D path
  does reach the screen; later dumps were empty/black.
- With `-display cocoa,gl=es` the **SDDM greeter rendered through the GL path**
  (screenshot was taken; X11 uses glamor), so the present step can work.
- **try-omarchy's own built QEMU + their own pinned libraries** show the same
  black window with our guest image (Hyprland running at 2144×1206). So the ported
  host stack is not what is missing; the guest is the remaining variable.

## Ruled out

- Guest mode / size mismatch: `TRY_FIXED_MODE=1512x982` pins `hyprctl monitors`
  to `1512x982@119.99` and the window is still black.
- `AQ_NO_MODIFIERS`, `AQ_FORCE_LINEAR_BLIT`, `AQ_MGPU_NO_EXPLICIT` (verified in
  `/proc/<pid>/environ`), `WLR_RENDERER_ALLOW_SOFTWARE`.
- `hostmem`/`+host_visible` vs plain texture scanout; `xres/yres` values.
- SDDM/Xorg holding DRM master (X really did stay on vt2 and block Hyprland —
  fixed by replacing SDDM with getty autologin).
- `swap-opt-cmd`, `show-cursor`, `full-screen`, `max_outputs=1`, `romfile=`.

## Omarchy A/B comparison (run this first — it is unblocked now)

Disk has >100 GB free, so the reference guest can be pulled. The goal is to boot
**their** guest with **our** binary/libraries: if their desktop renders under the
same cocoa path, the bug is in our guest (Mesa/compositor/session); if it also
stays black, the bug is host-side after all.

```sh
cd /Users/gabriel/try
mkdir -p .cache/omarchy-ab && cd .cache/omarchy-ab
# their factory disk ships as three release parts (release v1.2.0 at the time of writing)
gh release view --repo omacom/try-omarchy --json tagName -q .tagName
for p in 001 002 003; do
  gh release download v1.2.0 --repo omacom/try-omarchy \
    --pattern "omarchy-aarch64-edge.img.zst.$p" --dir . --clobber
done
cat omarchy-aarch64-edge.img.zst.00* > omarchy.img.zst
zstd -d -f omarchy.img.zst -o omarchy.img          # ~3 GB compressed, expect ~8-10 GB raw
KEG=/Users/gabriel/try/.cache/qemu
cp "$KEG/share/qemu/edk2-aarch64-code.fd" .
cp "$KEG/share/qemu/edk2-aarch64-vars.fd" vars.fd  # the keg ships the edk2 firmware
"$KEG/bin/qemu-system-aarch64" \
  -machine virt,accel=hvf,highmem=on,virtualization=on -cpu host -smp 8 -m 8G -nodefaults \
  -drive if=pflash,format=raw,readonly=on,file=edk2-aarch64-code.fd \
  -drive if=pflash,format=raw,file=vars.fd \
  -drive if=none,id=root,file=omarchy.img,format=raw,cache=writeback \
  -device virtio-blk-pci,drive=root,serial=root,bootindex=0 \
  -device virtio-gpu-gl-pci,max_outputs=1,hostmem=256M,xres=1512,yres=982 \
  -display "cocoa,gl=es,zoom-to-fit=on,full-grab=on,swap-opt-cmd=off" \
  -device virtio-keyboard-pci -device virtio-tablet-pci \
  -device qemu-xhci -device usb-kbd \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2299-:22 -device virtio-net-pci,netdev=n0 \
  -object rng-random,id=rng,filename=/dev/urandom -device virtio-rng-pci,rng=rng \
  -monitor unix:/tmp/ab.sock,server=on,wait=off
```

Capture the window like everywhere else:

```sh
python3 - <<'EOF'
import subprocess
out = subprocess.run(['swift','/tmp/winlist.swift'], capture_output=True, text=True).stdout
best = None
for line in out.splitlines():
    if 'qemu' not in line.lower() or not line.split() or not line.split()[0].isdigit(): continue
    try: w,h = float(line.split()[-2]), float(line.split()[-1])
    except ValueError: continue
    if not best or w*h > best[0]: best = (w*h, line.split()[0], w, h)
print(best)
if best: subprocess.run(['screencapture','-x','-l',best[1],'/tmp/ab.png'])
EOF
```

(`/tmp/winlist.swift` is a tiny CoreGraphics dumper that prints `<id> <owner> | <w> <h>`;
recreate it if missing: it iterates `CGWindowListCopyWindowInfo(.optionAll)`.)

Notes for this A/B:
- Our fork binary currently needs rebuilding first (`~/qemu/build` was deleted to save
  disk; the configure command is above). Using the keg's bottle QEMU is fine for the
  A/B too — both were black with our guest, so either isolates the guest.
- Their guest boots through UEFI + limine, not `-kernel`; the pflash drives above are
  the whole trick. Firmware also exists in their repo (`stage-uefi-firmware.sh` pulls
  it out of the pinned QEMU source).
- Their disk ships services that expect their app's virtio-serial bridges; without
  them the session should still come up (the package tolerates missing devices), but
  the Mac integrations (clipboard, battery, audio) will be absent. That is fine, only
  the picture matters here.
- If their desktop shows: ssh into it if possible (their factory user/keys are in
  `guest/factory/`), or read the raw image offline, and compare against our guest:
  `mesa`, `hyprland`, `aquamarine`, `quickshell` versions, `hyprctl -j monitors`,
  `/usr/lib/environment.d/*`, `~/.config/hypr/*.lua`, and the `try-omarchy` package.
- If their desktop is black too, jump to experiments 1-2 below (texture/context
  instrumentation) because the guest is exonerated.

## Next experiments (in order)

1. **Dump the borrowed texture itself**, not the window: in
   `ui/cocoa.m`'s borrow branch, right after `glBindTexture(..., texture.id)` and
   before `qemu_gl_run_texture_blit`, `glGetTexImage(GL_TEXTURE_2D, 0, ...)` into
   a PPM keyed by a trigger file (so it fires long after Hyprland is up). If it is
   black, the borrow returns the wrong object/context; if it has the desktop, the
   present/swap chain is at fault.
2. **Context sharing check**: print the EGL context used by
   `qemu_egl_rn_ctx` (QEMU render) and the one virglrenderer uses
   (`virgl_renderer_get_egl_context`-style accessor / `eglQueryContext`), and
   whether `eglMakeCurrent` succeeds before the blit. All current evidence is
   consistent with "texture lives in a different context than the one sampling
   it".
3. **Try `-display cocoa,gl=on` with the native-CGL branch** (`egl_surface ==
   EGL_NO_SURFACE`, `cocoa_gl_create_nscontext`) *after* installing the native
   virglrenderer + startergo epoxy/ANGLE. The `gl=on` branch was only tested with
   the old bottles, before the dependency swap.
4. **A/B the guest** — see the section above; it is now unblocked (>100 GB free).

## Environment gotchas

- macOS 26, arm64. `python3` on PATH is 3.9 (no `tomllib`); use
  `PATH=/opt/homebrew/bin:$PATH` for meson builds.
- try-omarchy's runtime build needs three test blocks stubbed out (the virgl
  driver/format regression runners and libslirp's `meson test`) — they fail on
  linker symbols, not on the build itself. They are already stubbed in
  `.cache/try-omarchy/macos/build-qemu-gpu-runtime.sh`.
- Disk: `xmake prune --all` drops the extracted root tree, `--disk` drops the
  ~5 GB guest overlay (next boot re-provisions in ~4 min). The host had ~120 GB
  free at handoff time, so the Omarchy A/B fits.
- Guest first boot installs ~65 packages from `guest/packages.txt`; a flaky
  mirror used to abort provisioning, now retried 5 times.

## File map

| Path | Purpose |
| --- | --- |
| `qemu/xmake.lua` | QEMU args, `vm`, `vminstall`, `shared.qemu_install_fork` |
| `shared/qemu/xmake.lua` | bottle pins, download/extract/patch, dependency fixes |
| `shared/image/xmake.lua` | base image build: units, autologin, session entry, env |
| `shared/payload/xmake.lua` | dotfiles payload disk + patch application |
| `scripts/preparePayload.py` | dotfiles patches applied at payload build |
| `guest/firstBoot/*.go` | provisioning, session entry, yudaemond build, sddm/autologin |
| `guest/packages.txt` | packages installed on first boot |
| `patches/*.patch` | dotfiles fixes; `qemuCocoaDisplay.patch` mirrors the fork work |
| `.github/workflows/image.yml` | builds the image, publishes the `image` pre-release |
| `.cache/try-omarchy` | reference clone (patches, guest package, runtime build) |

## Evidence

- `docs/evidence/desktop2d.png` — working 2D desktop (autologin, quickshell bar).
- The black GL window was captured repeatedly during the session
  (`/tmp/fixed_win.png` etc. are gone after reboots); reproduce with the command
  block above and `screencapture -l <qemu window id>`.
