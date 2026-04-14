#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if command -v fnm >/dev/null 2>&1; then eval "$(fnm env --use-on-cd 2>/dev/null || fnm env 2>/dev/null)"; fi
export PYTHONDONTWRITEBYTECODE=1
export GH_PROMPT_DISABLED=1
export GIT_PAGER=cat

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

ORG_SLUG="${ORG_SLUG:-veritykernel}"
MQ_REPO="${MQ_REPO:-$ORG_SLUG/prime-canon-artifact-pack-mq-validation}"
SOURCE_BRANCH="${SOURCE_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%d%H%M%S)}"
WORKFLOW_FILE="publish-guard-check.yml"
WORKFLOW_NAME="publish-guard-check"
PROOF_BRANCH="cycle-2/mq-proof-$RUN_ID"
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
WAIT_STATUS=""
WAIT_CONCLUSION=""
WAIT_RUN_URL=""
WAIT_SEEN="false"

cleanup() {
  git checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || true
  if git show-ref --verify --quiet "refs/heads/$PROOF_BRANCH"; then
    git branch -D "$PROOF_BRANCH" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

wait_for_run() {
  local repo="$1"
  local workflow="$2"
  local branch="$3"
  local event="$4"
  local head_sha="$5"
  local loops="$6"

  WAIT_STATUS=""
  WAIT_CONCLUSION=""
  WAIT_RUN_URL=""
  WAIT_SEEN="false"

  for _ in $(seq 1 "$loops"); do
    local args=(run list --repo "$repo" --workflow "$workflow" --event "$event" --json status,conclusion,headSha,url --limit 20)
    if [ -n "$branch" ]; then
      args+=(--branch "$branch")
    fi

    RUN_JSON="$(gh "${args[@]}" 2>/dev/null || echo '[]')"

    WAIT_STATUS="$(python3 - <<'PY' "$RUN_JSON" "$head_sha"
import json, sys
runs = json.loads(sys.argv[1])
head = sys.argv[2]
found = None
if head:
    for run in runs:
        if run.get("headSha") == head:
            found = run
            break
else:
    if runs:
        found = runs[0]
print(found.get("status","") if found else "")
PY
)"
    WAIT_CONCLUSION="$(python3 - <<'PY' "$RUN_JSON" "$head_sha"
import json, sys
runs = json.loads(sys.argv[1])
head = sys.argv[2]
found = None
if head:
    for run in runs:
        if run.get("headSha") == head:
            found = run
            break
else:
    if runs:
        found = runs[0]
print(found.get("conclusion","") if found else "")
PY
)"
    WAIT_RUN_URL="$(python3 - <<'PY' "$RUN_JSON" "$head_sha"
import json, sys
runs = json.loads(sys.argv[1])
head = sys.argv[2]
found = None
if head:
    for run in runs:
        if run.get("headSha") == head:
            found = run
            break
else:
    if runs:
        found = runs[0]
print(found.get("url","") if found else "")
PY
)"

    if [ -n "${WAIT_STATUS:-}" ]; then
      WAIT_SEEN="true"
    fi

    echo "$event $workflow branch=${branch:-any} status=${WAIT_STATUS:-none} conclusion=${WAIT_CONCLUSION:-none}"

    if [ "$WAIT_STATUS" = "completed" ]; then
      break
    fi

    sleep 5
  done

  if [ "$WAIT_SEEN" != "true" ]; then
    return 10
  fi

  if [ "$WAIT_STATUS" != "completed" ] || [ "$WAIT_CONCLUSION" != "success" ]; then
    return 11
  fi

  return 0
}

wait_for_new_merge_group_run() {
  local repo="$1"
  local workflow="$2"
  local after_id="$3"
  local loops="$4"

  WAIT_STATUS=""
  WAIT_CONCLUSION=""
  WAIT_RUN_URL=""
  WAIT_SEEN="false"

  for _ in $(seq 1 "$loops"); do
    RUN_JSON="$(gh api "repos/$repo/actions/runs?event=merge_group&per_page=20" 2>/dev/null || echo '{"workflow_runs": []}')"

    WAIT_STATUS="$(python3 - <<'PY' "$RUN_JSON" "$after_id" "$workflow"
import json, sys
data = json.loads(sys.argv[1])
after_id = int(sys.argv[2])
workflow = sys.argv[3]
runs = data.get("workflow_runs", [])
found = None
for run in runs:
    if run.get("name") == workflow and int(run.get("id", 0)) > after_id:
        found = run
        break
print(found.get("status","") if found else "")
PY
)"
    WAIT_CONCLUSION="$(python3 - <<'PY' "$RUN_JSON" "$after_id" "$workflow"
