---
name: handoff
description: Create, finalize, and resume verified project handoffs. Use whenever the user says `handoff 交班`, `handoff 任務後交班`, `handoff 接班`, `/handoff`, or `/handoff 接班`; asks to hand off or resume a project; requests context reconstruction; wants a new Codex task or host to continue prior work; or explicitly asks for handoff after another task finishes. Exact commands trigger their complete workflows without requiring the user to restate project details.
---

# Handoff

Reconstruct project context from verified files and Git state. Never treat a new task as the same session or rely on hidden conversation state.

## Contract version

- Skill version: `2.1.2`
- Handoff schema: `3`
- Durable state: project files and Git artifacts
- Conversation transcripts and model memory: supplementary evidence only

## Invocation contract

- `handoff 交班` or `/handoff`: run the full handoff workflow in the requested workspace. Authorize only project status and handoff-file writes.
- `handoff 任務後交班`: finish the other explicitly authorized task and proportional QA first, then run the full handoff workflow against the resulting workspace.
- `handoff 接班` or `/handoff 接班`: run the full resume workflow. Keep it read-only and stop after reporting the reconstructed state.
- When the user supplies a path, use it instead of the current working directory.
- Finish handoff or resume verification before any separately authorized follow-up action.
- Discover safely available facts from the live workspace; do not ask the user to repeat them.

## Shared rules

1. Treat the live filesystem, Git state, authoritative artifacts, and actual contents as primary evidence.
2. Read every applicable `AGENTS.md` completely. Apply root guidance first and nested guidance within its subtree.
3. Preserve unrelated changes. Never clean, reset, discard, stage, commit, pull, push, deploy, publish, or perform external actions unless separately authorized.
4. Never store credentials, tokens, cookies, OAuth paths, private keys, personal account details, hostnames, device names, IP addresses, or secret-bearing output in handoff files.
5. Replace user-home prefixes with `<USER_HOME>`. Prefer repository-relative paths and generic host roles such as `source-host` and `destination-host`.
6. Mark missing evidence as `未找到`, `尚待驗證`, or the project-required equivalent. Never convert assumptions into facts.
7. Record superseded claims so a future task cannot revive them accidentally.
8. Prefer targeted inspection. Scan the top level, then follow explicit authority pointers.
9. Use the matching artifact skill for spreadsheets, documents, PDFs, presentations, sites, databases, or other specialized formats.
10. Do not browse during handoff unless the user or project instructions require current external verification.
11. A handoff command does not synchronize hosts. Git commit, push, fetch, pull, merge, and conflict resolution require separate authorization.
12. When `session-updater` also applies, let it record interim milestones in the same `SESSION.md`. During handoff, revalidate the complete file and keep `SESSION.md` as the single current-state authority; never create a competing session-status file.

## Establish the real workspace

Run the bundled collector before interpreting status:

- Windows PowerShell: `scripts/collect-workspace-state.ps1 -Path <workspace>`
- macOS／Linux: `scripts/collect-workspace-state.sh <workspace>`

Both collectors are read-only, emit schema `3`, redact absolute paths, fail closed when critical Git evidence cannot be collected, and return the same core fields. Inspect additional details only when necessary.

Confirm:

- requested workspace and actual Git root;
- branch, HEAD, upstream ref and commit, ahead／behind counts, verified dirty-state counts, worktree count, and recursive nested-repository count;
- applicable `AGENTS.md` and status-file presence;
- whether the supplied folder is only a shell and the actual work is adjacent or referenced;
- whether source and destination hosts resolve the same repository identity and expected commit.

Trust verified filesystem evidence when an environment description disagrees.

## Mode: `handoff 任務後交班`

1. Perform only the non-handoff work explicitly authorized in the same request.
2. Complete relevant tests, renders, scans, readbacks, or other proportional QA.
3. Run `handoff 交班` against the resulting workspace.
4. If work fails or remains incomplete, record the actual partial state and next recovery action without claiming completion.
5. If no material project state changed and existing status files remain accurate, verify them without cosmetic timestamp churn.
6. Report the task outcome first, then the handoff state, unresolved gaps, next exact deliverable, contradictions, and QA.

## Mode: `handoff 交班`

### Authorization boundary

Write only the minimum files needed to preserve project state. Reuse project conventions. If none exist, use:

- `SESSION.md`: complete current-state authority.
- `HANDOFF_交班.md`: minimal resume entrypoint.

If project instructions require HTML twins for non-code Markdown, update the matching HTML files within the same handoff write set. Do not change business artifacts, source code, configuration, or Git history merely to prepare handoff.

### Read before writing

1. Read applicable `AGENTS.md` files completely.
2. Read existing handoff and status files completely.
3. Read the root README and authority index referenced by status files.
4. Inspect Git status and diffs; distinguish pre-existing user changes from current-task changes.
5. Inspect actual outputs needed to verify the current conclusion.
6. Verify recorded paths, commits, hashes, counts, key figures, deployment claims, and next steps.

