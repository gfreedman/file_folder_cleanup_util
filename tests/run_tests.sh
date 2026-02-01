#!/usr/bin/env bash
# ============================================================================
# FILE:        run_tests.sh
# PURPOSE:     Integration tests for the file folder cleanup utility
# DESCRIPTION: Creates temp directories with known file structures, runs each
#              phase, and verifies correctness. Self-contained — no external
#              test framework required.
#
# USAGE:       bash tests/run_tests.sh
# NOTE:        Requires bash 4+. On macOS, install via: brew install bash
# ============================================================================

# Re-exec under bash 4+ if the current shell is too old
if ((BASH_VERSINFO[0] < 4)); then
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$candidate" ]] && "$candidate" -c '((BASH_VERSINFO[0]>=4))' 2>/dev/null; then
            exec "$candidate" "$0" "$@"
        fi
    done
    echo "Error: Bash 4+ required. macOS ships 3.2; install via: brew install bash" >&2
    exit 1
fi

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Path to bash 4+ for running the scripts under test
BASH4="$BASH"

# ============================================================================
# TEST FRAMEWORK
# ============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""
TEST_TMPDIR=""

# Colors
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

# Create an isolated temp dir for one test, tear it down on exit
setup_test()
{
    CURRENT_TEST="$1"
    TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/cleanup_test_XXXXXX")
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${BOLD}TEST: $CURRENT_TEST${NC}"
}

teardown_test()
{
    if [[ -n "$TEST_TMPDIR" && -d "$TEST_TMPDIR" ]]
    then
        rm -rf "$TEST_TMPDIR"
    fi
    TEST_TMPDIR=""
}

pass()
{
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC}: $CURRENT_TEST"
}

fail()
{
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "  ${RED}FAIL${NC}: $CURRENT_TEST — $1"
}

assert_file_exists()
{
    if [[ ! -f "$1" ]]; then
        fail "Expected file to exist: $1"
        return 1
    fi
    return 0
}

assert_file_not_exists()
{
    if [[ -f "$1" ]]; then
        fail "Expected file NOT to exist: $1"
        return 1
    fi
    return 0
}

assert_dir_exists()
{
    if [[ ! -d "$1" ]]; then
        fail "Expected directory to exist: $1"
        return 1
    fi
    return 0
}

assert_contains()
{
    local file="$1"
    local pattern="$2"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        fail "Expected '$pattern' in $file"
        return 1
    fi
    return 0
}

assert_equals()
{
    if [[ "$1" != "$2" ]]; then
        fail "Expected '$2' but got '$1'"
        return 1
    fi
    return 0
}

# ============================================================================
# FIXTURE HELPERS
# ============================================================================

# Create a standard set of test files in $TEST_TMPDIR/source
create_standard_fixtures()
{
    local src="$TEST_TMPDIR/source"
    mkdir -p "$src/subdir"

    echo "hello world" > "$src/readme.txt"
    echo "print('hi')" > "$src/script.py"
    echo "<html></html>" > "$src/page.html"
    echo "body{}" > "$src/style.css"

    # Create a binary-like file for image testing
    printf '\x89PNG\r\n' > "$src/photo.png"

    # Duplicate file (same content as readme.txt)
    echo "hello world" > "$src/subdir/readme_copy.txt"

    # File in subdirectory
    echo "data,value" > "$src/subdir/data.csv"

    # File with spaces in name
    echo "spaced" > "$src/my document.pdf"

    # File with quotes in name
    echo "quoted" > "$src/file'with'quotes.txt"
}

# Create a second source directory for multi-source tests
create_second_source()
{
    local src2="$TEST_TMPDIR/source2"
    mkdir -p "$src2"

    echo "second source" > "$src2/notes.txt"
    echo "more data" > "$src2/report.pdf"

    # File that conflicts with source1
    echo "different content" > "$src2/readme.txt"
}

# ============================================================================
# TESTS
# ============================================================================

