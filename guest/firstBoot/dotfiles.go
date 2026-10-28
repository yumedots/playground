package main

import (
	"fmt"
	"os"
	"path/filepath"
)

func dotfileSources(root string) ([]string, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, fmt.Errorf("read dotfiles source %s: %w; check the submodule is populated", root, err)
	}
	if len(entries) == 0 {
		return nil, fmt.Errorf("dotfiles source %s is empty; check the submodule is populated", root)
	}
	var sources []string
	for _, entry := range entries {
		source := filepath.Join(root, entry.Name())
		if _, err := os.Stat(source); err != nil {
			return nil, fmt.Errorf("dotfiles source missing %s: %w", source, err)
		}
		sources = append(sources, source)
	}
	return sources, nil
}

func linkDotfiles(config string, sources []string, user guestUser) error {
	if err := os.MkdirAll(config, 0755); err != nil {
		return fmt.Errorf("create config directory: %w", err)
	}
	for _, source := range sources {
		destination := filepath.Join(config, filepath.Base(source))
		if _, err := os.Lstat(destination); err == nil {
			if err := os.RemoveAll(destination); err != nil {
				return fmt.Errorf("replace %s: %w", destination, err)
			}
		} else if !os.IsNotExist(err) {
			return fmt.Errorf("inspect %s: %w", destination, err)
		}
		if err := linkTree(source, destination); err != nil {
			return err
		}
		logf("linked %s -> %s", destination, source)
	}
	if err := filepath.Walk(config, func(current string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if !info.IsDir() {
			return nil
		}
		if err := os.Chown(current, user.uid, user.gid); err != nil {
			return fmt.Errorf("chown %s: %w", current, err)
		}
		return nil
	}); err != nil {
		logf("chown %s: %v", config, err)
	}
	return nil
}

func linkTree(source, destination string) error {
	info, err := os.Lstat(source)
	if err != nil {
		return fmt.Errorf("inspect %s: %w", source, err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		if err := os.Symlink(source, destination); err != nil {
			return fmt.Errorf("link %s to %s: %w", source, destination, err)
		}
		return nil
	}
	if err := os.MkdirAll(destination, info.Mode().Perm()); err != nil {
		return fmt.Errorf("create %s: %w", destination, err)
	}
	entries, err := os.ReadDir(source)
	if err != nil {
		return fmt.Errorf("read %s: %w", source, err)
	}
	for _, entry := range entries {
		if err := linkTree(filepath.Join(source, entry.Name()), filepath.Join(destination, entry.Name())); err != nil {
			return err
		}
	}
	return nil
}
