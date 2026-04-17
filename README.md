# File Folder Cleanup Utility

**[gfreedman.github.io/file_folder_cleanup_util](https://gfreedman.github.io/file_folder_cleanup_util/)**

A safe, interactive tool for consolidating and reorganizing files across multiple folders. Designed to work with **Claude Code** to provide a conversational approach to file organization.

## Philosophy

1. **Safety first** — Every operation can be reversed. Backups are created before any changes.
2. **Transparency** — You see exactly what will happen before it happens (dry-run by default).
3. **Minimal friction** — 2 approval prompts total: one to generate scripts, one to execute.

## Features

- Scans folders to identify duplicates (SHA-256), large files, and naming conflicts
- Choose from built-in templates or define your own folder structure
- Creates a `.tar.gz` backup and a reversal script before any file moves
- Dry-run preview of every planned move
- Complete manifest audit trail

## Requirements

- macOS (uses BSD `find`, `stat`, `shasum`)
- Bash 4+ (macOS ships with 3.2 — see Setup below)
- Claude Code CLI (for the recommended workflow)

## Setup

### With Claude Code

No manual setup needed. Claude Code detects your Bash version automatically and runs `brew install bash` if an upgrade is required — before doing anything else.

### Standalone

Install Bash 4+ once:

```bash
brew install bash
```

If Homebrew is not installed, get it at [brew.sh](https://brew.sh).

## Quick Start

### With Claude Code (recommended)

Clone the repo, open Claude Code in the folder, and describe what you want:

```
You: Help me consolidate my Desktop and Downloads into Documents
```

Claude handles the four phases, asks for approval twice, and reports when done.

**Output directory**: Claude writes generated files to `~/tmp-cleanup/` by default — outside your source directories and outside any cloud-synced folder (iCloud Drive, Dropbox, etc.). The backup tarball contains all your source files and should not be uploaded to cloud storage.

### Standalone

```bash
# Phase 1 — scan (read-only)
bash src/analyze.sh ~/Desktop ~/Downloads

# Phase 2 — propose a structure (read-only)
bash src/propose.sh ~/Documents --template personal

# Phase 3 — generate scripts + backup (1st approval)
bash src/generate_plan.sh \
    --sources ~/Desktop,~/Downloads \
    --target ~/Documents \
    --output ~/tmp-cleanup

# Phase 4 — preview, then execute (2nd approval)
bash src/execute.sh ~/tmp-cleanup/execute_<timestamp>.sh --dry-run
bash src/execute.sh ~/tmp-cleanup/execute_<timestamp>.sh --execute
```

**Important**: Set `--output` to a directory that is not inside any source directory and not inside a cloud-synced folder. The tool will exit with an error if the output path is inside a source directory.

## How It Works

```
PHASE 1: ANALYZE (read-only)
  Inventory files · Detect duplicates via SHA-256 · Flag large files · Find conflicts
                          ↓
PHASE 2: PROPOSE (read-only)
  Suggest target structure · Map files to destinations · Surface conflict options
                          ↓
PHASE 3: GENERATE (writes 4 files — 1st approval)
  manifest.txt    — complete audit trail of every planned move
  execute.sh      — the migration script
  reversal.sh     — one-command undo
  backup.tar.gz   — full backup of source folders, created before any move
                          ↓
PHASE 4: EXECUTE (2nd approval)
  Dry-run preview → confirm → move files → verify counts → clean up empty dirs
```

## Configuration

### Structure Templates

Built-in templates in `templates/`:

- `structure_personal.txt` — Documents, Media, Financial, Projects, Archives
- `structure_business.txt` — Clients, Contracts, Invoices, Reports, Marketing
- `structure_minimal.txt` — Files, Media, Archive

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLEANUP_LARGE_FILE_THRESHOLD` | `104857600` (100 MB) | Flag files larger than this |
| `CLEANUP_DRY_RUN` | `1` | Set to `0` to skip dry-run step |
| `CLEANUP_CREATE_BACKUP` | `1` | Set to `0` to skip backup (not recommended) |
| `CLEANUP_OUTPUT_DIR` | Current directory | Where to write manifest, scripts, and backup |

## Conflict Resolution

| Situation | Behavior |
|-----------|----------|
| Identical content (same SHA-256 hash) | One copy kept, duplicate logged in manifest |
| Same name, different content | Both kept; second gets `_from_[source]` suffix |
| Destination already exists | Incoming file skipped, flagged in manifest for manual review |

The tool never silently overwrites a file.

## Reversal

Two independent recovery paths are generated before any file moves:

```bash
# Option A: reversal script (moves every file back to its original path)
bash ~/tmp-cleanup/reversal_<timestamp>.sh

# Option B: full restore from backup archive
tar -xzf ~/tmp-cleanup/backup_<timestamp>.tar.gz -C /
```

## Known Limitations

- **Symlinks are skipped.** All phases use `find -type f`. Symlinks in source directories are not moved. Move them manually after migration if needed.
- **macOS only.** Uses BSD `stat`, `shasum`, and `find` syntax. Not compatible with Linux GNU coreutils.
- **Bash 4+ required.** macOS ships Bash 3.2. Claude Code handles this automatically; standalone users run `brew install bash` once.

## File Structure

```
file_folder_cleanup_util/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── CLAUDE.md                 # Claude Code instructions
├── src/
│   ├── utils.sh              # Shared utilities, validation, logging
│   ├── analyze.sh            # Phase 1: read-only scan
│   ├── propose.sh            # Phase 2: structure proposal
│   ├── generate_plan.sh      # Phase 3: script + backup generation
│   └── execute.sh            # Phase 4: execution wrapper
├── templates/
│   ├── structure_personal.txt
│   ├── structure_business.txt
│   └── structure_minimal.txt
└── docs/
    └── index.html            # GitHub Pages site
```

## License

MIT — see [LICENSE](LICENSE).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).
