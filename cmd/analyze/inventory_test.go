//go:build darwin

package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestStorageInventoryDoesNotFollowLinksAndDeduplicatesHardlinks(t *testing.T) {
	root := t.TempDir()
	a := filepath.Join(root, "a")
	if err := os.WriteFile(a, []byte("same content"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Link(a, filepath.Join(root, "hardlink")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(t.TempDir(), filepath.Join(root, "outside")); err != nil {
		t.Fatal(err)
	}
	row, files := inspectStorage(context.Background(), root, true)
	if !row.Complete || len(files) != 1 {
		t.Fatalf("row=%+v files=%v", row, files)
	}
	info, _ := os.Stat(a)
	if row.EstimatedBytes != getActualFileSize(a, info) {
		t.Fatalf("hardlinks counted twice: %+v", row)
	}
}

func TestStorageDuplicatesRequireIdenticalContents(t *testing.T) {
	root := t.TempDir()
	for name, body := range map[string]string{"a": "identical", "b": "identical", "c": "different"} {
		if err := os.WriteFile(filepath.Join(root, name), []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
	}
	row, files := inspectStorage(context.Background(), root, true)
	if !row.Complete {
		t.Fatal(row)
	}
	groups, err := inventoryDuplicates(context.Background(), root, files)
	if err != nil {
		t.Fatal(err)
	}
	if len(groups) != 1 || len(groups[0]) != 2 || filepath.Base(groups[0][0]) != "a" || filepath.Base(groups[0][1]) != "b" {
		t.Fatalf("unexpected groups: %v", groups)
	}
	for _, file := range files {
		if _, err := os.Stat(file.path); err != nil {
			t.Fatal("inspection removed a file", err)
		}
	}
}

func TestStorageGrowthRequiresComparableCompleteScans(t *testing.T) {
	old := storageInventory{Schema: inventorySchema, Root: "/example", Complete: true, Finished: time.Now(), Rows: []storageRow{{Path: "/example/a", Identity: "device:inode", Complete: true, EstimatedBytes: 100}}}
	current := storageInventory{Schema: inventorySchema, Root: "/example", Started: time.Now().Add(time.Second), Complete: true, Rows: []storageRow{{Path: "/example/a", Identity: "device:inode", Complete: true, EstimatedBytes: 150}}}
	compareStorageInventory(old, &current)
	if current.Previous == nil || current.Rows[0].Growth == nil || *current.Rows[0].Growth != 50 {
		t.Fatal(current)
	}
	current.Previous = nil
	current.Rows[0].Growth = nil
	current.Complete = false
	compareStorageInventory(old, &current)
	if current.Previous != nil || current.Rows[0].Growth != nil {
		t.Fatal("partial scan produced growth")
	}
}

func TestStorageInventoryCancellationIsIncomplete(t *testing.T) {
	root := t.TempDir()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	row, _ := inspectStorage(ctx, root, false)
	if row.Complete || row.Error == "" {
		t.Fatal(row)
	}
}

func TestLocalScanExcludesCloudAndAppInteriorsFromDeletion(t *testing.T) {
	for _, path := range []string{"/Users/me/Library/CloudStorage/provider", "/Users/me/Library/Mobile Documents", "/Library/Developer/CoreSimulator/Volumes"} {
		if !excludedLocalTree(path) {
			t.Fatal(path)
		}
	}
	if !localResourceDeleteProtected("/Applications/Browser.APP/Contents/file") {
		t.Fatal("app interior not protected")
	}
	if localResourceDeleteProtected("/Users/me/Downloads/ordinary.txt") {
		t.Fatal("ordinary explicit selection blocked")
	}
}

func TestCommandTargetInDownloadsIsProtected(t *testing.T) {
	root := t.TempDir()
	bin := filepath.Join(root, "bin")
	downloads := filepath.Join(root, "Downloads")
	if err := os.MkdirAll(bin, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(downloads, 0700); err != nil {
		t.Fatal(err)
	}
	command := filepath.Join(downloads, "tool")
	if err := os.WriteFile(command, []byte("#!/bin/sh\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(command, filepath.Join(bin, "tool")); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin)
	t.Setenv("VIRTUAL_ENV", "")
	t.Setenv("CONDA_PREFIX", "")
	if err := protectActiveCommandPath(downloads); err == nil {
		t.Fatal("live command target accepted")
	}
	other := filepath.Join(root, "unrelated")
	if err := os.Mkdir(other, 0700); err != nil {
		t.Fatal(err)
	}
	if err := protectActiveCommandPath(other); err != nil {
		t.Fatal(err)
	}
}

func TestDuplicateInspectionRejectsReplacedFile(t *testing.T) {
	root := t.TempDir()
	for _, name := range []string{"a", "b"} {
		if err := os.WriteFile(filepath.Join(root, name), []byte("same"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	_, files := inspectStorage(context.Background(), root, true)
	if err := os.Rename(filepath.Join(root, "a"), filepath.Join(root, "old")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "a"), []byte("same"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := inventoryDuplicates(context.Background(), root, files); err == nil {
		t.Fatal("changed identity accepted")
	}
}

func TestInventoryBaselineRejectsPartialAndStalePublication(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	start := time.Now().Add(-time.Minute)
	base := storageInventory{Schema: inventorySchema, Root: "/fixture", Started: start, Finished: start.Add(time.Second), Complete: true,
		Rows: []storageRow{{Path: "/fixture/cache", Identity: "1:2", Complete: true, EstimatedBytes: 100}}}
	if err := updateInventoryBaseline(&base); err != nil {
		t.Fatal(err)
	}
	partial := base
	partial.Started = start.Add(10 * time.Second)
	partial.Complete = false
	if err := updateInventoryBaseline(&partial); err != nil {
		t.Fatal(err)
	}
	stale := base
	stale.Started = start.Add(-time.Second)
	if err := updateInventoryBaseline(&stale); err != nil {
		t.Fatal(err)
	}
	dir, err := getCacheDir()
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(dir, "inventory.json"))
	if err != nil {
		t.Fatal(err)
	}
	var saved storageInventory
	if err := json.Unmarshal(data, &saved); err != nil {
		t.Fatal(err)
	}
	if !saved.Started.Equal(base.Started) || !saved.Complete {
		t.Fatalf("baseline replaced: %+v", saved)
	}
	current := base
	current.Started = start.Add(20 * time.Second)
	current.Finished = current.Started.Add(time.Second)
	current.Rows = []storageRow{{Path: "/fixture/cache", Identity: "1:2", Complete: true, EstimatedBytes: 150}}
	if err := updateInventoryBaseline(&current); err != nil {
		t.Fatal(err)
	}
	if current.Rows[0].Growth == nil || *current.Rows[0].Growth != 50 {
		t.Fatal("comparable growth missing")
	}
	replaced := base
	replaced.Rows = []storageRow{{Path: "/fixture/cache", Identity: "1:3", Complete: true, EstimatedBytes: 200}}
	replaced.Started = current.Finished.Add(time.Second)
	compareStorageInventory(current, &replaced)
	if replaced.Rows[0].Growth != nil {
		t.Fatal("replacement identity compared as growth")
	}
}

func TestInvokingProjectIsProtectedAtTrashBoundary(t *testing.T) {
	project := t.TempDir()
	if err := os.WriteFile(filepath.Join(project, "package.json"), []byte("{}"), 0600); err != nil {
		t.Fatal(err)
	}
	cache := filepath.Join(project, "build")
	if err := os.Mkdir(cache, 0700); err != nil {
		t.Fatal(err)
	}
	t.Chdir(project)
	t.Setenv("PATH", "")
	t.Setenv("VIRTUAL_ENV", "")
	t.Setenv("CONDA_PREFIX", "")
	if err := protectActiveCommandPath(cache); err == nil {
		t.Fatal("invoking project was not protected")
	}
	if err := protectActiveCommandPath(t.TempDir()); err != nil {
		t.Fatal(err)
	}
}
