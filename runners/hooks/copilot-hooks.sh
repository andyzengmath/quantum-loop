#!/usr/bin/env bash
# copilot-hooks.sh — Pre-spawn + post-output hooks for GitHub Copilot CLI.

# Pre-spawn: append autonomous, scripting-safe flags for non-interactive dispatch.
pre_spawn() {
  RUNNER_EXTRA_FLAGS="${RUNNER_EXTRA_FLAGS:+$RUNNER_EXTRA_FLAGS }--autopilot --max-autopilot-continues 0 --no-ask-user --silent --no-color --stream off --no-remote"
}

# Post-output: v0.10.7 / US-001 — copilot rate-limit observability.
# Detects rate-limit error signals in the captured copilot CLI output and
# emits a visible [RATE-LIMIT] log line to stderr. Patterns: rate-limit,
# 429, Retry-After, quota-exceeded, too-many-requests (case-insensitive).
# Idempotent: emits once per invocation even if multiple matches.
# Pure observability — does NOT alter signal classification or retry logic.
post_output() {
  local output="$1"
  # Single-pass case-insensitive grep. Capture first matching line for context.
  local first_match
  first_match=$(printf '%s\n' "$output" \
    | grep -iE 'rate.?limit|\b429\b|retry-after|quota.?exceeded|too.many.requests' \
    | head -1)
  if [[ -n "$first_match" ]]; then
    # Trim leading/trailing whitespace + truncate at 120 chars.
    first_match="${first_match#"${first_match%%[![:space:]]*}"}"
    first_match="${first_match%"${first_match##*[![:space:]]}"}"
    if (( ${#first_match} > 120 )); then
      first_match="${first_match:0:117}..."
    fi
    printf "[RATE-LIMIT] copilot rate-limit detected: %s\n" "$first_match" >&2
    # Optional: extract Retry-After value if parseable.
    # v0.10.7 / US-003 review fix: use sed capture-group anchored on
    # "retry-after" to extract only the value after that header,
    # avoiding mis-capture of preceding numbers (e.g. "HTTP/1.1 429
    # Retry-After: 30" -> 30, not 1 or 429).
    local retry_after
    retry_after=$(printf '%s\n' "$output" \
      | sed -n 's/.*[Rr]etry-[Aa]fter[: ]\{1,\}\([0-9][0-9]*\).*/\1/p' \
      | head -1)
    # v0.10.13 / US-002: fallback for RFC 7230-deprecated folded-header
    # form. Some legacy proxies / older copilot CLI versions emit:
    #   Retry-After:
    #       30
    # When single-line extraction returns empty, look for `Retry-After:`
    # alone on a line followed by a numeric value on the next non-empty
    # line. awk handles the line-context state.
    if [[ -z "$retry_after" ]]; then
      # v0.10.13 / US-003 review fix (code-reviewer MEDIUM): use match/
      # substr to extract only the FIRST contiguous digit group from the
      # continuation line, avoiding gsub-non-digits which would concat
      # disparate digit groups (e.g., "30 something 99" → "3099").
      # found-flag resets on non-continuation lines (header line followed
      # by a non-numeric line cancels the lookup) to avoid spurious match.
      retry_after=$(printf '%s\n' "$output" \
        | awk '
          /[Rr]etry-[Aa]fter[: ]*$/ { found=1; next }
          found && /^[ \t]*[0-9]+/ { match($0, /[0-9]+/); print substr($0, RSTART, RLENGTH); exit }
          found && !/^[ \t]/ { found=0 }
        ')
    fi
    if [[ -n "$retry_after" ]]; then
      printf "[RATE-LIMIT] copilot suggests Retry-After: %ss\n" "$retry_after" >&2
    fi
  fi
}
