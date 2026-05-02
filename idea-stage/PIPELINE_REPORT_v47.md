# PIPELINE_REPORT_v47 — v0.10.13 retrospective (LOW idle-ticker batch: OSC body strip + Retry-After multi-line)

**Date:** 2026-05-02
**Bundle:** `ql/v0.10.13-bundle` (release tag v0.10.13 — pending push/PR/merge/tag/release)
**Predecessor report:** `idea-stage/PIPELINE_REPORT_v46.md`
**Master parent:** `703ce40` (v0.10.12 ship state)
**Source:** `tasks/prd-v0.10.13-bundle.md` (auto-approved per `/loop` step 4-5; batches the 2 deferred LOW idle-tickers per loop instruction "propose new tasks or fix gaps").

## Overview

4-story patch closing 2 deferred LOW security/correctness items previously classified "defer indefinitely":
1. **OSC body strip** in `lib/json-atomic.sh` ANSI sanitization (carried since v0.10.8).
2. **Retry-After multi-line fallback** in `runners/hooks/copilot-hooks.sh` (carried since v0.10.7).

Code change: ~5 LOC functional + ~25 LOC tests + comments. **41st consecutive LOW G30 self-validation.**

## The 4 stories

| # | ID | Title | Outcome |
|:-:|---|---|:-:|
| 0 | (cycle setup) | chore: v0.10.13 cycle kickoff (PRD only) | committed at `91fecaf` |
| 1 | US-001 + US-002 | OSC body strip (with ESC-byte neutralization) + Retry-After multi-line fallback | first-attempt PASS at `0c540ff` |
| 2 | US-003 | 22nd p014 review trio (SHIP; 3 MEDIUM + 2 LOW inline-fixed) | committed at `b2b79e3` |
| 3 | US-004 | Retrospective + IDEA_REPORT_v47 + version bump 0.10.12 → 0.10.13 | this report |

## US-001 deep-dive: OSC body strip

`lib/json-atomic.sh` (sites at lines 301, 348 — both updated identically via `replace_all`) sed pipeline extended:

```bash
# Final pipeline:
sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' -e 's/\x1b\][^\x07]*\x07//g' \
  | tr -d '\001-\010\013-\037\177\033'
```

- **Pass 1:** strips CSI sequences (`\x1b[...m`) — unchanged from v0.10.8.
- **Pass 2 (NEW):** strips OSC-BEL form (`\x1b]...\x07`) — most common on xterm-derived terminals.
- **tr extended (NEW):** adds `\033` (ESC byte) to the strip set. Catches any unmatched escape framing — including OSC-ST (`\x1b]...\x1b\\`) which sed-dialect literal-backslash escaping makes fragile to pattern-match cleanly. Body chars remain as harmless plaintext (no ESC = no terminal interpretation possible).

**Architectural rationale (post-review-fix comment):** The ESC-byte strip is more robust than trying to match every escape variant. Architectural intent (block terminal manipulation) achieved without dialect-fragile sed.

## US-002 deep-dive: Retry-After multi-line fallback

`runners/hooks/copilot-hooks.sh::post_output` Retry-After extraction (around line 35-50):

```bash
# Primary: single-line sed (unchanged from v0.10.7).
retry_after=$(printf '%s\n' "$output" | sed -n 's/.../\1/p' | head -1)

# Fallback (NEW): RFC 7230-deprecated folded-header form.
if [[ -z "$retry_after" ]]; then
  retry_after=$(printf '%s\n' "$output" \
    | awk '
      /[Rr]etry-[Aa]fter[: ]*$/ { found=1; next }
      found && /^[ \t]*[0-9]+/ { match($0, /[0-9]+/); print substr($0, RSTART, RLENGTH); exit }
      found && !/^[ \t]/ { found=0 }
    ')
fi
```

**Post-review-fix design choices:**
- `match($0, /[0-9]+/) + substr` (not `gsub /[^0-9]/`) extracts only the FIRST contiguous digit group, avoiding `30 retry-id-99 → 3099` concat bug (caught by code-reviewer MEDIUM).
- `found && !/^[ \t]/ {found=0}` resets the lookup state when a non-continuation line appears, preventing spurious match on later body text (caught by architect LOW).

## Multi-perspective review synthesis (US-003; 22nd p014 application)

