#!/usr/bin/env bash
# Test suite for lib/merge-strategy.sh
# Tests get_merge_context, classify_conflict, resolve_conflict, classify_and_merge

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/../lib"
PASS=0
FAIL=0
TOTAL=0

# Source the library under test
if [[ ! -f "$LIB_DIR/merge-strategy.sh" ]]; then
  echo "SKIP: lib/merge-strategy.sh not found (RED phase)"
  exit 1
fi
source "$LIB_DIR/merge-strategy.sh"

assert_eq() {
  local test_name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local test_name="$1" needle="$2" haystack="$3"
  TOTAL=$((TOTAL + 1))
  if ! echo "$haystack" | grep -q "$needle"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name"
    echo "    expected NOT to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

# =========================================================================
echo "=== T-019 Tests: get_merge_context ==="
# =========================================================================

echo "--- Test 1: get_merge_context function exists ---"
TOTAL=$((TOTAL + 1))
if type get_merge_context &>/dev/null; then
  echo "  PASS: get_merge_context is defined"
  PASS=$((PASS + 1))
else
  echo "  FAIL: get_merge_context not defined"
  FAIL=$((FAIL + 1))
fi

echo "--- Test 2: get_merge_context reads mergeStrategy rules ---"
TMPDIR_T019=$(mktemp -d)
# Create a minimal quantum.json with mergeStrategy
cat > "$TMPDIR_T019/quantum.json" <<'QJSON'
{
  "execution": {
    "materializedContracts": ["AliasRegistry", "FeatureCluster"],
    "mergeStrategy": {
      "rules": [
        {
          "name": "dependency_manifest",
          "filePattern": "dependency_manifest",
          "strategy": "ours",
          "postAction": "install"
        },
        {
          "name": "barrel_export",
          "filePattern": "barrel_export",
          "strategy": "regenerate"
        }
      ],
      "defaultAction": "escalate"
    }
  },
  "progress": [
    {
      "filesChanged": ["src/types.ts", "src/index.ts"]
    },
    {
      "filesChanged": ["lib/common.sh"]
    }
  ]
}
QJSON

CTX_FILE=$(get_merge_context "$TMPDIR_T019/quantum.json")
EXIT_CODE=$?
assert_eq "get_merge_context exits 0" "0" "$EXIT_CODE"

# Check context file exists and is readable
TOTAL=$((TOTAL + 1))
if [[ -f "$CTX_FILE" ]]; then
  echo "  PASS: context file exists at $CTX_FILE"
  PASS=$((PASS + 1))
else
  echo "  FAIL: context file does not exist (got: '$CTX_FILE')"
  FAIL=$((FAIL + 1))
fi

# Check it contains the default action
if [[ -f "$CTX_FILE" ]]; then
  CTX_CONTENT=$(cat "$CTX_FILE")
  assert_contains "context has defaultAction" "defaultAction=escalate" "$CTX_CONTENT"
  assert_contains "context has materializedContracts" "materializedContracts=" "$CTX_CONTENT"
  assert_contains "context has AliasRegistry" "AliasRegistry" "$CTX_CONTENT"
  assert_contains "context has filesChanged" "filesChanged=" "$CTX_CONTENT"
  assert_contains "context has src/types.ts" "src/types.ts" "$CTX_CONTENT"
  assert_contains "context has lib/common.sh" "lib/common.sh" "$CTX_CONTENT"
  assert_contains "context has rules" "rules=" "$CTX_CONTENT"
fi

rm -rf "$TMPDIR_T019"

echo "--- Test 3: get_merge_context with missing mergeStrategy falls back ---"
TMPDIR_T019B=$(mktemp -d)
cat > "$TMPDIR_T019B/quantum.json" <<'QJSON'
{
  "execution": {},
  "progress": []
}
QJSON

CTX_FILE2=$(get_merge_context "$TMPDIR_T019B/quantum.json")
EXIT_CODE2=$?
assert_eq "get_merge_context exits 0 on missing mergeStrategy" "0" "$EXIT_CODE2"

if [[ -f "$CTX_FILE2" ]]; then
  CTX_CONTENT2=$(cat "$CTX_FILE2")
  assert_contains "fallback defaultAction is escalate" "defaultAction=escalate" "$CTX_CONTENT2"
  assert_contains "fallback has empty rules" "rules=" "$CTX_CONTENT2"
fi

rm -rf "$TMPDIR_T019B"

echo "--- Test 4: get_merge_context with empty json_path fails ---"
RESULT=$(get_merge_context "" 2>&1)
EXIT_CODE=$?
assert_eq "get_merge_context empty path returns 1" "1" "$EXIT_CODE"

echo "--- Test 5: get_merge_context with nonexistent file fails ---"
RESULT=$(get_merge_context "/tmp/nonexistent-quantum-$$.json" 2>&1)
EXIT_CODE=$?
assert_eq "get_merge_context nonexistent file returns 1" "1" "$EXIT_CODE"

echo "--- Test 6: get_merge_context with empty progress array ---"
TMPDIR_T019C=$(mktemp -d)
cat > "$TMPDIR_T019C/quantum.json" <<'QJSON'
{
  "execution": {
    "materializedContracts": [],
    "mergeStrategy": {
      "rules": [],
      "defaultAction": "ours"
    }
  },
  "progress": []
}
QJSON

CTX_FILE3=$(get_merge_context "$TMPDIR_T019C/quantum.json")
if [[ -f "$CTX_FILE3" ]]; then
  CTX_CONTENT3=$(cat "$CTX_FILE3")
  assert_contains "empty progress gives empty filesChanged" "filesChanged=" "$CTX_CONTENT3"
  assert_contains "custom defaultAction=ours" "defaultAction=ours" "$CTX_CONTENT3"
fi

rm -rf "$TMPDIR_T019C"

# =========================================================================
echo "=== T-020 Tests: classify_conflict ==="
# =========================================================================

echo "--- Test 7: classify_conflict function exists ---"
TOTAL=$((TOTAL + 1))
if type classify_conflict &>/dev/null; then
  echo "  PASS: classify_conflict is defined"
  PASS=$((PASS + 1))
else
  echo "  FAIL: classify_conflict not defined"
  FAIL=$((FAIL + 1))
fi

# Create a context file with pattern-based rules for testing
echo "--- Test 8: classify_conflict matches pattern rule ---"
TMPDIR_T020=$(mktemp -d)
cat > "$TMPDIR_T020/context.txt" <<'CTX'
defaultAction=escalate
materializedContracts=AliasRegistry|FeatureCluster
filesChanged=src/types.ts|src/index.ts|lib/common.sh
rules=[{"name":"dependency_manifest","filePattern":"package.json|package-lock.json|Cargo.toml","strategy":"ours","postAction":"install"},{"name":"barrel_export","filePattern":"**/index.ts|**/index.js|**/__init__.py","strategy":"regenerate"},{"name":"new_story_file","strategy":"theirs","condition":"file_not_on_ours"},{"name":"shared_infrastructure","strategy":"ours","condition":"file_merged_in_earlier_wave"},{"name":"contract_stub","strategy":"theirs","condition":"file_in_materializedContracts"}]
CTX

# Test pattern matching: package.json should match dependency_manifest
RESULT=$(classify_conflict "package.json" "$TMPDIR_T020/context.txt")
assert_eq "package.json -> dependency_manifest:ours:install" "dependency_manifest:ours:install" "$RESULT"

echo "--- Test 9: classify_conflict matches glob pattern ---"
RESULT=$(classify_conflict "src/components/index.ts" "$TMPDIR_T020/context.txt")
assert_eq "index.ts -> barrel_export:regenerate:" "barrel_export:regenerate:" "$RESULT"

echo "--- Test 10: classify_conflict condition file_merged_in_earlier_wave ---"
# Use a context with only the condition rule (no file_not_on_ours before it)
cat > "$TMPDIR_T020/context_wave.txt" <<'CTX'
defaultAction=escalate
materializedContracts=
filesChanged=src/types.ts|src/index.ts|lib/common.sh
rules=[{"name":"shared_infrastructure","strategy":"ours","condition":"file_merged_in_earlier_wave"}]
CTX
RESULT=$(classify_conflict "src/types.ts" "$TMPDIR_T020/context_wave.txt")
assert_eq "src/types.ts (in filesChanged) -> shared_infrastructure:ours:" "shared_infrastructure:ours:" "$RESULT"
# File NOT in filesChanged should not match
RESULT=$(classify_conflict "other/file.txt" "$TMPDIR_T020/context_wave.txt")
assert_eq "other/file.txt (not in filesChanged) -> unknown:escalate:" "unknown:escalate:" "$RESULT"

echo "--- Test 11: classify_conflict condition file_in_materializedContracts ---"
cat > "$TMPDIR_T020/context_contract.txt" <<'CTX'
defaultAction=escalate
materializedContracts=AliasRegistry|FeatureCluster
filesChanged=
rules=[{"name":"contract_stub","strategy":"theirs","condition":"file_in_materializedContracts"}]
CTX
RESULT=$(classify_conflict "AliasRegistry" "$TMPDIR_T020/context_contract.txt")
assert_eq "AliasRegistry (in materializedContracts) -> contract_stub:theirs:" "contract_stub:theirs:" "$RESULT"
# File NOT in materializedContracts should not match
RESULT=$(classify_conflict "SomeOther" "$TMPDIR_T020/context_contract.txt")
assert_eq "SomeOther (not in materializedContracts) -> unknown:escalate:" "unknown:escalate:" "$RESULT"

echo "--- Test 12: classify_conflict no match falls back to defaultAction ---"
# Use context with only pattern rules (no condition rules)
cat > "$TMPDIR_T020/context_nofallback.txt" <<'CTX'
defaultAction=escalate
materializedContracts=
filesChanged=
rules=[{"name":"dependency_manifest","filePattern":"package.json","strategy":"ours","postAction":"install"}]
CTX
RESULT=$(classify_conflict "some/random/file.go" "$TMPDIR_T020/context_nofallback.txt")
assert_eq "no match -> unknown:escalate:" "unknown:escalate:" "$RESULT"

echo "--- Test 13: classify_conflict condition file_not_on_ours ---"
# Set up a git repo to test git ls-tree behavior
TMPGIT_T020=$(mktemp -d)
git -C "$TMPGIT_T020" init -q
git -C "$TMPGIT_T020" config user.email "test@test.com"
git -C "$TMPGIT_T020" config user.name "Test"
echo "existing" > "$TMPGIT_T020/existing.txt"
git -C "$TMPGIT_T020" add existing.txt
git -C "$TMPGIT_T020" commit -m "init" -q

# A file that does not exist on HEAD should match file_not_on_ours
# Create context with only the file_not_on_ours rule
cat > "$TMPDIR_T020/context_notours.txt" <<'CTX'
defaultAction=escalate
materializedContracts=
filesChanged=
rules=[{"name":"new_story_file","strategy":"theirs","condition":"file_not_on_ours"}]
CTX

RESULT=$(cd "$TMPGIT_T020" && classify_conflict "brand_new_file.txt" "$TMPDIR_T020/context_notours.txt")
assert_eq "new file -> new_story_file:theirs:" "new_story_file:theirs:" "$RESULT"

# A file that DOES exist on HEAD should NOT match file_not_on_ours
RESULT=$(cd "$TMPGIT_T020" && classify_conflict "existing.txt" "$TMPDIR_T020/context_notours.txt")
assert_eq "existing file -> unknown:escalate:" "unknown:escalate:" "$RESULT"

rm -rf "$TMPGIT_T020"

echo "--- Test 14: classify_conflict first match wins ---"
# Create context where two rules could match
cat > "$TMPDIR_T020/context_first.txt" <<'CTX'
defaultAction=escalate
materializedContracts=package.json
filesChanged=package.json
rules=[{"name":"dependency_manifest","filePattern":"package.json","strategy":"ours","postAction":"install"},{"name":"contract_stub","strategy":"theirs","condition":"file_in_materializedContracts"}]
CTX
# package.json matches first rule by pattern, should not reach contract_stub
RESULT=$(classify_conflict "package.json" "$TMPDIR_T020/context_first.txt")
assert_eq "first match wins: pattern before condition" "dependency_manifest:ours:install" "$RESULT"

echo "--- Test 15: classify_conflict empty file_path fails ---"
RESULT=$(classify_conflict "" "$TMPDIR_T020/context.txt" 2>&1)
EXIT_CODE=$?
assert_eq "empty file_path returns 1" "1" "$EXIT_CODE"

echo "--- Test 16: classify_conflict empty context_file fails ---"
RESULT=$(classify_conflict "somefile" "" 2>&1)
EXIT_CODE=$?
assert_eq "empty context_file returns 1" "1" "$EXIT_CODE"

rm -rf "$TMPDIR_T020"

# =========================================================================
echo "=== T-021 Tests: resolve_conflict ==="
# =========================================================================

echo "--- Test 17: resolve_conflict function exists ---"
TOTAL=$((TOTAL + 1))
if type resolve_conflict &>/dev/null; then
  echo "  PASS: resolve_conflict is defined"
  PASS=$((PASS + 1))
else
  echo "  FAIL: resolve_conflict not defined"
  FAIL=$((FAIL + 1))
fi

# Set up a git repo with a merge conflict for resolve_conflict tests
TMPGIT_T021=$(mktemp -d)
git -C "$TMPGIT_T021" init -q
git -C "$TMPGIT_T021" config user.email "test@test.com"
git -C "$TMPGIT_T021" config user.name "Test"
echo "base content" > "$TMPGIT_T021/conflict.txt"
echo "base barrel" > "$TMPGIT_T021/index.ts"
git -C "$TMPGIT_T021" add .
git -C "$TMPGIT_T021" commit -m "init" -q

# Create branch with changes
git -C "$TMPGIT_T021" checkout -b feature -q
echo "feature content" > "$TMPGIT_T021/conflict.txt"
echo "feature barrel" > "$TMPGIT_T021/index.ts"
git -C "$TMPGIT_T021" add .
git -C "$TMPGIT_T021" commit -m "feature" -q

# Go back to main and create conflicting changes
git -C "$TMPGIT_T021" checkout main -q 2>/dev/null || git -C "$TMPGIT_T021" checkout master -q
echo "main content" > "$TMPGIT_T021/conflict.txt"
echo "main barrel" > "$TMPGIT_T021/index.ts"
git -C "$TMPGIT_T021" add .
git -C "$TMPGIT_T021" commit -m "main changes" -q

# Start the merge (will conflict)
git -C "$TMPGIT_T021" merge feature --no-commit --no-edit 2>/dev/null || true

echo "--- Test 18: resolve_conflict ours action ---"
(cd "$TMPGIT_T021" && resolve_conflict "conflict.txt" "ours" "" "$TMPGIT_T021")
EXIT_CODE=$?
assert_eq "resolve_conflict ours exits 0" "0" "$EXIT_CODE"
CONTENT=$(cat "$TMPGIT_T021/conflict.txt")
assert_eq "ours resolves to main content" "main content" "$CONTENT"

# Abort and redo merge for next test
git -C "$TMPGIT_T021" merge --abort 2>/dev/null || true
git -C "$TMPGIT_T021" checkout -- . 2>/dev/null || true
git -C "$TMPGIT_T021" merge feature --no-commit --no-edit 2>/dev/null || true

echo "--- Test 19: resolve_conflict theirs action ---"
(cd "$TMPGIT_T021" && resolve_conflict "conflict.txt" "theirs" "" "$TMPGIT_T021")
EXIT_CODE=$?
assert_eq "resolve_conflict theirs exits 0" "0" "$EXIT_CODE"
CONTENT=$(cat "$TMPGIT_T021/conflict.txt")
assert_eq "theirs resolves to feature content" "feature content" "$CONTENT"

echo "--- Test 20: resolve_conflict escalate action ---"
(cd "$TMPGIT_T021" && resolve_conflict "index.ts" "escalate" "" "$TMPGIT_T021")
EXIT_CODE=$?
assert_eq "resolve_conflict escalate returns 1" "1" "$EXIT_CODE"

echo "--- Test 21: resolve_conflict regenerate with unavailable barrel-regen ---"
# When BARREL_REGEN_AVAILABLE=false, regenerate should still attempt and handle gracefully
(cd "$TMPGIT_T021" && BARREL_REGEN_AVAILABLE=false resolve_conflict "index.ts" "regenerate" "" "$TMPGIT_T021")
EXIT_CODE=$?
assert_eq "resolve_conflict regenerate (unavailable) returns 1" "1" "$EXIT_CODE"

echo "--- Test 22: resolve_conflict empty file_path fails ---"
RESULT=$(resolve_conflict "" "ours" "" "$TMPGIT_T021" 2>&1)
EXIT_CODE=$?
assert_eq "resolve_conflict empty file returns 1" "1" "$EXIT_CODE"

echo "--- Test 23: resolve_conflict empty action fails ---"
RESULT=$(resolve_conflict "conflict.txt" "" "" "$TMPGIT_T021" 2>&1)
EXIT_CODE=$?
assert_eq "resolve_conflict empty action returns 1" "1" "$EXIT_CODE"

echo "--- Test 24: resolve_conflict unknown action returns 1 ---"
RESULT=$(resolve_conflict "conflict.txt" "unknown_action" "" "$TMPGIT_T021" 2>&1)
EXIT_CODE=$?
assert_eq "resolve_conflict unknown action returns 1" "1" "$EXIT_CODE"

# Clean up
git -C "$TMPGIT_T021" merge --abort 2>/dev/null || true
rm -rf "$TMPGIT_T021"

# =========================================================================
echo "=== T-022 Tests: classify_and_merge ==="
# =========================================================================

echo "--- Test 25: classify_and_merge function exists ---"
TOTAL=$((TOTAL + 1))
if type classify_and_merge &>/dev/null; then
  echo "  PASS: classify_and_merge is defined"
  PASS=$((PASS + 1))
else
  echo "  FAIL: classify_and_merge not defined"
  FAIL=$((FAIL + 1))
fi

# Helper: set up a repo with a quantum.json for classify_and_merge tests
setup_cam_repo() {
  local repo_dir
  repo_dir=$(mktemp -d)
  git -C "$repo_dir" init -q
  git -C "$repo_dir" config user.email "test@test.com"
  git -C "$repo_dir" config user.name "Test"
  echo "base" > "$repo_dir/shared.txt"
  echo "base lock" > "$repo_dir/package.json"
  # Create quantum.json with mergeStrategy
  cat > "$repo_dir/quantum.json" <<'QJSON'
{
  "execution": {
    "materializedContracts": [],
    "mergeStrategy": {
      "rules": [
        {"name":"dependency_manifest","filePattern":"package.json","strategy":"ours","postAction":"install"},
        {"name":"new_story_file","strategy":"theirs","condition":"file_not_on_ours"}
      ],
      "defaultAction": "escalate"
    }
  },
  "progress": []
}
QJSON
  git -C "$repo_dir" add .
  git -C "$repo_dir" commit -m "init" -q
  echo "$repo_dir"
}

echo "--- Test 26: classify_and_merge clean merge ---"
CAM_REPO=$(setup_cam_repo)
MAIN_BRANCH=$(git -C "$CAM_REPO" branch --show-current)

# Create a worktree branch with non-conflicting changes
git -C "$CAM_REPO" checkout -b wt-clean -q
echo "new file" > "$CAM_REPO/newfile.txt"
git -C "$CAM_REPO" add newfile.txt
git -C "$CAM_REPO" commit -m "add newfile" -q

# Back to main
git -C "$CAM_REPO" checkout "$MAIN_BRANCH" -q

OUTPUT=$(classify_and_merge "wt-clean" "$CAM_REPO" "$CAM_REPO/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "clean merge exits 0" "0" "$EXIT_CODE"

# Verify merge commit happened
TOTAL=$((TOTAL + 1))
if [[ -f "$CAM_REPO/newfile.txt" ]]; then
  echo "  PASS: merged file exists after clean merge"
  PASS=$((PASS + 1))
else
  echo "  FAIL: merged file missing after clean merge"
  FAIL=$((FAIL + 1))
fi

rm -rf "$CAM_REPO"

echo "--- Test 27: classify_and_merge resolves ours conflict ---"
CAM_REPO2=$(setup_cam_repo)
MAIN_BRANCH2=$(git -C "$CAM_REPO2" branch --show-current)

# Create worktree branch with conflicting package.json
git -C "$CAM_REPO2" checkout -b wt-conflict -q
echo "worktree lock" > "$CAM_REPO2/package.json"
git -C "$CAM_REPO2" add package.json
git -C "$CAM_REPO2" commit -m "worktree pkg" -q

# Back to main, make conflicting change
git -C "$CAM_REPO2" checkout "$MAIN_BRANCH2" -q
echo "main lock" > "$CAM_REPO2/package.json"
git -C "$CAM_REPO2" add package.json
git -C "$CAM_REPO2" commit -m "main pkg" -q

OUTPUT=$(classify_and_merge "wt-conflict" "$CAM_REPO2" "$CAM_REPO2/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "ours conflict resolution exits 0" "0" "$EXIT_CODE"

# package.json should be ours (main) version
CONTENT=$(cat "$CAM_REPO2/package.json")
assert_eq "package.json resolved to ours" "main lock" "$CONTENT"

# Check log output contains timing
assert_contains "log has timing" "Merge completed in" "$OUTPUT"

rm -rf "$CAM_REPO2"

echo "--- Test 28: classify_and_merge escalates on unresolvable conflict ---"
CAM_REPO3=$(setup_cam_repo)
MAIN_BRANCH3=$(git -C "$CAM_REPO3" branch --show-current)

# Create conflict on shared.txt which has no matching rule -> defaultAction=escalate
git -C "$CAM_REPO3" checkout -b wt-escalate -q
echo "worktree shared" > "$CAM_REPO3/shared.txt"
git -C "$CAM_REPO3" add shared.txt
git -C "$CAM_REPO3" commit -m "worktree shared" -q

git -C "$CAM_REPO3" checkout "$MAIN_BRANCH3" -q
echo "main shared" > "$CAM_REPO3/shared.txt"
git -C "$CAM_REPO3" add shared.txt
git -C "$CAM_REPO3" commit -m "main shared" -q

OUTPUT=$(classify_and_merge "wt-escalate" "$CAM_REPO3" "$CAM_REPO3/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "escalation returns 1" "1" "$EXIT_CODE"
assert_contains "output has CONFLICT line" "CONFLICT:" "$OUTPUT"

# Merge should be aborted -- working tree clean
STATUS=$(git -C "$CAM_REPO3" status --porcelain)
assert_eq "working tree clean after abort" "" "$STATUS"

rm -rf "$CAM_REPO3"

echo "--- Test 29: classify_and_merge with new file (theirs via file_not_on_ours) ---"
CAM_REPO4=$(setup_cam_repo)
MAIN_BRANCH4=$(git -C "$CAM_REPO4" branch --show-current)

# Create worktree branch that adds a brand new file AND conflicts on shared.txt
git -C "$CAM_REPO4" checkout -b wt-newfile -q
echo "brand new" > "$CAM_REPO4/brand_new.txt"
echo "worktree shared" > "$CAM_REPO4/shared.txt"
git -C "$CAM_REPO4" add .
git -C "$CAM_REPO4" commit -m "add new and change shared" -q

# Main changes shared.txt too
git -C "$CAM_REPO4" checkout "$MAIN_BRANCH4" -q
echo "main shared" > "$CAM_REPO4/shared.txt"
git -C "$CAM_REPO4" add shared.txt
git -C "$CAM_REPO4" commit -m "main shared" -q

# shared.txt has no matching rule -> escalate. brand_new.txt should match file_not_on_ours
# But shared.txt escalation causes abort
OUTPUT=$(classify_and_merge "wt-newfile" "$CAM_REPO4" "$CAM_REPO4/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "mixed conflict with escalation returns 1" "1" "$EXIT_CODE"

rm -rf "$CAM_REPO4"

echo "--- Test 30: classify_and_merge empty worktree_branch fails ---"
CAM_REPO5=$(setup_cam_repo)
RESULT=$(classify_and_merge "" "$CAM_REPO5" "$CAM_REPO5/quantum.json" 2>&1)
EXIT_CODE=$?
assert_eq "empty worktree_branch returns 1" "1" "$EXIT_CODE"
rm -rf "$CAM_REPO5"

echo "--- Test 31: classify_and_merge logs resolved count ---"
CAM_REPO6=$(setup_cam_repo)
MAIN_BRANCH6=$(git -C "$CAM_REPO6" branch --show-current)

git -C "$CAM_REPO6" checkout -b wt-resolved -q
echo "wt lock" > "$CAM_REPO6/package.json"
git -C "$CAM_REPO6" add package.json
git -C "$CAM_REPO6" commit -m "wt pkg" -q

git -C "$CAM_REPO6" checkout "$MAIN_BRANCH6" -q
echo "main lock2" > "$CAM_REPO6/package.json"
git -C "$CAM_REPO6" add package.json
git -C "$CAM_REPO6" commit -m "main pkg2" -q

OUTPUT=$(classify_and_merge "wt-resolved" "$CAM_REPO6" "$CAM_REPO6/quantum.json" 2>&1)
assert_contains "log has Resolved count" "Resolved" "$OUTPUT"

rm -rf "$CAM_REPO6"

# =========================================================================
echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ $FAIL -eq 0 ]]; then
  exit 0
else
  exit 1
fi
