package main

import (
	"fmt"
	"os"
	"path/filepath"
)

const sessionFile = "/usr/share/wayland-sessions/try.desktop"
const wrapperFile = "/usr/local/bin/Hyprland"

func writeSession() error {
	exec := "Hyprland"
	if info, err := os.Stat("/usr/bin/start-hyprland"); err == nil && !info.IsDir() {
		exec = "start-hyprland"
	}
	wrapper := "#!/bin/sh\nexport AQ_MGPU_NO_EXPLICIT=1\nexport AQ_NO_MODIFIERS=1\nexport AQ_FORCE_LINEAR_BLIT=1\nexec /usr/bin/Hyprland \"$@\"\n"
	if err := os.MkdirAll("/usr/local/bin", 0755); err != nil {
		return fmt.Errorf("create /usr/local/bin: %w", err)
	}
	if err := os.WriteFile(wrapperFile, []byte(wrapper), 0755); err != nil {
		return fmt.Errorf("write %s: %w", wrapperFile, err)
	}
	if err := os.MkdirAll(filepath.Dir(sessionFile), 0755); err != nil {
		return fmt.Errorf("create session directory: %w", err)
	}
	entry := fmt.Sprintf("[Desktop Entry]\nName=Hyprland\nComment=try desktop\nExec=%s\nType=Application\n", exec)
	if err := os.WriteFile(sessionFile, []byte(entry), 0644); err != nil {
		return fmt.Errorf("write %s: %w", sessionFile, err)
	}
	logf("session %s runs %s", sessionFile, exec)
	return nil
}