| Reviewer | Verdict | Score | Key findings |
|---|---|---:|---|
| **Architect** | SHIP | 88 | **1 MEDIUM (inline-fixed):** Test 16 OSC-ST sub-case input encoding bug (`printf '\\back'` = ESC + backspace, not ESC + backslash). Fixed with `\x5c` hex escape; added explicit OSC-ST framing-neutralization assertion. **2 LOW (1 inline-fixed, 1 deferred):** awk found-flag unbounded → reset added; PRD AC text divergence noted in commit (PRD-update deferred as historical artifact). |
| **Code-reviewer** | SHIP | 82 | **2 MEDIUM (1 inline-fixed, 1 documentation-fixed):** awk gsub digit concat (real bug; replaced with match/substr); OSC-ST PRD deviation (documentation-only; comment added explaining ESC-byte-strip rationale). **1 LOW (acceptable as-is):** Test 16 inline-replicates pipeline rather than calling json_atomic functions; pragmatic for unit-style sanitization test. |
| **Security** | SHIP | 97 | **0 findings.** OSC body residue without ESC framing is inert plaintext; awk extraction safe (no injection vector); no new attack surface. 3-pt deduction was for PRD/code mismatch (documentation hygiene; not security). |

**8th p014 catch in 22 applications career; ~36% career hit-rate.** Convergent finding (architect + code-reviewer caught the test-encoding + OSC-ST documentation gaps from different angles). All score-≥85 inline-fixable findings closed in this commit.

## Test-suite delta vs v0.10.12

`tests/test_json_atomic.sh`: 35 → 39 tests (+4 sub-asserts in Test 16: no ESC bytes; CSI preserves text; OSC-BEL strips body; OSC-ST framing neutralized).

6 baseline suites green: test_signal_parsing 15/15, test_coordinator_e2e 21/21, test_dag_query 44/44, test_json_atomic 39/39, test_next_wave 18/18, test_orchestrator_liveness 38/38 = **175 total**.

## v0.10.13 fixes shipped + deferrals

### Closed

| Finding | Severity | Source | Resolution |
|---|---|---|---|
| OSC body residue (carried since v0.10.8) | LOW (security) | wave plan | US-001 (sed pass 2 + tr ESC byte) |
| Retry-After multi-line edge case (carried since v0.10.7) | LOW | wave plan | US-002 (awk fallback with match/substr + found-reset) |
| Test 16 OSC-ST input encoding bug | MEDIUM (review) | architect | inline-fixed |
| awk gsub digit concat | MEDIUM (review) | code-reviewer | inline-fixed |
| OSC-ST PRD deviation undocumented | MEDIUM (review) | code-reviewer | code-comment added |
| awk found-flag unbounded | LOW (review) | architect | inline-fixed |

### Deferred (unchanged + new pre-existing items)

| Finding | Severity | Path |
|---|---|---|
| N43 — Parallel-with-dispatch wrap | MEDIUM | v0.11.x (operator-gated) |
| N48 stub-coordinator test coverage | MEDIUM (sub-threshold) | v0.11.0 dogfood |
| N47 — branch cleanup | operator | operator-decision-pending |
| PR_v44:43 "6th catch" off-by-one (career stat may be 8/22 not 8/22 — same-ish) | LOW (pre-existing) | future p015 audit |
| p014 range notation ambiguity | MEDIUM (pre-existing notational) | future p015 audit |
| test_orchestrator_liveness.sh approaching split (~495 LOC / 16 tests) | LOW | defer; trigger at ~600 LOC |
| PRD AC text vs implementation divergence (US-001 OSC-ST sed) | LOW | historical artifact; not updating |

## G30 self-validation — 41st consecutive LOW

Patch-tier delta: ~5 LOC functional + ~25 LOC tests + retro + version bump. **41 consecutive LOW** (v0.6.5..v0.10.13).

## Manual-takeover streak

v0.10.13 driven via autonomous /loop cron pattern. **Streak: PARTIALLY BROKEN through v0.10.13** — 15 consecutive cycles with 1 operator gate (at v0.10.6 wave plan approval).

## codebasePatterns

p001-p016 carried forward. **17 named patterns canonized** as of v0.10.13. p016 ("dogfood-driven LOW sweep wave") canonized at 1 application; v0.10.13 is a related "post-wave LOW idle-ticker batch" mode but distinct in that it's a 1-cycle batch, not a multi-cycle wave plan.

## Recommendation pointer

See `idea-stage/IDEA_REPORT_v47.md`. With OSC + Retry-After closed, the autonomous backlog now has only pre-existing notational artifacts (career hit-rate counting consistency) + sub-threshold MEDIUMs + operator-gated items. Likely truly idle from here until operator action.
