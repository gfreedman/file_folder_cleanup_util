# Sample Workflow: Consolidating Desktop and Downloads

This example walks through a complete file reorganization workflow, showing each phase and expected output.

## Scenario

You have files scattered across `~/Desktop` and `~/Downloads` that you want to consolidate into an organized structure in `~/Documents`.

## Phase 1: Analysis

Run the analysis to understand what files you're working with:

```bash
$ cd ~/file_folder_cleanup_util
$ bash src/analyze.sh ~/Desktop ~/Downloads

==============================================
PHASE 1: ANALYSIS
==============================================

[INFO] Scanning: /Users/you/Desktop
[OK] Found 87 files in Desktop
[INFO] Scanning: /Users/you/Downloads
[OK] Found 156 files in Downloads
[INFO] Checking for duplicate files (this may take a moment)...
  Progress: 243 / 243 files checked
[OK] Duplicate check complete

==============================================
ANALYSIS SUMMARY
==============================================

Files found:      243
Directories:      34
Total size:       1.8 GB

Large Files (>104857600 bytes):
  Found 2 large file(s):
  - 219.0 MB: SomeApp.dmg
  - 156.0 MB: video_project.mp4

Duplicate Files (identical content):
  Duplicate group 1 (MD5: a87ec359...):
    - recording.m4a
      /Users/you/Downloads/Audio/recording.m4a
    - recording.m4a
      /Users/you/Desktop/recording.m4a

Filename Conflicts (same name, different locations):
  "notes.txt" found in:
    - /Users/you/Desktop
    - /Users/you/Downloads/Documents

[OK] Analysis complete!
```

### Key Takeaways
- 243 files to organize
- 2 large files (software installer, video)
- 1 duplicate file (same audio file in two places)
- 1 filename conflict (different "notes.txt" files)

## Phase 2: Propose Structure

Choose a structure template or define your own:

```bash
$ bash src/propose.sh ~/Documents --template personal

==============================================
PHASE 2: PROPOSE STRUCTURE
==============================================

Target directory: /Users/you/Documents

[INFO] Loading template: personal
[OK] Structure is valid

Proposed Folder Structure:

├── Personal/
    ├── Medical/
    ├── Legal/
    ├── Identity/
    ├── Family/
    ├── Notes/
├── Home/
    ├── Maintenance/
    ├── Insurance/
    ├── Utilities/
├── Financial/
    ├── Tax/
    ├── Banking/
    ├── Insurance/
    ├── Investments/
    ├── Receipts/
├── Professional/
    ├── Resume/
    ├── References/
    ├── Certifications/
    ├── Projects/
├── Media/
    ├── Images/
        ├── Photos/
        ├── Screenshots/
        ├── Documents/
    ├── Audio/
    ├── Video/
├── Projects/
    ├── Active/
    ├── Archive/
├── Archives/
    ├── Software/
    ├── Fonts/
    ├── Data/
    ├── Old/
├── Sensitive/

[OK] Structure proposal complete!

If this structure looks good, proceed to Phase 3 (generate_plan.sh)
```

## Phase 3: Generate Migration Plan

Create the migration scripts and backup:

```bash
$ bash src/generate_plan.sh \
    --sources ~/Desktop,~/Downloads \
    --target ~/Documents \
    --output ~/Documents

==============================================
PHASE 3: GENERATE PLAN
==============================================

Configuration:
  Target:  /Users/you/Documents
  Sources: /Users/you/Desktop /Users/you/Downloads
  Output:  /Users/you/Documents

[INFO] Loading default mappings
[OK] Loaded 25 mapping rules
[INFO] Generating manifest: /Users/you/Documents/manifest_2026-01-16_14-30-00.txt
[INFO] Processing: /Users/you/Desktop
[INFO] Processing: /Users/you/Downloads
[OK] Manifest generated with 243 entries
[INFO] Generating execute script: /Users/you/Documents/execute_2026-01-16_14-30-00.sh
[OK] Execute script generated
[INFO] Generating reversal script: /Users/you/Documents/reversal_2026-01-16_14-30-00.sh
[OK] Reversal script generated
[INFO] Creating backup: /Users/you/Documents/backup_2026-01-16_14-30-00.tar.gz
[OK] Backup created: /Users/you/Documents/backup_2026-01-16_14-30-00.tar.gz (1.8 GB)

==============================================
GENERATION COMPLETE
==============================================

Generated files:
  Manifest:  /Users/you/Documents/manifest_2026-01-16_14-30-00.txt
  Execute:   /Users/you/Documents/execute_2026-01-16_14-30-00.sh
  Reversal:  /Users/you/Documents/reversal_2026-01-16_14-30-00.sh
  Backup:    /Users/you/Documents/backup_2026-01-16_14-30-00.tar.gz

Next steps:
  1. Review the manifest to ensure moves are correct
  2. Run execute script in dry-run mode: bash execute_2026-01-16_14-30-00.sh
  3. If satisfied, run with --execute: bash execute_2026-01-16_14-30-00.sh --execute
```

