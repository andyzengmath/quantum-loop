# Risk-mitigation language: writing checklist for design-doc authors (G28 / v0.6.5 / US-004)

This document is a craft guide for the **Risk** section of a design doc.
A design-doc Risk section identifies a hazard and prescribes a
mitigation. When the prescription names only a *technique* without
enumerating the *operations* the technique must wrap, an implementer
can faithfully apply the technique to the wrong scope and ship a bug
the design doc claimed was prevented.

The companion doc, [`finding-severity.md`](finding-severity.md), guides
how reviewers grade findings. This doc guides how design-doc authors
phrase the prescriptions reviewers will later grade. The two are paired:
review craft + design craft.

---

## Risk-mitigation prose: enumerate operations, not just techniques

**The rule.** A risk-mitigation paragraph must name the *technique*
**and** enumerate the **specific operations** the technique must cover.
"Use flock around the writer" is incomplete; "Use flock around the
writer's bootstrap-header check, header write, and append" is complete.

**Why this matters (the v0.6.4 cautionary tale).** v0.6.4 G13 added a
CSV writer for `metrics/pre-impl-review-findings.csv` with persistent
flock-style serialization. The design doc's Risk section read:

> Risk: concurrent writes from parallel pre-impl-review hooks could
> interleave rows. Mitigation: use flock-style atomic append.

The prose named the technique (flock) and one of the operations
(append), so the implementation wrapped flock around the row-append.
It did NOT wrap flock around the **header bootstrap** that runs the
first time the CSV is created. Result: two parallel hooks both saw
"file does not exist," both wrote the header, and the CSV ended up
with the header line twice. The race window was small but real:
two near-simultaneous fresh-checkout invocations of pre-impl-review.

The soliton finding (confidence 90 in the v0.6.4 deep-review pass)
caught the gap by reading the lock scope against the writer's
control flow. Commit `c89ba13` closed the gap by hoisting the lock
acquisition before the existence check. The mitigation was correct
in spirit; the prose just under-specified its scope.

**What the design doc should have said:**

> Risk: concurrent writes from parallel pre-impl-review hooks could
> interleave rows OR double-bootstrap the header. Mitigation: hold a
> single flock over the **bootstrap-header check, header write, and
> data row append** -- all three operations are observably coupled
> through the same file descriptor and must share one critical
> section.

The added clauses ("bootstrap-header check, header write, and data
row append") name the three operations. An implementer who reads
this prose cannot apply flock to only the append.

---

## Concurrency checklist for design docs

When a design doc proposes a concurrency mitigation, the Risk paragraph
must enumerate four items. Each item is a one-line answer; the absence
of any one of them produces the v0.6.4-style ambiguity.

1. **Shared mutable state.** Name the variable, file, table row, or
   in-memory structure that two threads/processes/agents could write
   simultaneously. "The CSV at `metrics/pre-impl-review-findings.csv`."
   Without this, no reviewer can verify the mitigation covers the right
   surface.

2. **Full set of observably-coupled operations.** Enumerate every
   operation that touches the shared state and whose ordering is
   observable to other writers. For a CSV: existence-check + header
   write + data append. For a counter: load + increment + store. For
   a cache: lookup + miss-fetch + populate. The full set is what the
   critical section must wrap; a partial set is a bug waiting to ship.

3. **Race window without mitigation.** Describe a concrete interleaving
   that triggers the bug. "Two hooks A and B both pass the
   `[[ -f csv ]]` check before either writes the header; both then
   write the header line; the CSV starts with the header twice."
   Without a concrete race, the reviewer cannot confirm the mitigation
   actually addresses the right window.

4. **Race window with mitigation.** Describe the same interleaving
   under the proposed mitigation, showing it can no longer trigger
   the bug. "Hook A acquires the flock; B blocks. A runs the existence
   check, header write, and append, then releases. B acquires, sees
   the file exists, skips header bootstrap, appends. Header appears
   exactly once." Without a worked example showing the fix, the
   mitigation is hopeful, not verified.

The four items are mechanical to write once you've identified the
shared state. The v0.6.4 design doc had item 1 (the CSV) but skipped
items 2-4 -- specifically, it never enumerated the bootstrap as a
coupled operation, so items 3-4 had nothing to anchor against.

---

## Other risk-mitigation language patterns

The same enumeration discipline applies to non-concurrency risks. The
common shapes:

- **"Validate input X."** Enumerate the fields validated, the rules
  enforced, and the failure mode. "Validate `quantum.json`" is incomplete;
  "Validate `quantum.json` has a top-level `stories` array of objects,
  each with required `id` and `tasks` fields, rejecting on schema
  violation with exit 2 and a `quantum.json:line:column` pointer" is
  complete. An implementer can reproduce the validator from the prose.

- **"Handle malformed Y."** Enumerate the malformed forms anticipated,
  the action for each, and the return/raise contract. "Handle malformed
  CSV" is incomplete; "Handle CSV with (a) missing trailing newline
  (auto-append), (b) row with fewer columns than the header (raise
  ValueError), (c) row with embedded newline in unquoted field (raise
  CSVFormatError); all error paths return a non-zero exit code with the
  row number on stderr" is complete.

- **"Atomic update Z."** Enumerate the atomicity scope (which set of
  reads/writes are inside the atomic boundary), the isolation level
  (serializable / repeatable-read / read-committed), and the rollback
  surface. "Atomically update the manifest" is incomplete; "Atomically
  update the manifest's `version` and `updatedAt` fields together; reads
  see either both old or both new, never split; on write failure, neither
  field changes" is complete.

The shared move across all three patterns is the same as for concurrency:
**enumerate operations**, not just techniques.

---

## See also

- [`finding-severity.md`](finding-severity.md) -- the review-craft pair
  to this design-craft doc. Reviewers grading risk-mitigation findings
  use the rubric there; design-doc authors writing risk-mitigation prose
  use the checklist here.
- v0.6.4 commit `c89ba13` -- the canonical cautionary tale this doc
  exists to prevent.
