# Soliton finding triage — validate before designing

**Audience:** operators triaging post-merge `/soliton:pr-review` findings between cycles, deciding which findings to address in the next cycle's design slate.

**Why this exists:** v0.6.7's US-002 shipped a fix for a soliton finding (G36, confidence 82) that turned out to be a hallucination — the bug didn't exist as described. The defensive guard + regression-guard test still had value, but a real reproduction at design time would have surfaced the false-positive earlier.

The score-≥85 inline-fix threshold is calibrated for high-confidence findings. Below 85, soliton's accuracy drops; **operators carrying sub-threshold findings into the next cycle's design slate must validate empirically first.**

## Workflow

For each sub-threshold soliton finding (score < 85) that the operator wants to address in the next cycle:

1. **Read the finding's claimed mechanism.** Identify the input that would trigger the bug (an empty argument, a malformed file, a specific shell flag, etc.).
2. **Write a 1-line empirical reproduction.** A single bash command that demonstrates the bug — exit code, stderr line, log output — whatever the finding claims.
3. **Run it.**
   - **Repro succeeds (bug is real)** → file as a fix story in the next cycle's design slate. Cite the 1-line repro in the design doc's Problem section so reviewers can verify.
   - **Repro fails (hallucination)** → file as a regression-guard test only. Lock in the current correct behavior so a future refactor that genuinely introduces the bug surface is caught at test time.
   - **Repro is ambiguous (works on some inputs)** → narrow the input range, repeat. If still ambiguous, defer the finding to a later cycle and capture the ambiguity in the IDEA_REPORT backlog.

## Repro template

```bash
# Sub-threshold finding: <one-line summary>
# Source: <agent name + confidence score>
# Claimed mechanism: <bug summary>

# Repro:
$ <single bash command demonstrating the claimed bug>
# Expected (per finding): <claimed output>
# Actual: <what the command actually shows>
# Verdict: REAL / HALLUCINATION / AMBIGUOUS
```

Paste this template into the next cycle's IDEA_REPORT entry for the finding so the verdict is reviewable.

## Examples

### v0.6.7 G36 — `should_dispatch_deep_review` empty-input prod_count (HALLUCINATION)

**Soliton claim (correctness, conf 82):** "`grep -cvE '^(tests?/|$)|...'` on an empty `$files` string returns 1 (the empty-line trailing newline counts as non-matching), spuriously inflating `prod_count`."

**Repro:**

```bash
$ printf '%s\n' "" | grep -cvE '^(tests?/|$)|(\.test\.|_test\.)'
0
```

**Verdict: HALLUCINATION.** The regex's `^(tests?/|$)|...` group includes `$` to match empty lines, so `grep -cv` correctly returns 0. The bug does not manifest.

**Action taken in v0.6.7:** the defensive `if (( files_changed > 0 ))` guard shipped anyway as defense-in-depth (cheap, hardens against a future refactor that drops the `|$` anchor). The durable protection is the new Test 5 regression-guard fixture in `tests/test_deep_review_dispatch.sh` asserting `score=0 files=0` on empty input. Per this triage doc, the v0.6.7 design slate should have flagged the finding as a verified hallucination and shipped only the regression-guard test — saving the implementation time of the defensive guard. v0.6.7 retrospective (PIPELINE_REPORT_v8) captures this as the source incident for this triage process.

### Hypothetical example — confirmed-real finding

**Soliton claim (security, conf 78):** "`bash script.sh "$user_input"` with double-quoted variable expansion is vulnerable to command injection when `$user_input` contains backticks."

**Repro:**

```bash
$ user_input='`whoami`'; bash -c 'echo "$1"' _ "$user_input"
`whoami`
```

**Verdict: HALLUCINATION** — bash double-quoted variable expansion does NOT execute backticks (they only execute when typed literally in source, not from variable contents). Command-substitution-via-data-injection requires `eval` or unquoted expansion.

**Action:** would file as regression-guard test (assert: `bash -c 'echo "$1"' _ "<input-with-backticks>"` outputs the literal string).

(Both real-world examples in this doc happen to be hallucinations — that's the v0.6.7 sample size. Future cycles should add real-bug examples as they accumulate.)