import json, sys
data = json.loads(sys.argv[1])
after_id = int(sys.argv[2])
workflow = sys.argv[3]
runs = data.get("workflow_runs", [])
found = None
for run in runs:
    if run.get("name") == workflow and int(run.get("id", 0)) > after_id:
        found = run
        break
print(found.get("conclusion","") if found else "")
PY
)"
    WAIT_RUN_URL="$(python3 - <<'PY' "$RUN_JSON" "$after_id" "$workflow"
import json, sys
data = json.loads(sys.argv[1])
after_id = int(sys.argv[2])
workflow = sys.argv[3]
runs = data.get("workflow_runs", [])
found = None
for run in runs:
    if run.get("name") == workflow and int(run.get("id", 0)) > after_id:
        found = run
        break
print(found.get("html_url","") if found else "")
PY
)"

    if [ -n "${WAIT_STATUS:-}" ]; then
      WAIT_SEEN="true"
    fi

    echo "merge_group $workflow status=${WAIT_STATUS:-none} conclusion=${WAIT_CONCLUSION:-none}"

    if [ "$WAIT_STATUS" = "completed" ]; then
      break
    fi

    sleep 5
  done

  if [ "$WAIT_SEEN" != "true" ]; then
    return 10
  fi

  if [ "$WAIT_STATUS" != "completed" ] || [ "$WAIT_CONCLUSION" != "success" ]; then
    return 11
  fi

  return 0
}

gh auth status

if ! gh repo view "$MQ_REPO" >/dev/null 2>&1; then
  gh repo create "$MQ_REPO" --public >/dev/null
fi

if git remote get-url mq >/dev/null 2>&1; then
  git remote set-url mq "https://github.com/$MQ_REPO.git"
else
  git remote add mq "https://github.com/$MQ_REPO.git"
fi

gh api --method PUT -H "Accept: application/vnd.github+json" "repos/$MQ_REPO/actions/permissions" -f enabled=true -f allowed_actions=all >/dev/null 2>&1 || true
gh workflow enable "$WORKFLOW_FILE" --repo "$MQ_REPO" >/dev/null 2>&1 || true

MAIN_SHA="$(git rev-parse "$SOURCE_BRANCH")"

if git ls-remote --exit-code --heads mq main >/dev/null 2>&1; then
  git fetch --no-tags mq refs/heads/main:refs/remotes/mq/main
  REMOTE_MAIN_SHA="$(git rev-parse refs/remotes/mq/main)"
  git push --force-with-lease=refs/heads/main:$REMOTE_MAIN_SHA mq "$SOURCE_BRANCH:refs/heads/main"
else
  git push mq "$SOURCE_BRANCH:refs/heads/main"
fi

gh api --method PATCH "repos/$MQ_REPO" -f default_branch=main >/dev/null

if wait_for_run "$MQ_REPO" "$WORKFLOW_FILE" "main" "push" "$MAIN_SHA" 36; then
  :
else
  code="$?"
  if [ "$code" = "10" ]; then
    echo "no push run was created on main for $MQ_REPO"
    exit 1
  fi
  echo "main push workflow did not succeed in $MQ_REPO"
  echo "run_url=${WAIT_RUN_URL:-none}"
  exit 1
fi

git checkout -B "$PROOF_BRANCH" "$SOURCE_BRANCH"
git commit --allow-empty -m "mq proof trigger $RUN_ID"
PR_HEAD_SHA="$(git rev-parse HEAD)"
git push mq "$PROOF_BRANCH"

if wait_for_run "$MQ_REPO" "$WORKFLOW_FILE" "$PROOF_BRANCH" "push" "$PR_HEAD_SHA" 36; then
  :
else
  code="$?"
  if [ "$code" = "10" ]; then
    echo "no push run was created on proof branch $PROOF_BRANCH"
    exit 1
  fi
  echo "proof branch push workflow did not succeed in $MQ_REPO"
  echo "run_url=${WAIT_RUN_URL:-none}"
  exit 1
