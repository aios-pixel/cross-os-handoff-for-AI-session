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
remote_count=0
staged_count=0
unstaged_count=0
untracked_count=0
conflict_count=0
worktree_count=0
nested_repository_count=0

if command -v git >/dev/null 2>&1; then
  git_available=true
  if root_candidate=$(git -C "$resolved_path" rev-parse --show-toplevel 2>/dev/null); then
    is_git_repository=true
    workspace_root=$(cd "$root_candidate" && pwd -P)
    branch=$(git -C "$workspace_root" branch --show-current 2>/dev/null || true)
    [[ -n "$branch" ]] || branch="DETACHED"
    head=$(git -C "$workspace_root" rev-parse HEAD 2>/dev/null || true)
    upstream=$(git -C "$workspace_root" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    remote_count=$(git -C "$workspace_root" remote 2>/dev/null | awk 'END { print NR + 0 }')
    worktree_count=$(git -C "$workspace_root" worktree list --porcelain 2>/dev/null | awk '$1 == "worktree" { n++ } END { print n + 0 }')

    while IFS= read -r status_line; do
      [[ -n "$status_line" ]] || continue
      code=${status_line:0:2}
      if [[ "$code" == "??" ]]; then
        untracked_count=$((untracked_count + 1))
        continue
      fi
      case "$code" in
        DD|AU|UD|UA|DU|AA|UU) conflict_count=$((conflict_count + 1)) ;;
      esac
      [[ "${code:0:1}" == " " ]] || staged_count=$((staged_count + 1))
      [[ "${code:1:1}" == " " ]] || unstaged_count=$((unstaged_count + 1))
    done < <(git -C "$workspace_root" status --porcelain=v1 2>/dev/null || true)

    nested_repository_count=$(find "$workspace_root" -mindepth 2 -maxdepth 2 -name .git -print 2>/dev/null | awk 'END { print NR + 0 }')
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

top_level_entry_count=$(find "$workspace_root" -mindepth 1 -maxdepth 1 -print 2>/dev/null | awk 'END { print NR + 0 }')
repository_name=$(basename "$workspace_root")
collected_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
is_dirty=false
if (( staged_count + unstaged_count + untracked_count + conflict_count > 0 )); then
  is_dirty=true
fi

printf '{'
printf '"SchemaVersion":2,'
printf '"CollectedAt":"%s",' "$(json_escape "$collected_at")"
printf '"RequestedPath":"<WORKSPACE_ROOT>","WorkspaceRoot":"<WORKSPACE_ROOT>",'
printf '"RepositoryName":"%s",' "$(json_escape "$repository_name")"
printf '"IsGitRepository":%s,"GitAvailable":%s,' "$is_git_repository" "$git_available"
printf '"Branch":"%s","Head":"%s","Upstream":"%s",' "$(json_escape "$branch")" "$(json_escape "$head")" "$(json_escape "$upstream")"
printf '"RemoteCount":%d,' "$remote_count"
printf '"GitStatus":{"IsDirty":%s,"Staged":%d,"Unstaged":%d,"Untracked":%d,"Conflicts":%d},' "$is_dirty" "$staged_count" "$unstaged_count" "$untracked_count" "$conflict_count"
printf '"WorktreeCount":%d,"NestedRepositoryCount":%d,' "$worktree_count" "$nested_repository_count"
printf '"EntryFiles":[%s],"TopLevelEntryCount":%d' "$entry_json" "$top_level_entry_count"
printf '}\n'