test_analyze_basic()
{
    setup_test "analyze: basic file counting"
    create_standard_fixtures

    local output
    output=$("$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$TEST_TMPDIR/source" 2>&1)
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        fail "analyze.sh exited with code $rc"
        teardown_test
        return
    fi

    # Check that the completion line reports the right total
    if echo "$output" | grep -q "ANALYSIS_COMPLETE|"; then
        local total
        total=$(echo "$output" | grep "ANALYSIS_COMPLETE|" | cut -d'|' -f2)
        # 9 files: readme.txt, script.py, page.html, style.css,
        # photo.png, readme_copy.txt, data.csv, my document.pdf, file'with'quotes.txt
        if [[ "$total" -eq 9 ]]; then
            pass
        else
            fail "Expected 9 files, got $total"
        fi
    else
        fail "No ANALYSIS_COMPLETE line in output"
    fi

    teardown_test
}

test_analyze_per_directory_count()
{
    setup_test "analyze: per-directory count not cumulative (bug #12 fix)"
    create_standard_fixtures
    create_second_source

    local output
    output=$("$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$TEST_TMPDIR/source" "$TEST_TMPDIR/source2" 2>&1)

    # The log_success lines should show per-directory counts, not cumulative
    local first_count
    first_count=$(echo "$output" | grep -m1 "Found .* files in source$" | grep -oE '[0-9]+' | head -1)
    local second_count
    second_count=$(echo "$output" | grep -m1 "Found .* files in source2$" | grep -oE '[0-9]+' | head -1)

    # source has 9 files, source2 has 3
    if [[ "$first_count" -eq 9 && "$second_count" -eq 3 ]]; then
        pass
    else
        fail "Expected source=9, source2=3; got source=$first_count, source2=$second_count"
    fi

    teardown_test
}

test_analyze_duplicate_detection()
{
    setup_test "analyze: duplicate detection finds identical files"
    create_standard_fixtures

    local output
    output=$("$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$TEST_TMPDIR/source" 2>&1)

    if echo "$output" | grep -qi "duplicate group"; then
        pass
    else
        fail "Expected duplicate detection to find readme.txt / readme_copy.txt"
    fi

    teardown_test
}

test_analyze_filename_conflicts()
{
    setup_test "analyze: filename conflicts across sources"
    create_standard_fixtures
    create_second_source

    local output
    output=$("$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$TEST_TMPDIR/source" "$TEST_TMPDIR/source2" 2>&1)

    if echo "$output" | grep -q "readme.txt"; then
        # At minimum it should mention conflicts section
        if echo "$output" | grep -qi "conflict"; then
            pass
        else
            fail "Expected filename conflict section in output"
        fi
    else
        fail "Expected readme.txt mentioned in output"
    fi

    teardown_test
}

test_propose_template()
{
    setup_test "propose: load personal template"

    local output
    output=$("$BASH4" "${PROJECT_DIR}/src/propose.sh" "$TEST_TMPDIR" --template personal 2>&1)
    local rc=$?

    if [[ $rc -ne 0 ]]; then
        fail "propose.sh exited with code $rc"
        teardown_test
        return
    fi

    if echo "$output" | grep -qi "structure"; then
        pass
    else
        fail "Expected structure output from propose"
    fi

    teardown_test
}

test_generate_plan_creates_files()
{
    setup_test "generate: creates manifest, execute, and reversal scripts"
    create_standard_fixtures

    local out="$TEST_TMPDIR/output"
    mkdir -p "$out"

    CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$TEST_TMPDIR/source" \
        --target "$TEST_TMPDIR/target" \
        --output "$out" 2>&1 >/dev/null

    # Find generated files
    local manifest execute reversal
    manifest=$(ls "$out"/manifest_*.txt 2>/dev/null | head -1)
    execute=$(ls "$out"/execute_*.sh 2>/dev/null | head -1)
    reversal=$(ls "$out"/reversal_*.sh 2>/dev/null | head -1)

    if [[ -f "$manifest" && -f "$execute" && -f "$reversal" ]]; then
        pass
    else
        fail "Missing generated files: manifest=$manifest execute=$execute reversal=$reversal"
    fi

    teardown_test
}

