# Contributing to File Folder Cleanup Utility

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in Issues
2. If not, create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - macOS version and Bash version (`bash --version`)

### Suggesting Features

1. Open an issue with the "enhancement" label
2. Describe the feature and its use case
3. Explain how it fits with the project's philosophy (safety, transparency, minimal friction)

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Test thoroughly on macOS
5. Ensure all scripts have extensive comments
6. Submit a pull request

## Code Style

### Bash Scripts

- Use extensive comments to explain logic (assume readers may not be Bash experts)
- Use meaningful variable names in UPPER_CASE for constants, lower_case for locals
- Quote all variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals (Bash-specific, more robust)
- Handle errors gracefully with meaningful messages

Example:
```bash
# ============================================================================
# FUNCTION: safe_move
# PURPOSE:  Move a file from source to destination with safety checks
# ARGS:     $1 = source path, $2 = destination path
# RETURNS:  0 on success, 1 on failure
# ============================================================================
safe_move() {
    local source_path="$1"    # The file we want to move
    local dest_path="$2"      # Where we want to move it to

    # Check if source exists before attempting move
    if [[ ! -e "$source_path" ]]; then
        log_error "Source does not exist: $source_path"
        return 1
    fi

    # ... rest of function
}
```

### Documentation

- Keep README.md up to date with any new features
- Add examples for new functionality
- Update CLAUDE.md if changing the Claude Code workflow

## Testing

Before submitting:

1. Test on a fresh directory with sample files
2. Verify dry-run mode works correctly
3. Test the reversal script
4. Check that backups are created properly

## Questions?

Open an issue with the "question" label.
