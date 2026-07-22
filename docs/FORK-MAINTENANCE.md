# Xclipsen Omarchy Fork

This fork adds optional GitHub-release packages for Lab Backup and GSR Replay
without vendoring either project into Omarchy.

## Branches

- `quattro` mirrors `basecamp/omarchy:quattro` exactly.
- `xclipsen` is the default branch containing fork integrations.
- Feature branches start from `xclipsen` and merge through reviewed pull
  requests.

Update the mirror and merge it locally with:

```bash
git fetch upstream quattro
git switch quattro
git merge --ff-only upstream/quattro
git push origin quattro
git switch xclipsen
git merge quattro
```

Run `./test/all` before pushing the merge. Quattro is an alpha branch and must
not be merged into the fork automatically without passing tests.

## Package Releases

The Omarchy adapters install exact release assets from:

- `Xclipsen/gsr-replay`
- `Xclipsen/lab-backup` (private)

For every package update:

1. Tag and publish the source project.
2. Build the Arch package from that exact source archive.
3. Run project tests, `makepkg`, `namcap`, and package-content checks.
4. Upload the package and source archive to the GitHub release.
5. Replace the version, asset filename, and SHA-256 digest in the corresponding
   `omarchy-install-*` command.
6. Run `test/shell.d/xclipsen-integration-test.sh` and `./test/all`.

The private Lab Backup asset is downloaded through the user's authenticated
GitHub CLI. Authentication is never elevated.

## Data Boundaries

Lab Backup credentials and recovery files are never part of this repository or
an Arch package. GSR Replay configuration under `~/.config/gsr-replay` is
covered by Lab Backup. Replay videos are stored on the external Toshiba drive
through `~/Videos/replay` and are intentionally outside Restic coverage.

## Development Installation

Source work does not require changing the running desktop. Package and UI
acceptance tests should use a disposable Omarchy Quattro VM. Only enable
`omarchy channel dev` or install release packages on a live machine after an
explicit installation decision and a verified backup.
