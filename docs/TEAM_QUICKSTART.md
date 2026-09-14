# Mole team CLI candidate

This is the independent POCKET-SOMM fork of Mole by Tw93 and contributors,
under GPL-3.0. It is a terminal tool, not the separately distributed Mole Mac app.
This candidate is for review and controlled testing until the release gates pass.

## Run locally

Choose `darwin-arm64` for Apple Silicon or `darwin-amd64` for Intel. The initial
compatibility target is macOS 14 or newer; native release certification is pending.
The corresponding source archive is supplied alongside the runtime archives.

1. Download the archive and `CHECKSUMS.sha256` from the agreed release location.
   Verify the archive hash against that trusted manifest with
   `shasum -a 256 <archive-name>.tar.gz` before extracting it.
2. Extract the archive into a folder you own and open Terminal in that folder.
3. Check its contents, then run:

   ```sh
   bash verify.sh
   ./mo-team --version
   ./mo-team --help
   ./mo-team clean --dry-run
   ./mo-team analyze --json /absolute/path/to/a/local/folder
   ```

Keep the whole folder together. Go, Homebrew, an installer and internet access
are not required. No global command, startup item or automatic updater is installed.
Run without sudo. Maintenance and deletion commands still need their documented
selection and confirmation; begin with inspection and previews.

These candidates are not Developer ID signed or notarized. Checksums establish
integrity against a trusted manifest, not the identity of an untrusted sender.
If macOS blocks execution, stop and report it for release preparation. Do not
disable Gatekeeper, clear quarantine, or change global security settings.

## Updating and removal

Download and verify each new version explicitly. Extract it into a separate folder;
retain the previous folder for rollback. Updates do not run automatically.
To remove a portable copy, move its extracted folder to Trash in Finder.
`./mo-team remove` prints that guidance without searching for other installations.

Configuration, operation logs and scan metadata use Mole's existing local paths
(`~/.config/mole`, `~/.cache/mole`, `~/Library/Logs/mole`). They may be shared with
another Mole installation and remain after removing this folder. Logs can contain
file and app names; they are not uploaded. Do not enable shell-completion installation
for a portable pilot; it assumes an installed `mo` or `mole` command.

Read `BEHAVIOR.md` for the exact supported cleanup and protection boundaries.
Report the version, architecture, macOS version and command when sharing feedback;
review logs for personal paths before sharing them yourself.
