# PRD: v0.10.13 — patch-tier (LOW idle-ticker batch: OSC body strip + Retry-After multi-line)

**Status:** Auto-approved per `/loop` step 4-5; recommended path after 2 consecutive idle-tick holds. Per loop instruction "propose new tasks or fix gaps", batching the 2 deferred LOW idle-tickers as one cycle.
**Date:** 2026-05-02
**Predecessor:** `tasks/prd-v0.10.12-bundle.md`.
**Branch:** `ql/v0.10.13-bundle`.
**Target version:** 0.10.12 → 0.10.13 (patch).
**Total effort:** ~45 min.

## Section 1: Introduction / Overview

4-story patch closing 2 deferred LOW security/correctness items:
1. **OSC sequence body strip** in `lib/json-atomic.sh` ANSI sanitization (carried since v0.10.8).
2. **Retry-After multi-line edge case** in `runners/hooks/copilot-hooks.sh` (carried since v0.10.7).

Both items were previously classified "defer indefinitely" by architect's p015 audits as cosmetic/non-exploitable. Closing them as autonomous-cycle housekeeping per loop step 4-5 instruction.

## Section 2: Goals

- Strip OSC sequences (`\x1b]...\x07` and `\x1b]...\x1b\\`) in addition to existing CSI sequences during jq stderr sanitization.
- Add fallback Retry-After extraction for RFC 7230-deprecated folded-header form (value on continuation line).
- 22nd p014 review.
- Bump 0.10.12 → 0.10.13.
- 41 consecutive LOW G30.

## Section 3: User Stories

### US-001: OSC body strip in json-atomic.sh sanitization

**Acceptance Criteria:**
- [ ] `lib/json-atomic.sh:301` (and identical site at line 348) sed pattern extended with OSC-strip passes:
  - Strip OSC-BEL form: `s/\x1b\][^\x07]*\x07//g` (ESC `]` followed by body, terminated by BEL `\x07`).
  - Strip OSC-ST form: `s/\x1b\][^\x1b]*\x1b\\\\//g` (ESC `]` followed by body, terminated by ESC `\`).
- [ ] Final pattern (chained): `sed 's/\x1b\[[0-9;]*[a-zA-Z]//g; s/\x1b\][^\x07]*\x07//g; s/\x1b\][^\x1b]*\x1b\\\\//g' | tr -d '\001-\010\013-\037\177'`.
- [ ] Existing Test 14 in `tests/test_json_atomic.sh` (jq stderr surfaces in error message) still passes — sanitization preserves jq error text.
- [ ] New test verifies OSC sequences are stripped (e.g., input containing `\x1b]2;title\x07` produces output without that subsequence).
- [ ] `bash -n lib/json-atomic.sh` clean.
- [ ] `bash tests/test_json_atomic.sh` rc=0; ≥35 tests pass (existing baseline + new).

### US-002: Retry-After multi-line fallback in copilot-hooks.sh

**Acceptance Criteria:**
- [ ] `runners/hooks/copilot-hooks.sh::post_output` Retry-After extraction (around lines 35-38) gets a fallback for RFC 7230-deprecated folded-header form: when the main sed returns empty, look for `Retry-After:` followed by a value on the next non-empty line.
- [ ] Fallback uses awk for stateful line-context: `awk '/[Rr]etry-[Aa]fter[: ]*$/ {found=1; next} found && /^[ \t]*[0-9]+/ {gsub(/[^0-9]/, ""); print; exit}'`.
- [ ] Single-line case unchanged (original sed still runs first; fallback only fires when single-line returns empty).
- [ ] No regression: smoke test the existing 3 edge cases (30/60/90 in single-line form) all still extract correctly.
- [ ] `bash -n runners/hooks/copilot-hooks.sh` clean.

### US-003: Multi-perspective post-merge review (22nd application)

**Acceptance Criteria:**
- [ ] 3 reviewer agents (architect + code-reviewer + security) invoked in parallel.
- [ ] No score-≥85 finding deferred.

### US-004: Retrospective + IDEA_REPORT_v47 + version bump 0.10.12 → 0.10.13

**Acceptance Criteria:**
- [ ] `idea-stage/PIPELINE_REPORT_v47.md` documents v0.10.13 (4 stories).
- [ ] `idea-stage/IDEA_REPORT_v47.md` rolling forward state.
- [ ] `CHANGELOG.md [0.10.13]` entry.
- [ ] 4 plugin manifest version fields bumped 0.10.12 → 0.10.13.
- [ ] G30 self-validation (41st consecutive LOW expected).

## Section 4: Functional Requirements

- **FR-1:** OSC strip preserves jq error text content; only strips control sequences.
- **FR-2:** Retry-After multi-line fallback only fires when single-line extraction returns empty.
- **FR-3:** Plugin version 0.10.12 → 0.10.13 (4 fields).

## Section 5: Non-Goals

- No `--coordinator` dispatch (still v0.11.0 reserved).
- No N43 / N48 stub-coord work (operator-gated).
- No N47 branch cleanup (operator-decision).
- No pre-existing notational artifact cleanup (PR_v44:43 off-by-one + p014 range ambiguity; defer to v0.10.14 if pursued).

## Section 6: Design Notes

**OSC sequence anatomy:** `ESC ]` (CSI: `ESC [`) opens an OSC, body is variable-length text (often title/icon-name), terminator is either:
- BEL (`\x07`) — most common on xterm-derived terminals.
- ST (`ESC \`, i.e., `\x1b\\`) — formal X3.64.

Both forms must be stripped to prevent operator-terminal manipulation via attacker-controlled jq stderr. Cosmetic-tier exploitation only (operator-only attack surface; no privilege boundary crossed) per security MEDIUM at v0.10.8.

**Retry-After RFC 7230:** Folded headers were deprecated by RFC 7230 §3.2.4 but may still appear in legacy proxies / older copilot CLI versions. Fallback handles the case `Retry-After:\n   30`.

## Section 7: Technical Notes

Bash 4.3+. Sed + awk available everywhere.

## Section 8: Success Metrics

- All 4 stories first-attempt PASS.
- 6 test suites green: 15+21+44+(35+1)+18+38 = 172.
- 41 consecutive LOW G30.
