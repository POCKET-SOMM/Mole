//go:build darwin

package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"time"
)

const inventorySchema = 1

type storageRow struct {
	Path           string    `json:"path"`
	Identity       string    `json:"identity"`
	EstimatedBytes int64     `json:"estimated_allocated_bytes"`
	Modified       time.Time `json:"modified"`
	Complete       bool      `json:"complete"`
	KeptReason     string    `json:"kept_reason"`
	Error          string    `json:"error,omitempty"`
	Growth         *int64    `json:"growth_since_previous_scan,omitempty"`
}

type storageInventory struct {
	Schema     int          `json:"schema"`
	Root       string       `json:"root"`
	Started    time.Time    `json:"started"`
	Finished   time.Time    `json:"finished"`
	Previous   *time.Time   `json:"previous_scan,omitempty"`
	Complete   bool         `json:"complete"`
	Rows       []storageRow `json:"rows"`
	Duplicates [][]string   `json:"identical_content_candidates,omitempty"`
	Notes      []string     `json:"notes"`
}

type inventoryFile struct {
	path string
	info fs.FileInfo
}

// Root-scoped walks do not follow directory symlinks or escape via renamed
// ancestors. Size is allocated-file metadata, not a promise of reclaimability.
func inspectStorage(ctx context.Context, path string, collectFiles bool) (storageRow, []inventoryFile) {
	row := storageRow{Path: path, Complete: true, KeptReason: "Inspection only; ownership and offline recovery must be reviewed before any removal"}
	if inventoryIsModel(path) {
		row.KeptReason = "Model data is retained for offline use; differing formats and absent references do not prove duplication or disuse"
	}
	if err := localScanPath(path); err != nil {
		row.Complete = false
		row.Error = err.Error()
		return row, nil
	}
	info, err := os.Lstat(path)
	if err != nil {
		row.Complete = false
		row.Error = err.Error()
		return row, nil
	}
	row.Modified = info.ModTime()
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		row.Identity = fmt.Sprintf("%d:%d", stat.Dev, stat.Ino)
	}
	if !info.IsDir() {
		row.EstimatedBytes = getActualFileSize(path, info)
		return row, nil
	}
	root, err := os.OpenRoot(path)
	if err != nil {
		row.Complete = false
		row.Error = err.Error()
		return row, nil
	}
	defer root.Close()
	seen := make(map[[2]uint64]bool)
	files := []inventoryFile{}
	count := 0
	err = fs.WalkDir(root.FS(), ".", func(name string, d fs.DirEntry, walkErr error) error {
		if err := ctx.Err(); err != nil {
			return err
		}
		count++
		if count > 100000 {
			return fmt.Errorf("entry budget reached")
		}
		if walkErr != nil {
			return walkErr
		}
		full := filepath.Join(path, name)
		if excludedLocalTree(full) {
			row.Complete = false
			row.Error = "Cloud or Apple-owned descendants excluded"
			return fs.SkipDir
		}
		if d.Type()&os.ModeSymlink != 0 {
			return nil
		}
		st, err := d.Info()
		if err != nil {
			return err
		}
		stat, ok := st.Sys().(*syscall.Stat_t)
		if !ok {
			return fmt.Errorf("file identity unavailable")
		}
		if stat.Flags&0x40000000 != 0 {
			row.Complete = false
			row.Error = "Cloud placeholders excluded"
			if d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			if err := localScanPath(full); err != nil {
				row.Complete = false
				row.Error = err.Error()
				return fs.SkipDir
			}
			return nil
		}
		if !st.Mode().IsRegular() {
			return nil
		}
		id := [2]uint64{uint64(uint32(stat.Dev)), stat.Ino}
		if seen[id] {
			return nil
		}
		seen[id] = true
		row.EstimatedBytes += getActualFileSize(full, st)
		if collectFiles && st.Size() > 0 {
			files = append(files, inventoryFile{full, st})
		}
		return nil
	})
	if err != nil {
		row.Complete = false
		row.Error = err.Error()
	}
	return row, files
}

