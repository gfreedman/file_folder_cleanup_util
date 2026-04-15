#!/usr/bin/env bats
# Unit tests for src/utils.sh

BASH4="${BASH4:-/opt/homebrew/bin/bash}"
PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Source utils in a subshell helper
run_utils() {
    "$BASH4" -c "source '${PROJECT_DIR}/src/utils.sh'; $1"
}

# ── format_bytes ──────────────────────────────────────────────────────────────

@test "format_bytes: bytes under 1 KB" {
    run run_utils "format_bytes 500"
    [ "$status" -eq 0 ]
    [ "$output" = "500 bytes" ]
}

@test "format_bytes: exactly 1 MB" {
    run run_utils "format_bytes 1048576"
    [ "$status" -eq 0 ]
    [ "$output" = "1 MB" ]
}

@test "format_bytes: exactly 1 GB" {
    run run_utils "format_bytes 1073741824"
    [ "$status" -eq 0 ]
    [ "$output" = "1 GB" ]
}

@test "format_bytes: KB boundary" {
    run run_utils "format_bytes 2048"
    [ "$status" -eq 0 ]
    [ "$output" = "2 KB" ]
}

# ── get_file_hash ─────────────────────────────────────────────────────────────

@test "get_file_hash: returns correct SHA-256" {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'test' > "$tmpfile"
    run run_utils "get_file_hash '$tmpfile'"
    rm -f "$tmpfile"
    [ "$status" -eq 0 ]
    # SHA-256("test") without newline
    [ "$output" = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08" ]
}

@test "get_file_hash: same content same hash" {
    local f1 f2
    f1=$(mktemp); f2=$(mktemp)
    echo "duplicate" > "$f1"
    echo "duplicate" > "$f2"
    run "$BASH4" -c "
        source '${PROJECT_DIR}/src/utils.sh'
        h1=\$(get_file_hash '$f1')
        h2=\$(get_file_hash '$f2')
        [[ \"\$h1\" == \"\$h2\" ]]
    "
    rm -f "$f1" "$f2"
    [ "$status" -eq 0 ]
}

# ── validate_directory ────────────────────────────────────────────────────────

@test "validate_directory: accepts existing directory" {
    run run_utils "validate_directory '/tmp'"
    [ "$status" -eq 0 ]
}

@test "validate_directory: rejects non-existent path" {
    run run_utils "validate_directory '/no/such/path/xyz'"
    [ "$status" -ne 0 ]
}

@test "validate_directory: rejects a file path" {
    local tmpfile
    tmpfile=$(mktemp)
    run run_utils "validate_directory '$tmpfile'"
    rm -f "$tmpfile"
    [ "$status" -ne 0 ]
}

# ── validate_not_system_dir ───────────────────────────────────────────────────

@test "validate_not_system_dir: blocks /System" {
    run run_utils "validate_not_system_dir '/System'"
    [ "$status" -ne 0 ]
}

@test "validate_not_system_dir: blocks /Library subtree" {
    run run_utils "validate_not_system_dir '/Library/Preferences'"
    [ "$status" -ne 0 ]
}

@test "validate_not_system_dir: blocks /usr" {
    run run_utils "validate_not_system_dir '/usr'"
    [ "$status" -ne 0 ]
}

@test "validate_not_system_dir: allows ~/Documents" {
    run run_utils "validate_not_system_dir '$HOME/Documents'"
    [ "$status" -eq 0 ]
}

# ── safe_move (dry run) ───────────────────────────────────────────────────────

@test "safe_move: dry run does not move file" {
    local src dest
    src=$(mktemp)
    dest=$(mktemp).dest
    echo "content" > "$src"
    run "$BASH4" -c "
        source '${PROJECT_DIR}/src/utils.sh'
        DRY_RUN=1
        safe_move '$src' '$dest'
    "
    # Source must still exist; dest must not
    [ -f "$src" ]
    [ ! -f "$dest" ]
    rm -f "$src"
}

@test "safe_move: live run moves file" {
    local tmpdir src dest
    tmpdir=$(mktemp -d)
    src="$tmpdir/source.txt"
    dest="$tmpdir/subdir/dest.txt"
    echo "content" > "$src"
    run "$BASH4" -c "
        source '${PROJECT_DIR}/src/utils.sh'
        DRY_RUN=0
        safe_move '$src' '$dest'
    "
    [ "$status" -eq 0 ]
    [ ! -f "$src" ]
    [ -f "$dest" ]
    rm -rf "$tmpdir"
}

@test "safe_move: skips when destination already exists" {
    local tmpdir src dest
    tmpdir=$(mktemp -d)
    src="$tmpdir/source.txt"
    dest="$tmpdir/dest.txt"
    echo "original" > "$src"
    echo "existing" > "$dest"
    run "$BASH4" -c "
        source '${PROJECT_DIR}/src/utils.sh'
        DRY_RUN=0
        safe_move '$src' '$dest'
    "
    # Source should still exist (skipped, not overwritten)
    [ -f "$src" ]
    [ "$(cat "$dest")" = "existing" ]
    rm -rf "$tmpdir"
}

# ── remove_empty_dirs ─────────────────────────────────────────────────────────

@test "remove_empty_dirs: removes empty dirs, leaves non-empty" {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/empty1" "$tmpdir/empty2" "$tmpdir/nonempty"
    echo "file" > "$tmpdir/nonempty/file.txt"
    run "$BASH4" -c "
        source '${PROJECT_DIR}/src/utils.sh'
        DRY_RUN=0
        remove_empty_dirs '$tmpdir'
    "
    [ ! -d "$tmpdir/empty1" ]
    [ ! -d "$tmpdir/empty2" ]
    [ -d "$tmpdir/nonempty" ]
    rm -rf "$tmpdir"
}

# ── create_backup ─────────────────────────────────────────────────────────────

@test "create_backup: produces a .tar.gz containing source files" {
    local tmpdir src out
    tmpdir=$(mktemp -d)
    src="$tmpdir/source"
    out="$tmpdir/out"
    mkdir -p "$src" "$out"
    echo "data" > "$src/file.txt"
    run "$BASH4" -c "
        source '${PROJECT_DIR}/src/utils.sh'
        DRY_RUN=0
        OUTPUT_DIR='$out'
        create_backup 'backup_test' '$src'
    "
    [ "$status" -eq 0 ]
    [ -f "$out/backup_test.tar.gz" ]
    rm -rf "$tmpdir"
}
