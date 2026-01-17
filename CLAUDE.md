# Claude Code Integration Guide

This document provides instructions for Claude Code to use the File Folder Cleanup Utility effectively.

## Overview

This utility helps users reorganize files from multiple source folders into a consolidated, organized structure. It operates in 4 phases:

1. **Analyze** - Scan source folders (read-only)
2. **Propose** - Define target structure (read-only)
3. **Generate** - Create migration scripts (writes 4 files)
4. **Execute** - Run the migration (moves files)

## Workflow for Claude Code

When a user asks to reorganize, consolidate, or clean up their files/folders, follow this workflow:

### Step 1: Gather Requirements

Ask the user:
1. Which folders should be consolidated? (e.g., Desktop, Downloads)
2. Where should files be moved to? (e.g., Documents)
3. Do they have a preferred organization scheme, or should you suggest one?

Example prompt:
```
I can help you reorganize your files. Please tell me:
1. Which folders do you want to consolidate? (e.g., ~/Desktop, ~/Downloads)
2. Where should everything be moved to? (e.g., ~/Documents)
3. Would you like me to suggest an organization structure, or do you have one in mind?
```

### Step 2: Analyze (Phase 1)

Run the analysis script to understand what files exist:

```bash
bash /path/to/file_folder_cleanup_util/src/analyze.sh ~/Desktop ~/Downloads
```

Present the summary to the user:
- Total files and size
- Large files (>100MB)
- Duplicate files found
- Filename conflicts

### Step 3: Propose Structure (Phase 2)

Either:
- Use a template: `--template personal` or `--template business` or `--template minimal`
- Auto-suggest based on file types: `--auto --analysis <analysis_file>`
- Let the user define custom structure

```bash
bash /path/to/file_folder_cleanup_util/src/propose.sh ~/Documents --template personal
```

Show the proposed structure to the user and confirm it looks correct.

### Step 4: Generate Migration Plan (Phase 3)

**This is the first step that writes files. Ask for permission once.**

```bash
bash /path/to/file_folder_cleanup_util/src/generate_plan.sh \
    --sources ~/Desktop,~/Downloads \
    --target ~/Documents \
    --output ~/Documents
```

This creates:
- `manifest_<timestamp>.txt` - Audit trail
- `execute_<timestamp>.sh` - Migration script
- `reversal_<timestamp>.sh` - Undo script
- `backup_<timestamp>.tar.gz` - Full backup

Tell the user these files were created.

### Step 5: Execute (Phase 4)

**This is the second and final permission request.**

First, run in dry-run mode to show what will happen:

```bash
bash /path/to/file_folder_cleanup_util/src/execute.sh execute_<timestamp>.sh --dry-run
```

Show the user the dry-run output. If they approve, execute for real:

```bash
bash /path/to/file_folder_cleanup_util/src/execute.sh execute_<timestamp>.sh --execute
```

### Step 6: Post-Migration Cleanup

After successful migration:
1. Verify files are in place
2. Remove empty source directories
3. Report final state to user

## Permission Minimization

**Critical**: This workflow is designed to minimize permission prompts:

| Phase | Permissions Needed |
|-------|-------------------|
| Analyze | 0 (read-only) |
| Propose | 0 (read-only) |
| Generate | 1 (write 4 files) |
| Execute | 1 (run script) |

**Total: 2 permission prompts**

Do NOT ask for permission for each file move. The batch script handles all moves in one execution.

## Handling Conflicts

When duplicates or conflicts are found:

1. **Identical files (same MD5)**: Inform user, recommend keeping one copy
2. **Same name, different content**: Suggest renaming with source suffix
3. **Destination exists**: Flag for manual review, do not overwrite

## Reversal

If the user wants to undo:

```bash
bash ~/Documents/reversal_<timestamp>.sh
```

Or restore from backup:

```bash
tar -xzf ~/Documents/backup_<timestamp>.tar.gz -C /
```

## Example Conversation

```
User: Help me clean up my Desktop and Downloads folders

Claude: I'll help you consolidate your files. Let me first analyze what's in those folders.

[Runs analyze.sh]

Claude: Here's what I found:
- 150 files in Desktop (200MB)
- 89 files in Downloads (1.2GB)
- 3 duplicate files detected
- 2 large files (>100MB): installer.dmg, video.mp4

Where would you like to move these files? I recommend ~/Documents with this structure:
- Documents/
- Media/Images, Media/Audio
- Archives/Software
- Projects/

Does this structure work for you?

User: Yes, let's do it

Claude: I'll now generate the migration plan. This will create:
- A manifest of all moves
- The migration script
- A reversal script
- A backup of your current files

[Runs generate_plan.sh - ONE permission prompt]

Claude: Plan generated! Here's a preview of what will happen:

[Runs execute.sh --dry-run]

150 files will be moved. Ready to execute?

User: Yes

[Runs execute.sh --execute - ONE permission prompt]

Claude: Done! Your files have been reorganized. Desktop and Downloads are now empty.
To undo, run: bash ~/Documents/reversal_2026-01-16.sh
```

## Environment Variables

These can be set before running scripts:

- `CLEANUP_LARGE_FILE_THRESHOLD` - Size in bytes (default: 104857600 = 100MB)
- `CLEANUP_DRY_RUN` - Set to 0 to skip dry-run (default: 1)
- `CLEANUP_CREATE_BACKUP` - Set to 0 to skip backup (default: 1)
- `CLEANUP_OUTPUT_DIR` - Where to write generated files

## Error Handling

If any phase fails:
1. Report the error clearly
2. Do not proceed to next phase
3. Suggest remediation (check permissions, disk space, etc.)
4. Remind user that no changes have been made yet (if before Execute)