fi

cat > /tmp/prime_canon_merge_queue_ruleset.json <<'JSON'
{
  "name": "required-ci-publish-guard-main-mq",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          {
            "context": "publish-guard-check"
          }
        ],
        "strict_required_status_checks_policy": true
      }
    },
    {
      "type": "merge_queue",
      "parameters": {
        "check_response_timeout_minutes": 30,
        "grouping_strategy": "HEADGREEN",
        "max_entries_to_build": 1,
        "max_entries_to_merge": 1,
        "merge_method": "SQUASH",
        "min_entries_to_merge": 1,
        "min_entries_to_merge_wait_minutes": 0
      }
    }
  ]
}
JSON

RULESET_ID="$(gh api "repos/$MQ_REPO/rulesets" --jq '.[] | select(.name=="required-ci-publish-guard-main-mq") | .id' 2>/dev/null | head -n1 || true)"
if [ -n "${RULESET_ID:-}" ]; then
  gh api --method PUT -H "Accept: application/vnd.github+json" "repos/$MQ_REPO/rulesets/$RULESET_ID" --input /tmp/prime_canon_merge_queue_ruleset.json >/dev/null
else
  gh api --method POST -H "Accept: application/vnd.github+json" "repos/$MQ_REPO/rulesets" --input /tmp/prime_canon_merge_queue_ruleset.json >/dev/null
fi

if gh pr view --repo "$MQ_REPO" "$PROOF_BRANCH" >/dev/null 2>&1; then
  :
else
  gh pr create --repo "$MQ_REPO" --base main --head "$PROOF_BRANCH" --title "mq proof $RUN_ID" --body "Deterministic merge queue proof for publish-guard-check." >/dev/null
fi

PR_JSON="$(gh pr view --repo "$MQ_REPO" "$PROOF_BRANCH" --json number,url,headRefOid)"
export PR_JSON
PR_NUMBER="$(python3 - <<'PY'
import json, os
print(json.loads(os.environ["PR_JSON"])["number"])
PY
)"
PR_URL="$(python3 - <<'PY'
import json, os
print(json.loads(os.environ["PR_JSON"])["url"])
PY
)"
PR_HEAD_SHA="$(python3 - <<'PY'
import json, os
print(json.loads(os.environ["PR_JSON"])["headRefOid"])
PY
)"

echo "mq_repo=$MQ_REPO"
echo "pr_number=$PR_NUMBER"
echo "pr_url=$PR_URL"

if wait_for_run "$MQ_REPO" "$WORKFLOW_FILE" "$PROOF_BRANCH" "pull_request" "$PR_HEAD_SHA" 36; then
  :
else
  code="$?"
  if [ "$code" = "10" ]; then
    echo "no pull_request run was created for PR #$PR_NUMBER"
    exit 1
  fi
  echo "pull_request workflow did not succeed for PR #$PR_NUMBER"
  echo "run_url=${WAIT_RUN_URL:-none}"
  exit 1
fi

BEFORE_MG_ID="$(gh api "repos/$MQ_REPO/actions/runs?event=merge_group&per_page=1" 2>/dev/null | python3 - <<'PY'
import json, sys
data = json.load(sys.stdin)
runs = data.get("workflow_runs", [])
print(runs[0]["id"] if runs else 0)
PY
)"

gh pr merge --repo "$MQ_REPO" "$PROOF_BRANCH" --squash --match-head-commit "$PR_HEAD_SHA"

if wait_for_new_merge_group_run "$MQ_REPO" "$WORKFLOW_NAME" "$BEFORE_MG_ID" 48; then
  :
else
  code="$?"
  if [ "$code" = "10" ]; then
    echo "no new merge_group run was created in $MQ_REPO"
    exit 1
  fi
  echo "merge_group $WORKFLOW_NAME did not complete successfully in $MQ_REPO"
  echo "run_url=${WAIT_RUN_URL:-none}"
  exit 1
fi

echo "merge_queue_proof=success"
echo "repo=$MQ_REPO"
echo "pr_number=$PR_NUMBER"
echo "pr_url=$PR_URL"
echo "merge_group_run_url=$WAIT_RUN_URL"