### Maintain `SESSION.md`

Make it the complete current-state document, not a transcript. Include when applicable:

1. Schema version, date, time zone, repository identity, branch, HEAD, upstream, and dirty-state summary.
2. Project purpose and current governing conclusion.
3. Authority and version hierarchy with repository-relative paths.
4. Verified current facts, each traceable to an artifact.
5. Completed work and actual verification performed.
6. Decisions and rationale.
7. Superseded and prohibited claims.
8. Unfinished work, model gaps, blockers, and dependencies.
9. External-state boundary: live-verified, locally verified, previously verified, announced, assumed, or not reverified.
10. One next exact deliverable with scope, required inputs, completion standard, and actions awaiting review.
11. Git and artifact governance, including whether anything was staged, committed, pushed, or deployed.
12. Operating and context boundaries.

Do not include full transcripts, raw logs, screenshots, secrets, absolute home paths, hostnames, IP addresses, or obsolete implementation details recoverable from Git.

### Maintain `HANDOFF_交班.md`

Keep it short enough for a new task to read first. Include:

1. Schema version, update date, project identity, and purpose.
2. Exact minimum reading order.
3. One-sentence current status.
4. Authority files and primary artifact paths.
5. Critical verified anchors.
6. Prohibited or superseded claims.
7. Gaps and blockers.
8. Next exact deliverable and definition of done.
9. Git and nested-repository status.
10. Operating and context boundaries.

Point to `SESSION.md` instead of duplicating detail.

### Handoff QA

1. Re-read both state files completely.
2. Confirm authority order, figures, paths, statuses, gaps, and next deliverable agree.
3. Verify material paths exist and recompute identity-critical hashes.
4. Compare recorded Git state with the live tree.
5. Inspect the final diff and confirm only authorized handoff/status files changed in this phase.
6. Confirm no secrets or PII were added and every unverified claim is labeled.
7. Report files changed, current authority, unresolved gaps, next deliverable, contradictions, and validation. Then stop.

## Mode: `handoff 接班`

### Read-only boundary

Do not edit, create, export, stage, commit, fetch, pull, push, deploy, browse, or execute external actions. Allow only read-only inspection and non-mutating diagnostics.

### Resume workflow

1. Establish the real workspace and Git root with the bundled collector.
2. Read applicable `AGENTS.md` completely.
3. Read `HANDOFF_交班.md`, `SESSION.md`, root README, and the current authority index in that order unless project instructions are stricter.
4. Follow only direct authority pointers needed for the next deliverable.
5. Compare branch, HEAD, upstream, dirty state, paths, hashes, versions, counts, artifact status, and external-state claims with live evidence.
6. If the collector fails, or a Git repository reports `GitStatus.Available` other than `true`, report that Git state is unverifiable and stop.
7. Derive each state-file anchor with `git log -1 --format=%H -- SESSION.md` and `git log -1 --format=%H -- HANDOFF_交班.md`. Require both commands to return the same commit and require that commit to equal local `HEAD`; otherwise report state drift and stop.
8. When an upstream exists, require `Ahead = 0`, `Behind = 0`, and `Head = UpstreamHead`. Any ahead, behind, or diverged state is sync drift: report the exact counts and commits, mark local authority potentially stale, and stop without reading it as current authority. Do not fetch, pull, or merge.
9. Inspect representative formulas, ranges, sections, tests, or rendered outputs for material claims.
10. Resolve contradictions with the project authority order; otherwise prefer the newest verified artifact and state uncertainty.
11. Confirm the next deliverable is still unfinished. Do not repeat completed work.
12. State that this is a new task reconstructing context, not the source execution session.

### Resume confirmation

Return a concise confirmation containing:

1. Authority.
2. Current conclusion.
3. Verified anchors.
4. Prohibited claims.
5. Unfinished gaps.
6. Contradictions and drift.
7. Next exact deliverable.
8. Authorization boundary.

Then stop and wait for a separate implementation instruction.

## Failure handling

- If no Git repository exists, continue with filesystem evidence and label Git metadata unavailable.
- If the folder is only a shell, inspect its parent and directly adjacent candidates without broad recursion.
- If handoff files are missing during `交班`, create project-default files. If missing during `接班`, do not create them; reconstruct what is possible and report the gap.
- If handoff files conflict with artifacts, preserve the conflict and follow authority order; never edit artifacts merely to make the summary agree.
- If verification requires internet access, credentials, or external actions not authorized by the command, mark the claim not reverified.
- If a required file is unreadable, encrypted, corrupt, or unavailable, state the limitation.
- If a user decision would materially change the state, preserve alternatives instead of choosing.
