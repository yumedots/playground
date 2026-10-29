package main

import (
	"fmt"
	"os"
	"os/user"
	"path/filepath"
	"strconv"
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

func ensureSddmHome() error {
	account, err := user.Lookup("sddm")
	if err != nil {
		return fmt.Errorf("lookup sddm: %w", err)
	}
	uid, err := strconv.Atoi(account.Uid)
	if err != nil {
		return fmt.Errorf("sddm uid: %w", err)
	}
	gid, err := strconv.Atoi(account.Gid)
	if err != nil {
		return fmt.Errorf("sddm gid: %w", err)
	}
	if err := os.MkdirAll(account.HomeDir, 0700); err != nil {
		return fmt.Errorf("create %s: %w", account.HomeDir, err)
	}
	if err := os.Chown(account.HomeDir, uid, gid); err != nil {
		return fmt.Errorf("chown %s: %w", account.HomeDir, err)
	}
	return nil
}

func showGreeter() error {
	if err := ensureSddmHome(); err != nil {
		return err
	}
	conf := "[General]\nDisplayServer=x11\nNumlock=on\n"
	if err := os.WriteFile("/etc/sddm.conf", []byte(conf), 0644); err != nil {
		return fmt.Errorf("write sddm.conf: %w", err)
	}
	logf("sddm greeter enabled, autologin off")
	return nil
}
