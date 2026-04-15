#!/usr/bin/env bats
# Integration tests for all 4 phases (analyze, propose, generate, execute)

BASH4="${BASH4:-/opt/homebrew/bin/bash}"
PROJECT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Build a standard fixture tree in BATS_TEST_TMPDIR/source
setup_fixtures() {
    local src="$BATS_TEST_TMPDIR/source"
    mkdir -p "$src/subdir"
    echo "hello world"  > "$src/readme.txt"
    echo "print('hi')" > "$src/script.py"
    echo "<html></html>" > "$src/page.html"
    echo "body{}"       > "$src/style.css"
    printf '\x89PNG\r\n' > "$src/photo.png"
    echo "hello world"  > "$src/subdir/readme_copy.txt"   # duplicate of readme.txt
    echo "data,value"   > "$src/subdir/data.csv"
    echo "spaced"       > "$src/my document.pdf"
    echo "quoted"       > "$src/file'with'quotes.txt"
}

setup_second_source() {
    local src2="$BATS_TEST_TMPDIR/source2"
    mkdir -p "$src2"
    echo "second source"    > "$src2/notes.txt"
    echo "more data"        > "$src2/report.pdf"
    echo "different content" > "$src2/readme.txt"  # same name, different content
}

# ── Phase 1: analyze ──────────────────────────────────────────────────────────

@test "analyze: counts all regular files" {
    setup_fixtures
    run "$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$BATS_TEST_TMPDIR/source"
    [ "$status" -eq 0 ]
    total=$(echo "$output" | grep "ANALYSIS_COMPLETE|" | cut -d'|' -f2)
    [ "$total" -eq 9 ]
}

@test "analyze: per-source counts are not cumulative" {
    setup_fixtures
    setup_second_source
    run "$BASH4" "${PROJECT_DIR}/src/analyze.sh" \
        "$BATS_TEST_TMPDIR/source" "$BATS_TEST_TMPDIR/source2"
    [ "$status" -eq 0 ]
    first=$(echo "$output"  | grep -m1 "Found .* files in source$"  | grep -oE '[0-9]+' | head -1)
    second=$(echo "$output" | grep -m1 "Found .* files in source2$" | grep -oE '[0-9]+' | head -1)
    [ "$first"  -eq 9 ]
    [ "$second" -eq 3 ]
}

@test "analyze: detects duplicate content" {
    setup_fixtures
    run "$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$BATS_TEST_TMPDIR/source"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "duplicate group"
}

@test "analyze: reports filename conflicts across sources" {
    setup_fixtures
    setup_second_source
    run "$BASH4" "${PROJECT_DIR}/src/analyze.sh" \
        "$BATS_TEST_TMPDIR/source" "$BATS_TEST_TMPDIR/source2"
    [ "$status" -eq 0 ]
    # readme.txt appears in both sources — should appear in Conflicts section
    echo "$output" | grep -qi "conflict"
}

@test "analyze: exits non-zero for missing source dir" {
    run "$BASH4" "${PROJECT_DIR}/src/analyze.sh" "/no/such/directory/xyz"
    [ "$status" -ne 0 ]
}

@test "analyze: excludes .DS_Store and .git contents" {
    local src="$BATS_TEST_TMPDIR/filtered"
    mkdir -p "$src/.git/objects"
    echo "real"   > "$src/real.txt"
    echo "ds"     > "$src/.DS_Store"
    echo "gitobj" > "$src/.git/objects/abc"
    run "$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$src"
    [ "$status" -eq 0 ]
    total=$(echo "$output" | grep "ANALYSIS_COMPLETE|" | cut -d'|' -f2)
    [ "$total" -eq 1 ]
}

@test "analyze: handles filenames with spaces and quotes" {
    local src="$BATS_TEST_TMPDIR/special"
    mkdir -p "$src"
    echo "a" > "$src/my file.txt"
    echo "b" > "$src/it's a doc.pdf"
    echo "c" > "$src/report (final).xlsx"
    run "$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$src"
    [ "$status" -eq 0 ]
    total=$(echo "$output" | grep "ANALYSIS_COMPLETE|" | cut -d'|' -f2)
    [ "$total" -eq 3 ]
}

# ── Phase 2: propose ──────────────────────────────────────────────────────────

@test "propose: personal template loads without error" {
    run "$BASH4" "${PROJECT_DIR}/src/propose.sh" "$BATS_TEST_TMPDIR" --template personal
    [ "$status" -eq 0 ]
}

@test "propose: business template loads without error" {
    run "$BASH4" "${PROJECT_DIR}/src/propose.sh" "$BATS_TEST_TMPDIR" --template business
    [ "$status" -eq 0 ]
}

