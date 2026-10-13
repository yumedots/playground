package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRemovePacmanLock(t *testing.T) {
	root := t.TempDir()
	processDir := filepath.Join(root, "proc")
	lockDir := filepath.Join(root, "var", "lib", "pacman")
	if err := os.MkdirAll(processDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(lockDir, 0755); err != nil {
		t.Fatal(err)
	}
	lock := filepath.Join(lockDir, "db.lck")
	if err := os.WriteFile(lock, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := removePacmanLock(processDir, lock); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(lock); !os.IsNotExist(err) {
		t.Fatalf("stale lock remains: %v", err)
	}
	pidDir := filepath.Join(processDir, "123")
	if err := os.Mkdir(pidDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(pidDir, "comm"), []byte("pacman\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(lock, nil, 0600); err != nil {
		t.Fatal(err)
	}
	if err := removePacmanLock(processDir, lock); err == nil {
		t.Fatal("active pacman lock was removed")
	}
	if _, err := os.Stat(lock); err != nil {
		t.Fatalf("active lock missing: %v", err)
	}
}
