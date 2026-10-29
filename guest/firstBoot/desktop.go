package main

import (
	"fmt"
	"os"
	"path/filepath"
)

const guestPassword = "alarm"

func buildYudaemond(user guestUser) error {
	dir := filepath.Join(user.home, ".config", "quickshell", "yudaemond")
	if info, err := os.Stat(filepath.Join(dir, "build.zig")); err != nil || info.IsDir() {
		logf("no yudaemond sources, skipping the build")
		return nil
	}
	build := fmt.Sprintf("cd %s && zig build 2>&1 | tail -5", dir)
	if output, err := command("runuser", "-u", user.name, "--", "sh", "-c", build); err != nil {
		logf("yudaemond build: %v: %s", err, output)
		return nil
	}
	os.RemoveAll(filepath.Join(dir, ".zig-cache"))
	os.RemoveAll(filepath.Join(user.home, ".cache", "zig"))
	if info, err := os.Stat(filepath.Join(dir, "zig-out", "bin", "yudaemond")); err == nil && !info.IsDir() {
		logf("built yudaemond")
	}
	return nil
}

func setPassword(user guestUser) error {
	line := fmt.Sprintf("%s:%s", user.name, guestPassword)
	if _, err := command("sh", "-c", "echo '"+line+"' | chpasswd"); err != nil {
		return fmt.Errorf("set password: %w", err)
	}
	logf("password for %s is %s", user.name, guestPassword)
	return nil
}

func showGreeter() error {
	conf := "[General]\nDisplayServer=x11\nNumlock=on\n"
	if err := os.WriteFile("/etc/sddm.conf", []byte(conf), 0644); err != nil {
		return fmt.Errorf("write sddm.conf: %w", err)
	}
	logf("sddm greeter enabled, autologin off")
	return nil
}
