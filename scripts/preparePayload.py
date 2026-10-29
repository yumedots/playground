#!/usr/bin/env python3
"""Adjust the staged dotfiles so they work inside the try guest.

Patches the NVIDIA-only environment, the quickshell launcher binding, the
yudaemond build mode and writes the display cache, then points the user
session at yudaemond. The payload disk is read-only in the guest, so every
dotfile edit has to happen here, while the tree is still on the host.
"""

import os
import re
import sys

SCALE = "1"


def patch_envs(root):
    path = os.path.join(root, "hypr", "envs.lua")
    if not os.path.isfile(path):
        return
    with open(path) as handle:
        text = handle.read()
    old = (
        'hl.env("LIBVA_DRIVER_NAME", "nvidia")\n'
        'hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")\n'
        'hl.env("GBM_BACKEND", "nvidia-drm")\n'
    )
    new = (
        'if io.open("/dev/nvidia0") then\n'
        '  hl.env("LIBVA_DRIVER_NAME", "nvidia")\n'
        '  hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")\n'
        '  hl.env("GBM_BACKEND", "nvidia-drm")\n'
        'end\n'
    )
    if old in text:
        with open(path, "w") as handle:
            handle.write(text.replace(old, new))
        print("patched hypr/envs.lua for the nvidia-free guest")


def patch_launcher(root):
    path = os.path.join(root, "quickshell", "launcher", "Launcher.qml")
    if not os.path.isfile(path):
        return
    with open(path) as handle:
        text = handle.read()
    text = text.replace("property var data: Yudae.launcher", "property var launcherState: Yudae.launcher")
    text = text.replace("root.data", "root.launcherState")
    with open(path, "w") as handle:
        handle.write(text)
    print("patched quickshell/launcher/Launcher.qml")


def patch_build(root):
    path = os.path.join(root, "quickshell", "yudaemond", "build.zig")
    if not os.path.isfile(path):
        return
    with open(path) as handle:
        text = handle.read()
    text = text.replace(".preferred_optimize_mode = .small", ".preferred_optimize_mode = .ReleaseSmall")
    text = text.replace("!= .debug", "!= .Debug")
    with open(path, "w") as handle:
        handle.write(text)
    print("patched quickshell/yudaemond/build.zig")


def write_display(root):
    cache = os.path.join(root, "quickshell", "cache")
    os.makedirs(cache, exist_ok=True)
    with open(os.path.join(cache, "display.lua"), "w") as handle:
        handle.write('return {\n\tfallback = { mode = "", scale = %s },\n}\n' % SCALE)
    print("wrote quickshell/cache/display.lua")


def link_service(root):
    user = os.path.join(root, "systemd", "user")
    service = os.path.join(user, "yudaemond.service")
    if not os.path.isfile(service):
        return
    wants = os.path.join(user, "default.target.wants")
    os.makedirs(wants, exist_ok=True)
    link = os.path.join(wants, "yudaemond.service")
    if os.path.lexists(link):
        os.remove(link)
    os.symlink("../yudaemond.service", link)
    print("enabled the yudaemond user service")


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: preparePayload.py <staged dotfiles dir>")
    root = sys.argv[1]
    patch_envs(root)
    patch_launcher(root)
    patch_build(root)
    write_display(root)
    link_service(root)


if __name__ == "__main__":
    main()