test_generate_manifest_format()
{
    setup_test "generate: manifest contains PLANNED entries with correct format"
    create_standard_fixtures

    local out="$TEST_TMPDIR/output"
    mkdir -p "$out"

    CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$TEST_TMPDIR/source" \
        --target "$TEST_TMPDIR/target" \
        --output "$out" 2>&1 >/dev/null

    local manifest
    manifest=$(ls "$out"/manifest_*.txt 2>/dev/null | head -1)

    if [[ ! -f "$manifest" ]]; then
        fail "No manifest file generated"
        teardown_test
        return
    fi

    local planned_count
    planned_count=$(grep -c '^PLANNED|' "$manifest" 2>/dev/null || echo "0")

    if [[ "$planned_count" -gt 0 ]]; then
        # Verify format: STATUS|SOURCE|DEST|NOTES
        local first_planned
        first_planned=$(grep '^PLANNED|' "$manifest" | head -1)
        local field_count
        field_count=$(echo "$first_planned" | tr '|' '\n' | wc -l | tr -d ' ')
        if [[ "$field_count" -ge 3 ]]; then
            pass
        else
            fail "Manifest entry has $field_count fields, expected >= 3"
        fi
    else
        fail "No PLANNED entries in manifest"
    fi

    teardown_test
}

test_generate_no_injection()
{
    setup_test "generate: execute script reads manifest, no inlined paths"
    create_standard_fixtures

    local out="$TEST_TMPDIR/output"
    mkdir -p "$out"

    CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$TEST_TMPDIR/source" \
        --target "$TEST_TMPDIR/target" \
        --output "$out" 2>&1 >/dev/null

    local execute
    execute=$(ls "$out"/execute_*.sh 2>/dev/null | head -1)

    if [[ ! -f "$execute" ]]; then
        fail "No execute script generated"
        teardown_test
        return
    fi

    # The execute script should reference MANIFEST_FILE and read from it,
    # not contain inlined mv commands with literal paths
    if grep -q 'MANIFEST_FILE' "$execute" && grep -q 'while IFS=.*read' "$execute"; then
        pass
    else
        fail "Execute script should read from manifest, not inline paths"
    fi

    teardown_test
}

test_execute_dry_run()
{
    setup_test "execute: dry run does not move files"
    create_standard_fixtures

    local out="$TEST_TMPDIR/output"
    mkdir -p "$out"

    CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$TEST_TMPDIR/source" \
        --target "$TEST_TMPDIR/target" \
        --output "$out" 2>&1 >/dev/null

    local execute
    execute=$(ls "$out"/execute_*.sh 2>/dev/null | head -1)

    # Run dry-run (no --execute flag)
    local output
    output=$(cd "$out" && "$BASH4" "$execute" 2>&1)

    # Files should still be in source
    if assert_file_exists "$TEST_TMPDIR/source/readme.txt"; then
        pass
    fi

    teardown_test
}

