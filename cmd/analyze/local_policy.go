//go:build darwin

package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// These trees are never traversed, even when they are locally mounted.
func excludedLocalTree(path string) bool {
	p := strings.ToLower(filepath.Clean(path)) + "/"
	for _, fragment := range []string{"/library/cloudstorage/", "/library/mobile documents/", "/coresimulator/volumes/", "/coresimulator/cryptex/"} {
		if strings.Contains(p, fragment) {
			return true
		}
	}
	return false
}

// Expensive command resolution belongs at the action boundary, not row rendering.
func protectActiveCommandPath(path string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	target, err := filepath.EvalSymlinks(path)
	if err != nil {
		return err
	}
	contains := func(p string) bool { return p == target || strings.HasPrefix(p, target+string(filepath.Separator)) }
	working, err := os.Getwd()
	if err != nil {
		return err
	}
	working, err = filepath.EvalSymlinks(working)
	if err != nil {
		return err
	}
	for dir := working; dir != filepath.Dir(dir); dir = filepath.Dir(dir) {
		for _, marker := range []string{".git", "pyproject.toml", "package.json", "go.mod"} {
			if _, err := os.Lstat(filepath.Join(dir, marker)); err == nil {
				if contains(dir) || strings.HasPrefix(target, dir+string(filepath.Separator)) {
					return fmt.Errorf("invoking project is protected")
				}
				// Only the nearest enclosing project defines this invocation.
				working = ""
				break
			}
		}
		if working == "" {
			break
		}
	}
	for _, variable := range []string{"VIRTUAL_ENV", "CONDA_PREFIX"} {
		if value := os.Getenv(variable); value != "" {
			resolved, err := filepath.EvalSymlinks(value)
			if err != nil {
				return fmt.Errorf("active environment could not be inspected")
			}
			if contains(resolved) || strings.HasPrefix(target, resolved+string(filepath.Separator)) {
				return fmt.Errorf("active environment is protected")
			}
		}
	}
	for _, dir := range filepath.SplitList(os.Getenv("PATH")) {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if dir == "" {
			dir = "."
		}
		if excludedLocalTree(dir) || strings.HasPrefix(dir, "/Volumes/") {
			return fmt.Errorf("nonlocal PATH entry cannot be inspected")
		}
		entries, err := os.ReadDir(dir)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return fmt.Errorf("PATH entry cannot be inspected: %w", err)
		}
		for _, entry := range entries {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if entry.IsDir() {
				continue
			}
			command, err := filepath.EvalSymlinks(filepath.Join(dir, entry.Name()))
			if os.IsNotExist(err) {
				continue
			}
			if err != nil {
				return err
			}
			info, err := os.Stat(command)
			if err != nil {
				return err
			}
			if info.Mode().IsRegular() && info.Mode().Perm()&0111 != 0 && contains(command) {
				return fmt.Errorf("selected path contains a command on PATH")
			}
		}
	}
	return nil
}

func localScanPath(path string) error {
	if excludedLocalTree(path) {
		return fmt.Errorf("cloud-managed or Apple-owned storage is excluded: %s", path)
	}
	info, err := os.Lstat(path)
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("symbolic link is not traversed: %s", path)
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); ok && stat.Flags&0x40000000 != 0 { // SF_DATALESS, sys/stat.h
		return fmt.Errorf("cloud placeholder is not read: %s", path)
	}
	var fs syscall.Statfs_t
	if err := syscall.Statfs(path, &fs); err != nil {
		return err
	}
	if fs.Flags&0x1000 == 0 { // MNT_LOCAL, sys/mount.h
		return fmt.Errorf("only local filesystems are supported: %s", path)
	}
	return nil
}

func localResourceDeleteProtected(path string) bool {
	if excludedLocalTree(path) {
		return true
	}
	parts := strings.Split(filepath.Clean(path), string(filepath.Separator))
	for index, component := range parts {
		lower := strings.ToLower(component)
		if lower == ".git" {
			return true
		}
		if strings.HasSuffix(lower, ".app") {
			bundle := strings.Join(parts[:index+1], string(filepath.Separator))
			// Reverse-DNS cache names ending in .app are not application bundles.
			if (index > 0 && strings.EqualFold(parts[index-1], "Applications")) || (index+1 < len(parts) && parts[index+1] == "Contents") {
				return true
			}
			if _, err := os.Lstat(filepath.Join(bundle, "Contents", "Info.plist")); err == nil {
				return true
			}
		}
	}
	return false
}
