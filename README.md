# File Folder Cleanup Utility

A safe, interactive tool for consolidating and reorganizing files across multiple folders. Designed to work with **Claude Code** to provide an intelligent, conversational approach to file organization.

## Philosophy

This tool follows three core principles:

1. **Safety First**: Every operation can be reversed. Backups are created before any changes.
2. **Transparency**: You see exactly what will happen before it happens (dry-run by default).
3. **Minimal Friction**: Only 2 approval prompts needed - one to generate scripts, one to execute.

## Features

- **Smart Analysis**: Scans folders to identify duplicates, large files, and naming conflicts
- **Flexible Structure Proposals**: Choose from templates or define your own organization scheme
- **Backup & Reversal**: Creates tar.gz backup and generates reversal scripts automatically
- **Dry-Run Mode**: Preview all changes before committing
- **Detailed Manifest**: Complete audit trail of every file move

## Requirements

- macOS (uses BSD versions of `find`, `stat`, `md5`, etc.)
- Bash 3.2+ (ships with macOS)
- Claude Code CLI (for the interactive workflow)

## Quick Start

### With Claude Code (Recommended)

Simply ask Claude Code to help you reorganize your files:

```
You: Help me consolidate my Desktop and Downloads folders into Documents
```

Claude will use this utility to:
1. Analyze your folders
2. Propose a structure
3. Generate the migration scripts
4. Execute with your approval

### Standalone Usage

```bash
# Clone the repo
git clone https://github.com/yourusername/file_folder_cleanup_util.git
cd file_folder_cleanup_util

# Run the full workflow
./cleanup.sh --source ~/Desktop ~/Downloads --target ~/Documents
```

## How It Works

The tool operates in 4 phases:

```
┌─────────────────────────────────────────────────────────┐
│  PHASE 1: ANALYZE (read-only)                          │
│  - Inventory all files in source folders                │
│  - Detect duplicates via MD5 checksums                  │
│  - Flag large files (>100MB by default)                 │
│  - Identify filename conflicts                          │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  PHASE 2: PROPOSE (read-only)                          │
│  - Suggest target folder structure                      │
│  - Map source files to destinations                     │
│  - Present options for conflict resolution              │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  PHASE 3: GENERATE (writes 4 files)                    │
│  - manifest.txt: Complete audit trail                   │
│  - execute.sh: The migration script                     │
│  - reversal.sh: Undo script                             │
│  - backup.tar.gz: Full backup of source folders         │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│  PHASE 4: EXECUTE                                       │
│  - Dry-run first (shows what would happen)              │
│  - Execute for real on confirmation                     │
│  - Verify file counts match                             │
│  - Clean up empty directories                           │
└─────────────────────────────────────────────────────────┘
```

## Configuration

### Structure Templates

The tool comes with pre-built templates in `/templates/`:

- `structure_personal.txt` - For personal file organization (Documents, Media, Financial, etc.)
- `structure_business.txt` - For work/business files
- `structure_minimal.txt` - Simple flat structure

You can also define custom structures interactively.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLEANUP_LARGE_FILE_THRESHOLD` | `104857600` (100MB) | Flag files larger than this |
| `CLEANUP_DRY_RUN` | `1` | Set to `0` to execute immediately |
| `CLEANUP_CREATE_BACKUP` | `1` | Set to `0` to skip backup |
| `CLEANUP_OUTPUT_DIR` | Current directory | Where to write manifest/scripts |

## Conflict Resolution

When duplicate filenames are found across source folders:

1. **Identical content** (same MD5): Keep one copy, log the duplicate
2. **Different content**: Keep both, append `_from_[source]` suffix
3. **Destination exists**: Skip and flag for manual review

## Reversal

To undo a reorganization:

```bash
# Restore from backup (recommended)
tar -xzf backup_YYYY-MM-DD.tar.gz -C /

# Or use the reversal script
bash reversal_YYYY-MM-DD.sh
```

## File Structure

```
file_folder_cleanup_util/
├── README.md                 # This file
├── LICENSE                   # MIT License
├── CONTRIBUTING.md           # Contribution guidelines
├── .gitignore
├── cleanup.sh                # Main entry point
│
├── src/
│   ├── utils.sh              # Shared utility functions
│   ├── analyze.sh            # Phase 1: Analysis
│   ├── propose.sh            # Phase 2: Structure proposal
│   ├── generate_plan.sh      # Phase 3: Script generation
│   └── execute.sh            # Phase 4: Execution
│
├── templates/
│   ├── structure_personal.txt
│   ├── structure_business.txt
│   └── structure_minimal.txt
│
├── examples/
│   └── sample_workflow.md    # Example walkthrough
│
└── claude_code/
    └── CLAUDE.md             # Claude Code instructions
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Credits

Built with Claude Code by Anthropic.
