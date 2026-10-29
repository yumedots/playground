package main

import (
	"fmt"
	"os"
	"path/filepath"
)

const sessionFile = "/usr/share/wayland-sessions/try.desktop"

func writeSession() error {
	exec := "Hyprland"
	if info, err := os.Stat("/usr/bin/start-hyprland"); err == nil && !info.IsDir() {
		exec = "start-hyprland"
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
