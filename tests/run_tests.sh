#!/usr/bin/env bash
# Test runner — delegates to bats-core. Run: bash tests/run_tests.sh
#
# Installs bats-core via brew if not present. Requires Bash 4+ (auto-re-execs).

if ((BASH_VERSINFO[0] < 4)); then
    for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
        if [[ -x "$candidate" ]] && "$candidate" -c '((BASH_VERSINFO[0]>=4))' 2>/dev/null; then
            exec "$candidate" "$0" "$@"
        fi
    done
    echo "Error: Bash 4+ required. Install: brew install bash" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure bats is available.
if ! command -v bats &>/dev/null; then
    echo "bats-core not found — installing via brew..."
    brew install bats-core || { echo "Error: brew install bats-core failed" >&2; exit 1; }
fi

# Export the Bash 4+ path so .bats files can use it.
export BASH4="$BASH"

exec bats --tap "$SCRIPT_DIR"/test_*.bats
