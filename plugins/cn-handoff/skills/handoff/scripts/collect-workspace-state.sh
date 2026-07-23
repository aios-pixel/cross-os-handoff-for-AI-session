#!/usr/bin/env bash
set -euo pipefail

requested_path=${1:-.}
if [[ -d "$requested_path" ]]; then
  resolved_path=$(cd "$requested_path" && pwd -P)
else
  resolved_path=$(cd "$(dirname "$requested_path")" && pwd -P)
fi

git_available=false
is_git_repository=false
workspace_root=$resolved_path
branch=""
head=""
upstream=""
upstream_head=""
ahead=""
behind=""
remote_count=0
staged_count=0
unstaged_count=0
untracked_count=0
conflict_count=0
git_status_available=false
worktree_count=0
nested_repository_count=0

stop_collector() {
  printf 'collector_error=%s\n' "$1" >&2
  exit 2
}

if command -v git >/dev/null 2>&1; then
  git_available=true
  if root_candidate=$(git -C "$resolved_path" rev-parse --show-toplevel 2>/dev/null); then
    is_git_repository=true
    workspace_root=$(cd "$root_candidate" && pwd -P)
    branch=$(git -C "$workspace_root" branch --show-current 2>/dev/null) || stop_collector "git_branch_unavailable"
    [[ -n "$branch" ]] || branch="DETACHED"
    head=$(git -C "$workspace_root" rev-parse HEAD 2>/dev/null) || stop_collector "git_head_unavailable"

    if upstream=$(git -C "$workspace_root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
      upstream_head=$(git -C "$workspace_root" rev-parse '@{u}' 2>/dev/null) || stop_collector "git_upstream_head_unavailable"
      ahead_behind=$(git -C "$workspace_root" rev-list --left-right --count 'HEAD...@{u}' 2>/dev/null) || stop_collector "git_drift_unavailable"
      ahead=$(printf '%s\n' "$ahead_behind" | awk 'NR == 1 { print $1 }')
      behind=$(printf '%s\n' "$ahead_behind" | awk 'NR == 1 { print $2 }')
      [[ "$ahead" =~ ^[0-9]+$ && "$behind" =~ ^[0-9]+$ ]] || stop_collector "git_drift_invalid"
    else
      upstream=""
      if [[ "$branch" != "DETACHED" ]]; then
        set +e
        configured_remote=$(git -C "$workspace_root" config --get "branch.$branch.remote" 2>/dev/null)
        configured_remote_status=$?
        configured_merge=$(git -C "$workspace_root" config --get "branch.$branch.merge" 2>/dev/null)
        configured_merge_status=$?
        set -e
        (( configured_remote_status <= 1 && configured_merge_status <= 1 )) || stop_collector "git_config_unavailable"
        if [[ -n "$configured_remote" || -n "$configured_merge" ]]; then
          stop_collector "git_upstream_unavailable"
        fi
      fi
    fi

    remote_output=$(git -C "$workspace_root" remote 2>/dev/null) || stop_collector "git_remote_unavailable"
    remote_count=$(printf '%s\n' "$remote_output" | awk 'NF { n++ } END { print n + 0 }')
    worktree_output=$(git -C "$workspace_root" worktree list --porcelain 2>/dev/null) || stop_collector "git_worktree_unavailable"
    worktree_count=$(printf '%s\n' "$worktree_output" | awk '$1 == "worktree" { n++ } END { print n + 0 }')

    status_output=$(git -C "$workspace_root" status --porcelain=v1 2>/dev/null) || stop_collector "git_status_unavailable"
    git_status_available=true
    untracked_count=$(printf '%s\n' "$status_output" | awk 'substr($0, 1, 2) == "??" { n++ } END { print n + 0 }')
    conflict_count=$(printf '%s\n' "$status_output" | awk '
      BEGIN { conflict["DD"]; conflict["AU"]; conflict["UD"]; conflict["UA"]; conflict["DU"]; conflict["AA"]; conflict["UU"] }
      substr($0, 1, 2) in conflict { n++ }
      END { print n + 0 }
    ')
    staged_count=$(printf '%s\n' "$status_output" | awk 'substr($0, 1, 2) != "??" && substr($0, 1, 1) != " " { n++ } END { print n + 0 }')
    unstaged_count=$(printf '%s\n' "$status_output" | awk 'substr($0, 1, 2) != "??" && substr($0, 2, 1) != " " { n++ } END { print n + 0 }')

    nested_repository_count=$(find "$workspace_root" -mindepth 1 \
      -path "$workspace_root/.git" -prune -o \
      -name .git -print -prune 2>/dev/null | awk 'END { print NR + 0 }') || stop_collector "nested_repository_scan_failed"
  fi
fi

json_escape() {
  local value=${1-}
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

json_nullable_string() {
  if [[ -n "${1-}" ]]; then
    printf '"%s"' "$(json_escape "$1")"
  else
    printf 'null'
  fi
}

json_nullable_number() {
  if [[ -n "${1-}" ]]; then
    printf '%d' "$1"
  else
    printf 'null'
  fi
}

file_mtime() {
  if stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$1" >/dev/null 2>&1; then
    stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$1"
  else
    stat -c '%y' "$1"
  fi
}

file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    sha256sum "$1" | awk '{ print $1 }'
  fi
}

entry_names=(
  AGENTS.md AGENT.md CLAUDE.md HANDOFF_交班.md HANDOFF_交班.html
  HANDOFF.md SESSION.md SESSION.html PROJECT.md STATUS.md RESULTS.md TODO.md README.md
)
entry_json=""
entry_count=0
for entry_name in "${entry_names[@]}"; do
  candidate="$workspace_root/$entry_name"
  [[ -f "$candidate" ]] || continue
  [[ $entry_count -eq 0 ]] || entry_json+=","
  length=$(wc -c < "$candidate" | tr -d ' ')
  mtime=$(file_mtime "$candidate")
  sha=$(file_sha256 "$candidate")
  entry_json+="{\"Name\":\"$(json_escape "$entry_name")\",\"Path\":\"$(json_escape "$entry_name")\",\"Length\":$length,\"LastWriteTime\":\"$(json_escape "$mtime")\",\"Sha256\":\"$sha\"}"
  entry_count=$((entry_count + 1))
done

top_level_entry_count=$(find "$workspace_root" -mindepth 1 -maxdepth 1 -print 2>/dev/null | awk 'END { print NR + 0 }') || stop_collector "top_level_scan_failed"
repository_name=$(basename "$workspace_root")
collected_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
is_dirty=null
if [[ "$git_status_available" == true ]]; then
  is_dirty=false
  if (( staged_count + unstaged_count + untracked_count + conflict_count > 0 )); then
    is_dirty=true
  fi
fi

printf '{'
printf '"SchemaVersion":3,'
printf '"CollectedAt":"%s",' "$(json_escape "$collected_at")"
printf '"RequestedPath":"<WORKSPACE_ROOT>","WorkspaceRoot":"<WORKSPACE_ROOT>",'
printf '"RepositoryName":"%s",' "$(json_escape "$repository_name")"
printf '"IsGitRepository":%s,"GitAvailable":%s,' "$is_git_repository" "$git_available"
printf '"Branch":'; json_nullable_string "$branch"; printf ','
printf '"Head":'; json_nullable_string "$head"; printf ','
printf '"Upstream":'; json_nullable_string "$upstream"; printf ','
printf '"UpstreamHead":'; json_nullable_string "$upstream_head"; printf ','
printf '"Ahead":'; json_nullable_number "$ahead"; printf ','
printf '"Behind":'; json_nullable_number "$behind"; printf ','
printf '"RemoteCount":%d,' "$remote_count"
if [[ "$git_status_available" == true ]]; then
  printf '"GitStatus":{"Available":true,"IsDirty":%s,"Staged":%d,"Unstaged":%d,"Untracked":%d,"Conflicts":%d},' "$is_dirty" "$staged_count" "$unstaged_count" "$untracked_count" "$conflict_count"
else
  printf '"GitStatus":{"Available":false,"IsDirty":null,"Staged":null,"Unstaged":null,"Untracked":null,"Conflicts":null},'
fi
printf '"WorktreeCount":%d,"NestedRepositoryCount":%d,' "$worktree_count" "$nested_repository_count"
printf '"EntryFiles":[%s],"TopLevelEntryCount":%d' "$entry_json" "$top_level_entry_count"
printf '}\n'