### What Was Created

1. **manifest_2026-01-16_14-30-00.txt** - Lists every file move:
   ```
   PLANNED|/Users/you/Desktop/photo.jpg|/Users/you/Documents/Media/Images/Photos/photo.jpg|
   PLANNED|/Users/you/Downloads/resume.pdf|/Users/you/Documents/Professional/Resume/resume.pdf|
   CONFLICT|/Users/you/Downloads/notes.txt|/Users/you/Documents/Personal/Notes/notes.txt|Conflicts with: /Users/you/Desktop/notes.txt
   ```

2. **execute_2026-01-16_14-30-00.sh** - The migration script

3. **reversal_2026-01-16_14-30-00.sh** - Undo script

4. **backup_2026-01-16_14-30-00.tar.gz** - Full backup

## Phase 4: Execute

First, run in dry-run mode (default):

```bash
$ bash src/execute.sh ~/Documents/execute_2026-01-16_14-30-00.sh

==============================================
PHASE 4: EXECUTE MIGRATION
==============================================

Execute script: /Users/you/Documents/execute_2026-01-16_14-30-00.sh
Mode: dry-run

[INFO] Running execute script...

*** DRY RUN MODE - No files will be moved ***
Run with --execute to perform actual moves

[DRY RUN] Would move: photo.jpg
[DRY RUN] Would move: resume.pdf
[DRY RUN] Would move: notes.txt
... (241 more files)

==============================================
EXECUTION COMPLETE
==============================================

This was a dry run. No files were moved.

To execute for real:
  bash execute_2026-01-16_14-30-00.sh --execute
```

If everything looks correct, execute for real:

```bash
$ bash src/execute.sh ~/Documents/execute_2026-01-16_14-30-00.sh --execute

==============================================
PHASE 4: EXECUTE MIGRATION
==============================================

Execute script: /Users/you/Documents/execute_2026-01-16_14-30-00.sh
Mode: execute

[INFO] Running pre-flight checks...
[OK] Backup verified: /Users/you/Documents/backup_2026-01-16_14-30-00.tar.gz
[INFO] Manifest contains 243 planned moves

[INFO] Running execute script...

*** EXECUTE MODE - Files will be moved ***

Are you sure? Type 'yes' to proceed: yes

MOVED: photo.jpg
MOVED: resume.pdf
MOVED: notes.txt
... (241 more files)

==============================================
EXECUTION COMPLETE
==============================================

Moved:   240 files
Skipped: 2 files
Failed:  1 files

Log file: execution_log_2026-01-16_14-32-15.txt

[INFO] Verifying execution...

Verification Results:
  Expected: 243 files
  Found:    240 files
  Missing:  3 files

[WARN] Some files were not moved. Check the log for details.

Clean up empty source directories? [y/N]: y
[INFO] Cleaned up: /Users/you/Desktop
[INFO] Cleaned up: /Users/you/Downloads
[OK] Cleanup complete

==============================================
EXECUTION COMPLETE
==============================================
```

## Reversal (If Needed)

If you need to undo the reorganization:

```bash
$ bash ~/Documents/reversal_2026-01-16_14-30-00.sh

==============================================
REVERSAL SCRIPT
==============================================

This will move files back to their original locations.
Are you sure? Type 'yes' to proceed: yes

Restored: photo.jpg
Restored: resume.pdf
Restored: notes.txt
...

Reversal complete!
```

Or restore from backup:

```bash
$ tar -xzf ~/Documents/backup_2026-01-16_14-30-00.tar.gz -C /
```

## Summary

| Phase | Action | Files Written | User Approvals |
|-------|--------|---------------|----------------|
| 1. Analyze | Scan folders | 0 | 0 |
| 2. Propose | Define structure | 0 | 0 |
| 3. Generate | Create scripts | 4 | 1 |
| 4. Execute | Move files | 1 (log) | 1 |
| **Total** | | **5** | **2** |

The entire reorganization requires only **2 user approvals**, making it efficient while maintaining safety through backups and dry-run previews.
