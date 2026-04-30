#!/usr/bin/env bash
# lib/coordinator-guard.sh — coordinator HEAD-snapshot guard (v0.9.2 / US-001)
#
# Closes v0.9.1 finding 5a HIGH (implementer subagent ran `git reset --hard`
# mid-wave, wiping prior story commit; coordinator self-healed emergently).
# This library provides an engineered safety net the coordinator must
# invoke after each implementer dispatch — see agents/coordinator.md step 2.
#
# Per v0.9.1 US-004 security review: ordinal SHA comparison is INSUFFICIENT.
# An implementer can `reset --hard <prior-sha> && commit <different-content>`
# to advance HEAD past a snapshot while creating a SIBLING rather than a
# descendant. Naive `[[ "$head_after" != "$head_before" ]]` would accept
# this as "HEAD moved forward". Ancestry check via
# `git merge-base --is-ancestor` correctly rejects siblings.
#
# Functions:
#   guard_head_advance HEAD_BEFORE [HEAD_AFTER=HEAD]
#     Returns 0 if HEAD_BEFORE is an ancestor of HEAD_AFTER (legitimate
#     advance — implementer added commits on top). Returns 1 with stderr
#     message containing "HEAD reset detected" otherwise. Stderr is silent
#     on success.
#
# Library contract: no shell flags at source time; strict mode only in the
# CLI-entry block at bottom (mirrors lib/finding-persist.sh, lib/handoff.sh).

# Source-guard
if [[ -n "${_QL_COORDINATOR_GUARD_LIB:-}" ]]; then
  return 0 2>/dev/null || true
fi
readonly _QL_COORDINATOR_GUARD_LIB=1

# guard_head_advance(head_before, [head_after=HEAD]) -> 0 | 1
guard_head_advance() {
  local head_before="${1:?guard_head_advance: HEAD_BEFORE required (e.g. \$(git rev-parse HEAD) before implementer dispatch)}"
  local head_after="${2:-HEAD}"
  if ! git merge-base --is-ancestor "$head_before" "$head_after" 2>/dev/null; then
    printf "ERROR: guard_head_advance: HEAD reset detected — %s not ancestor of %s\n" \
      "$head_before" "$head_after" >&2
    return 1
  fi
  return 0
}

# ------------------------------------------------------------------------------
# CLI entry. Strict mode only here.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  subcmd="${1:-}"
  shift || true
  case "$subcmd" in
    guard_head_advance)
      # guard_head_advance HEAD_BEFORE [HEAD_AFTER]
      guard_head_advance "$@"
      ;;
    *)
      cat >&2 <<USAGE
Usage: bash lib/coordinator-guard.sh <subcmd> [args...]
  guard_head_advance HEAD_BEFORE [HEAD_AFTER=HEAD]
    Verify HEAD_BEFORE is ancestor of HEAD_AFTER. Returns 0 on legit advance,
    1 on HEAD reset (with stderr message). Per v0.9.1 US-004 security review:
    uses git merge-base --is-ancestor (NOT ordinal comparison).
USAGE
      exit 2
      ;;
  esac
fi