func hashInventoryFile(ctx context.Context, root *os.Root, base string, file inventoryFile) (string, error) {
	rel, err := filepath.Rel(base, file.path)
	if err != nil {
		return "", err
	}
	f, err := root.OpenFile(rel, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return "", err
	}
	defer f.Close()
	before, err := f.Stat()
	if err != nil {
		return "", err
	}
	if !before.Mode().IsRegular() || !os.SameFile(before, file.info) || before.Size() != file.info.Size() || !before.ModTime().Equal(file.info.ModTime()) {
		return "", fmt.Errorf("file changed before hashing")
	}
	stat, ok := before.Sys().(*syscall.Stat_t)
	if !ok || stat.Flags&0x40000000 != 0 {
		return "", fmt.Errorf("file became a placeholder or identity is unavailable")
	}
	var filesystem syscall.Statfs_t
	if err := syscall.Fstatfs(int(f.Fd()), &filesystem); err != nil || filesystem.Flags&0x1000 == 0 {
		return "", fmt.Errorf("file is no longer on a known local filesystem")
	}
	h := sha256.New()
	buffer := make([]byte, 1024*1024)
	var total int64
	for {
		if err := ctx.Err(); err != nil {
			return "", err
		}
		n, e := f.Read(buffer)
		total += int64(n)
		if total > before.Size() {
			return "", fmt.Errorf("file grew during hashing")
		}
		if n > 0 {
			_, _ = h.Write(buffer[:n])
		}
		if e == io.EOF {
			break
		}
		if e != nil {
			return "", e
		}
	}
	after, err := f.Stat()
	if err != nil {
		return "", err
	}
	if after.Size() != before.Size() || !after.ModTime().Equal(before.ModTime()) {
		return "", fmt.Errorf("file changed during hashing")
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func inventoryDuplicates(ctx context.Context, path string, files []inventoryFile) ([][]string, error) {
	root, err := os.OpenRoot(path)
	if err != nil {
		return nil, err
	}
	defer root.Close()
	bySize := make(map[int64][]inventoryFile)
	for _, f := range files {
		bySize[f.info.Size()] = append(bySize[f.info.Size()], f)
	}
	var result [][]string
	var readBytes int64
	sizes := make([]int64, 0, len(bySize))
	for size := range bySize {
		sizes = append(sizes, size)
	}
	sort.Slice(sizes, func(i, j int) bool { return sizes[i] < sizes[j] })
	for _, size := range sizes {
		group := bySize[size]
		if len(group) < 2 {
			continue
		}
		byHash := make(map[string][]string)
		for _, file := range group {
			if readBytes+size > 8<<30 {
				return result, fmt.Errorf("hash budget reached; duplicate inspection incomplete")
			}
			digest, err := hashInventoryFile(ctx, root, path, file)
			if err != nil {
				return result, err
			}
			readBytes += size
			byHash[digest] = append(byHash[digest], file.path)
		}
		for _, matches := range byHash {
			if len(matches) > 1 {
				sort.Strings(matches)
				result = append(result, matches)
			}
		}
	}
	sort.Slice(result, func(i, j int) bool { return result[i][0] < result[j][0] })
	return result, nil
}

func inventoryRoots(home string) []string {
	var result []string
	for _, p := range []string{".cache", ".npm", ".cargo", ".rustup", ".lmstudio/models", ".ollama/models", ".local", "Library/Caches", "Library/Application Support", "Library/Developer", "Downloads", "Developer", "Projects", ".Trash"} {
		result = append(result, filepath.Join(home, p))
	}
	// Explicitly configured owner roots are read as data; tool hooks and
	// toolchain launchers are not executed to discover storage locations.
	for _, variable := range []string{"UV_CACHE_DIR", "PIP_CACHE_DIR", "HOMEBREW_CACHE", "CARGO_HOME", "RUSTUP_HOME", "HF_HOME", "HF_HUB_CACHE", "OLLAMA_MODELS", "VIRTUAL_ENV", "CONDA_PREFIX"} {
		if value := os.Getenv(variable); filepath.IsAbs(value) {
			result = append(result, filepath.Clean(value))
		}
	}
	for _, name := range []string{"DARWIN_USER_TEMP_DIR", "DARWIN_USER_CACHE_DIR"} {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		data, err := exec.CommandContext(ctx, "/usr/bin/getconf", name).Output()
		cancel()
		value := strings.TrimSpace(string(data))
		if err == nil && filepath.IsAbs(value) {
			result = append(result, filepath.Clean(value))
		}
	}
	result = append(result, "/Applications", "/Library/Frameworks/Python.framework/Versions", "/opt/homebrew/Cellar", "/usr/local", "/Users/Shared", "/System/Volumes/VM")
	seen := make(map[string]bool)
	unique := result[:0]
	for _, path := range result {
		if !seen[path] {
			seen[path] = true
			unique = append(unique, path)
		}
	}
	return unique
}

// Compare only completed explicit scans with identical measurement semantics
// and root sets. Never reuse these measurements as cleanup authorization.
func compareStorageInventory(previous storageInventory, current *storageInventory) {
	if !previous.Complete || !current.Complete || previous.Finished.After(current.Started) || previous.Schema != current.Schema || previous.Root != current.Root || len(previous.Rows) != len(current.Rows) {
		return
	}
	old := make(map[string]storageRow)
	for _, r := range previous.Rows {
		if !r.Complete {
			return
		}
		old[r.Path] = r
	}
	for _, r := range current.Rows {
		if previous, ok := old[r.Path]; !ok || r.Identity == "" || previous.Identity != r.Identity {
			return
		}
	}
	for i := range current.Rows {
		delta := current.Rows[i].EstimatedBytes - old[current.Rows[i].Path].EstimatedBytes
		current.Rows[i].Growth = &delta
	}
	current.Previous = &previous.Finished
}

func runStorageInventory(path string, overview, duplicates bool, output io.Writer) error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	r := storageInventory{Schema: inventorySchema, Root: path, Started: time.Now().UTC(), Complete: true, Rows: []storageRow{}, Notes: []string{
		"Inspection only. Estimates do not account exactly for shared APFS clones or snapshot retention; do not sum overlapping roots.",
		"Modified means last modification, not last use. Identical content does not prove either copy is unused.",
		"Network filesystems, symlinks, cloud placeholders and protected simulator storage are not traversed.",
		"Custom owner roots use exported cache settings. Tool hooks are not invoked; other configured roots can be inspected explicitly.",
	}}
	roots := []string{path}
	if overview {
		roots = inventoryRoots(os.Getenv("HOME"))
	} else if !duplicates {
		// Explicit inventory drills down one level, showing each bucket's date.
		entries, err := os.ReadDir(path)
		if err != nil {
			return err
		}
		roots = nil
		for _, entry := range entries {
			roots = append(roots, filepath.Join(path, entry.Name()))
		}
	}
	var files []inventoryFile
	for _, root := range roots {
		if _, err := os.Lstat(root); os.IsNotExist(err) {
			continue
		}
		probeCtx, probeCancel := context.WithTimeout(ctx, 3*time.Second)
		if duplicates {
			probeCancel()
			probeCtx = ctx
			probeCancel = func() {}
		}
		row, found := inspectStorage(probeCtx, root, duplicates)
		probeCancel()
		r.Rows = append(r.Rows, row)
		files = append(files, found...)
		r.Complete = r.Complete && row.Complete
		if ctx.Err() != nil {
			r.Complete = false
			r.Notes = append(r.Notes, "Overall scan deadline reached; remaining roots were not inspected")
			break
		}
	}
	if duplicates && r.Complete {
		matches, err := inventoryDuplicates(ctx, path, files)
		r.Duplicates = matches
		if err != nil {
			r.Complete = false
			r.Notes = append(r.Notes, err.Error())
		}
	}
	r.Finished = time.Now().UTC()
	sort.Slice(r.Rows, func(i, j int) bool { return r.Rows[i].EstimatedBytes > r.Rows[j].EstimatedBytes })
	if err := updateInventoryBaseline(&r); err != nil {
		r.Notes = append(r.Notes, "Local comparison baseline unavailable: "+err.Error())
	}
	encoder := json.NewEncoder(output)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(r); err != nil {
		return err
	}
	if !r.Complete {
		return fmt.Errorf("storage inspection incomplete; see per-root reasons")
	}
	return nil
}

// Model labels explain retention; they never authorize deletion.
func inventoryIsModel(path string) bool {
	p := strings.ToLower(path)
	return strings.Contains(p, "huggingface") || strings.Contains(p, ".ollama") || strings.Contains(p, ".lmstudio")
}

// One bounded baseline, protected against concurrent/stale publication.
func updateInventoryBaseline(current *storageInventory) error {
	cacheDir, err := getCacheDir()
	if err != nil {
		return err
	}
	lock, err := os.OpenFile(filepath.Join(cacheDir, "inventory.lock"), os.O_CREATE|os.O_RDWR|syscall.O_NOFOLLOW, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return err
	}
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	path := filepath.Join(cacheDir, "inventory.json")
	file, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err == nil {
		data, readErr := io.ReadAll(io.LimitReader(file, 1<<20))
		_ = file.Close()
		if readErr == nil && len(data) < 1<<20 {
			var previous storageInventory
			if json.Unmarshal(data, &previous) == nil {
				if previous.Started.After(current.Started) {
					return nil
				}
				compareStorageInventory(previous, current)
			}
		}
	}
	if !current.Complete {
		return nil
	}
	baseline := *current
	baseline.Duplicates = nil
	baseline.Notes = nil
	baseline.Previous = nil
	baseline.Rows = append([]storageRow(nil), current.Rows...)
	for i := range baseline.Rows {
		baseline.Rows[i].Growth = nil
	}
	data, err := json.Marshal(baseline)
	if err != nil {
		return err
	}
	if len(data) > 1<<20 {
		return fmt.Errorf("baseline size limit exceeded")
	}
	temp, err := os.CreateTemp(cacheDir, "inventory-*.tmp")
	if err != nil {
		return err
	}
	name := temp.Name()
	defer os.Remove(name)
	_, writeErr := temp.Write(data)
	closeErr := temp.Close()
	if writeErr != nil {
		return writeErr
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(name, path)
}
