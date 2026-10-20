#!/usr/bin/env bash
# Runs every check the protocol's repositories have.
#
# The protocol has no continuous integration: its checks are local, and
# this script is how they are run together. It is what a contributor runs
# before opening a proposal, and what a release is cut from.
#
# Usage:
#   scripts/verify.sh                # check what is present
#   scripts/verify.sh --all          # require every repository
#
# The repositories are expected next to this one as `../mlp-core`,
# `../mlp-ts`, `../mlp-proto`, `../mlp-conformance` and `../mlp-harness`. A
# repository that is absent is reported and skipped, unless `--all` was
# given.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(cd "$REPO_ROOT/.." && pwd)"

CORE_DIR="${MLP_CORE_DIR:-$WORKSPACE/mlp-core}"
TS_DIR="${MLP_TS_DIR:-$WORKSPACE/mlp-ts}"
PROTO_DIR="${MLP_PROTO_DIR:-$WORKSPACE/mlp-proto}"
CONFORMANCE_DIR="${MLP_CONFORMANCE_DIR:-$WORKSPACE/mlp-conformance}"
HARNESS_DIR="${MLP_HARNESS_DIR:-$WORKSPACE/mlp-harness}"

REQUIRE_ALL=0
for argument in "$@"; do
    case "$argument" in
        --all) REQUIRE_ALL=1 ;;
        *) printf 'verify: unknown argument %s\n' "$argument" >&2; exit 2 ;;
    esac
done

PASSES=0
FAILURES=0
SKIPPED=0

ok() {
    PASSES=$((PASSES + 1))
    printf '  ok    %s\n' "$1"
}

fail() {
    FAILURES=$((FAILURES + 1))
    printf '  FAIL  %s\n' "$1" >&2
    if [ $# -gt 1 ]; then
        printf '        %s\n' "$2" >&2
    fi
}

skip() {
    SKIPPED=$((SKIPPED + 1))
    printf '  skip  %s\n' "$1"
}

# Run a step, and report it by name.
step() { # name, directory, command...
    local name="$1" directory="$2"
    shift 2
    if [ ! -d "$directory" ]; then
        if [ "$REQUIRE_ALL" = "1" ]; then
            fail "$name" "the repository is missing at $directory"
        else
            skip "$name (no repository at $directory)"
        fi
        return 0
    fi
    if ( cd "$directory" && "$@" ) >/tmp/mlp-verify-step.log 2>&1; then
        ok "$name"
    else
        fail "$name" "see the output below"
        tail -20 /tmp/mlp-verify-step.log >&2
    fi
}

echo "verify: the protocol's repositories"

step "specification: cross-references resolve" "$REPO_ROOT" \
    node scripts/check-references.mjs

step "specification: cross-references resolve in the implementations" "$REPO_ROOT" \
    node scripts/check-references.mjs \
        --impl "$CORE_DIR" --impl "$TS_DIR" --impl "$CONFORMANCE_DIR"

step "mlp-core: builds" "$CORE_DIR" cargo build
step "mlp-core: tests" "$CORE_DIR" cargo test
step "mlp-core: lints clean" "$CORE_DIR" cargo clippy --all-targets -- -D warnings
step "mlp-core: formatted" "$CORE_DIR" cargo fmt --check

step "mlp-ts: typechecks" "$TS_DIR" npm run typecheck
step "mlp-ts: tests" "$TS_DIR" npm test

step "mlp-proto: generated bindings are current" "$PROTO_DIR" npm run generate:check

step "mlp-conformance: the corpus is reproducible" "$CONFORMANCE_DIR" \
    scripts/conformance-gate.sh

step "mlp-conformance: the gate checks its own teeth" "$CONFORMANCE_DIR" \
    scripts/conformance-gate.sh --self-test

step "mlp-harness: the harness's own checks" "$HARNESS_DIR" \
    scripts/verify.sh

step "mlp-harness: the gate checks its own teeth" "$HARNESS_DIR" \
    scripts/verify.sh --self-test

if [ "$FAILURES" -eq 0 ]; then
    echo "verify: all checks passed ($PASSES passed, $SKIPPED skipped)"
    exit 0
fi
echo "verify: $FAILURES check(s) failed" >&2
exit 1