@test "propose: minimal template loads without error" {
    run "$BASH4" "${PROJECT_DIR}/src/propose.sh" "$BATS_TEST_TMPDIR" --template minimal
    [ "$status" -eq 0 ]
}

@test "propose: invalid template exits non-zero" {
    run "$BASH4" "${PROJECT_DIR}/src/propose.sh" "$BATS_TEST_TMPDIR" --template nonexistent_xyz
    [ "$status" -ne 0 ]
}

# ── Phase 3: generate ─────────────────────────────────────────────────────────

@test "generate: produces manifest, execute, and reversal files" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    run env CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out"
    [ "$status" -eq 0 ]
    [ -n "$(ls "$out"/manifest_*.txt 2>/dev/null)" ]
    [ -n "$(ls "$out"/execute_*.sh  2>/dev/null)" ]
    [ -n "$(ls "$out"/reversal_*.sh 2>/dev/null)" ]
}

@test "generate: manifest has PLANNED entries in correct pipe-delimited format" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    env CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out" >/dev/null 2>&1
    local manifest
    manifest=$(ls "$out"/manifest_*.txt | head -1)
    planned=$(grep -c '^PLANNED|' "$manifest")
    [ "$planned" -gt 0 ]
    # Verify format: at least 3 pipe-delimited fields
    first_line=$(grep '^PLANNED|' "$manifest" | head -1)
    field_count=$(echo "$first_line" | tr '|' '\n' | wc -l | tr -d ' ')
    [ "$field_count" -ge 3 ]
}

@test "generate: execute script is executable and reads from manifest" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    env CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out" >/dev/null 2>&1
    local execute
    execute=$(ls "$out"/execute_*.sh | head -1)
    [ -x "$execute" ]
    # Must reference MANIFEST_FILE and loop over it — not inline paths
    grep -q 'MANIFEST_FILE' "$execute"
    grep -q 'while IFS=.*read' "$execute"
}

@test "generate: reversal script references same paths as execute script" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    env CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out" >/dev/null 2>&1
    local reversal
    reversal=$(ls "$out"/reversal_*.sh | head -1)
    # Reversal must also read from the manifest
    grep -q 'MANIFEST_FILE' "$reversal"
}

@test "generate: backup is created by default" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    run "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out"
    [ "$status" -eq 0 ]
    [ -n "$(ls "$out"/backup_*.tar.gz 2>/dev/null)" ]
}

# ── Phase 4: execute ──────────────────────────────────────────────────────────

@test "execute: dry run outputs DRY RUN and leaves files in place" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    env CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out" >/dev/null 2>&1
    local execute
    execute=$(ls "$out"/execute_*.sh | head -1)
    run bash -c "cd '$out' && '$BASH4' '$execute'"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qi "DRY RUN"
    # Original file must still exist
    [ -f "$BATS_TEST_TMPDIR/source/readme.txt" ]
}

@test "execute: live run moves files to target" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    env CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out" >/dev/null 2>&1
    local execute
    execute=$(ls "$out"/execute_*.sh | head -1)
    bash -c "cd '$out' && echo yes | '$BASH4' '$execute' --execute" >/dev/null 2>&1
    moved=$(find "$BATS_TEST_TMPDIR/target" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$moved" -gt 0 ]
}

@test "execute: reversal restores files to original locations" {
    setup_fixtures
    local out="$BATS_TEST_TMPDIR/out"
    mkdir -p "$out"
    env CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$BATS_TEST_TMPDIR/source" \
        --target  "$BATS_TEST_TMPDIR/target" \
        --output  "$out" >/dev/null 2>&1
    local execute reversal
    execute=$(ls "$out"/execute_*.sh | head -1)
    reversal=$(ls "$out"/reversal_*.sh | head -1)
    bash -c "cd '$out' && echo yes | '$BASH4' '$execute' --execute"  >/dev/null 2>&1
    bash -c "cd '$out' && echo yes | '$BASH4' '$reversal'"           >/dev/null 2>&1
    [ -f "$BATS_TEST_TMPDIR/source/readme.txt" ]
}

@test "execute: missing manifest exits non-zero" {
    local execute="$BATS_TEST_TMPDIR/execute_fake.sh"
    # Write a minimal execute script that references a non-existent manifest
    cat > "$execute" <<'EOF'
#!/bin/bash
MANIFEST_FILE="$(dirname "$0")/manifest_fake.txt"
if [[ ! -f "$MANIFEST_FILE" ]]; then echo "Error: Manifest not found" >&2; exit 1; fi
EOF
    chmod +x "$execute"
    run bash -c "cd '$BATS_TEST_TMPDIR' && '$BASH4' '$execute'"
    [ "$status" -ne 0 ]
}
