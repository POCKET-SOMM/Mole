//go:build darwin

package main

// Retain the existing JSON/TUI contract without inferring deletion safety from
// a directory name or cache tag. Real deletion requires deliberate selection
// and the independent final path/identity guards.
func isCleanableDir(path string) bool {
	return false
}