test_execute_and_reversal()
{
    setup_test "execute: real run moves files, reversal restores them"
    create_standard_fixtures

    local out="$TEST_TMPDIR/output"
    mkdir -p "$out"

    CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
        --sources "$TEST_TMPDIR/source" \
        --target "$TEST_TMPDIR/target" \
        --output "$out" 2>&1 >/dev/null

    local execute reversal manifest
    execute=$(ls "$out"/execute_*.sh 2>/dev/null | head -1)
    reversal=$(ls "$out"/reversal_*.sh 2>/dev/null | head -1)
    manifest=$(ls "$out"/manifest_*.txt 2>/dev/null | head -1)

    # Execute for real (pipe 'yes' to confirm)
    (cd "$out" && echo "yes" | "$BASH4" "$execute" --execute) 2>&1 >/dev/null

    # Verify some files moved to target
    local target="$TEST_TMPDIR/target"
    if [[ -d "$target" ]]; then
        local moved_count
        moved_count=$(find "$target" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$moved_count" -eq 0 ]]; then
            fail "No files were moved to target"
            teardown_test
            return
        fi
    else
        fail "Target directory was not created"
        teardown_test
        return
    fi

    # Now run reversal
    (cd "$out" && echo "yes" | "$BASH4" "$reversal") 2>&1 >/dev/null

    # Check that original files are restored
    if assert_file_exists "$TEST_TMPDIR/source/readme.txt"; then
        pass
    fi

    teardown_test
}

test_special_characters_in_names()
{
    setup_test "edge case: files with spaces and quotes in names"

    TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/cleanup_test_XXXXXX")
    local src="$TEST_TMPDIR/source"
    mkdir -p "$src"

    echo "spaced" > "$src/my file.txt"
    echo "quoted" > "$src/it's a file.txt"
    echo "parens" > "$src/report (final).pdf"

    local out="$TEST_TMPDIR/output"
    mkdir -p "$out"

    local output
    output=$("$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$src" 2>&1)
    local total
    total=$(echo "$output" | grep "ANALYSIS_COMPLETE|" | cut -d'|' -f2)

    if [[ "$total" -eq 3 ]]; then
        # Now test that generate_plan handles them
        CLEANUP_CREATE_BACKUP=0 "$BASH4" "${PROJECT_DIR}/src/generate_plan.sh" \
            --sources "$src" \
            --target "$TEST_TMPDIR/target" \
            --output "$out" 2>&1 >/dev/null

        local manifest
        manifest=$(ls "$out"/manifest_*.txt 2>/dev/null | head -1)
        local planned
        planned=$(grep -c '^PLANNED|' "$manifest" 2>/dev/null || echo "0")

        if [[ "$planned" -eq 3 ]]; then
            pass
        else
            fail "Expected 3 PLANNED entries, got $planned"
        fi
    else
        fail "Expected 3 files, got $total"
    fi

    teardown_test
}

test_find_excludes_shared()
{
    setup_test "utils: FIND_EXCLUDES filters .DS_Store and .git"

    TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/cleanup_test_XXXXXX")
    local src="$TEST_TMPDIR/source"
    mkdir -p "$src/.git/objects"

    echo "real file" > "$src/hello.txt"
    echo "ds store" > "$src/.DS_Store"
    echo "localized" > "$src/.localized"
    echo "git object" > "$src/.git/objects/abc123"

    local output
    output=$("$BASH4" "${PROJECT_DIR}/src/analyze.sh" "$src" 2>&1)
    local total
    total=$(echo "$output" | grep "ANALYSIS_COMPLETE|" | cut -d'|' -f2)

    if assert_equals "$total" "1"; then
        pass
    fi

    teardown_test
}

test_format_bytes()
{
    setup_test "utils: format_bytes returns correct units"

    # Source utils.sh in a subshell to test format_bytes
    local result
    result=$("$BASH4" -c "source '${PROJECT_DIR}/src/utils.sh'; format_bytes 1048576")
    if [[ "$result" == "1 MB" ]]; then
        result=$("$BASH4" -c "source '${PROJECT_DIR}/src/utils.sh'; format_bytes 500")
        if [[ "$result" == "500 bytes" ]]; then
            result=$("$BASH4" -c "source '${PROJECT_DIR}/src/utils.sh'; format_bytes 1073741824")
            if [[ "$result" == "1 GB" ]]; then
                pass
            else
                fail "Expected '1 GB', got '$result'"
            fi
        else
            fail "Expected '500 bytes', got '$result'"
        fi
    else
        fail "Expected '1 MB', got '$result'"
    fi

    teardown_test
}

test_get_file_hash()
{
    setup_test "utils: get_file_hash returns SHA-256"

    TEST_TMPDIR=$(mktemp -d "${TMPDIR:-/tmp}/cleanup_test_XXXXXX")
    echo -n "test" > "$TEST_TMPDIR/hashfile"

    local result
    result=$("$BASH4" -c "source '${PROJECT_DIR}/src/utils.sh'; get_file_hash '$TEST_TMPDIR/hashfile'")

    # SHA-256 of "test" (no newline) is known
    local expected="9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
    if assert_equals "$result" "$expected"; then
        pass
    fi

    teardown_test
}

# ============================================================================
# MAIN
# ============================================================================

echo ""
echo -e "${BOLD}=============================================="
echo "  File Folder Cleanup Utility — Test Suite"
echo -e "==============================================${NC}"
echo ""

test_analyze_basic
test_analyze_per_directory_count
test_analyze_duplicate_detection
test_analyze_filename_conflicts
test_propose_template
test_generate_plan_creates_files
test_generate_manifest_format
test_generate_no_injection
test_execute_dry_run
test_execute_and_reversal
test_special_characters_in_names
test_find_excludes_shared
test_format_bytes
test_get_file_hash

echo ""
echo -e "${BOLD}=============================================="
echo "  Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
echo -e "==============================================${NC}"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
