package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
)

type guestUser struct {
	name  string
	home  string
	uid   int
	gid   int
	shell string
}

func resolveUser(uid int) (guestUser, error) {
	user, err := lookupUser(strconv.Itoa(uid))
	if err == nil {
		return user, nil
	}
	if uid != 1000 {
		if _, lookupErr := lookupUser("alarm"); lookupErr == nil {
			if _, err := command("usermod", "-u", strconv.Itoa(uid), "alarm"); err != nil {
				return guestUser{}, err
			}
			if _, err := command("groupmod", "-g", strconv.Itoa(uid), "alarm"); err != nil {
				return guestUser{}, err
			}
			return lookupUser(strconv.Itoa(uid))
		}
	}
	return guestUser{}, fmt.Errorf("no guest user with uid %d", uid)
}

func normalizeGuestOwnership(user guestUser) error {
	for _, path := range []string{"/", "/home"} {
		if _, err := os.Lstat(path); os.IsNotExist(err) {
			continue
		}
		if err := chownIfNeeded(path, 0, 0); err != nil {
			return fmt.Errorf("chown %s: %w", path, err)
		}
	}
	for _, path := range []string{"/boot", "/etc", "/lib", "/lib64", "/opt", "/root", "/sbin", "/usr", "/var"} {
		if _, err := os.Lstat(path); os.IsNotExist(err) {
			continue
		}
		if err := filepath.Walk(path, func(current string, info os.FileInfo, err error) error {
			if err != nil {
				return err
			}
			return chownIfNeeded(current, 0, 0)
		}); err != nil {
			return fmt.Errorf("chown %s: %w", path, err)
		}
	}
	if err := chownIfNeeded(user.home, user.uid, user.gid); err != nil {
		return fmt.Errorf("chown %s: %w", user.home, err)
	}
	return restoreSpecialModes()
}

func chownIfNeeded(path string, uid, gid int) error {
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); ok && int(stat.Uid) == uid && int(stat.Gid) == gid {
		return nil
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return os.Lchown(path, uid, gid)
	}
	return os.Chown(path, uid, gid)
}

func restoreSpecialModes() error {
	data, err := os.ReadFile("/usr/local/lib/try/special-modes.txt")
	if err != nil {
		return fmt.Errorf("read special mode manifest: %w", err)
	}
	for _, line := range strings.Split(string(data), "\n") {
		mode, name, found := strings.Cut(line, "|")
		if !found || name == "" {
			continue
		}
		permissions, err := strconv.ParseUint(mode, 8, 32)
		if err != nil {
			return fmt.Errorf("parse special mode %q: %w", mode, err)
		}
		if strings.HasPrefix(name, "/") || filepath.Clean(name) != name || name == ".." || strings.HasPrefix(name, "../") {
			return fmt.Errorf("invalid special mode path %q", name)
		}
		if err := os.Chmod(filepath.Join("/", name), specialMode(permissions)); err != nil {
			return fmt.Errorf("restore mode for %s: %w", name, err)
		}
	}
	return nil
}

func specialMode(permissions uint64) os.FileMode {
	mode := os.FileMode(permissions & 0o777)
	if permissions&0o4000 != 0 {
		mode |= os.ModeSetuid
	}
	if permissions&0o2000 != 0 {
		mode |= os.ModeSetgid
	}
	if permissions&0o1000 != 0 {
		mode |= os.ModeSticky
	}
	return mode
}

func lookupUser(identifier string) (guestUser, error) {
	data, err := os.ReadFile("/etc/passwd")
	if err != nil {
		return guestUser{}, fmt.Errorf("read passwd: %w", err)
	}
	for _, line := range strings.Split(string(data), "\n") {
		fields := strings.Split(line, ":")
		if len(fields) < 7 || (identifier != fields[0] && identifier != fields[2]) {
			continue
		}
		uid, _ := strconv.Atoi(fields[2])
		gid, _ := strconv.Atoi(fields[3])
		return guestUser{name: fields[0], home: fields[5], uid: uid, gid: gid, shell: fields[6]}, nil
	}
	return guestUser{}, fmt.Errorf("user %s not found", identifier)
}
