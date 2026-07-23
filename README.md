# Cross-OS Handoff for AI Sessions

`cn-handoff` is a filesystem-backed Codex plugin for verified project continuity across new tasks, computers, and operating systems.

It does not copy hidden chat memory. It writes durable project state, verifies the live Git workspace, detects synchronization drift, and reconstructs context in a fresh Codex task.

## Why

Starting a new AI session usually loses decisions, authority files, verified facts, unfinished work, and safety boundaries. Copying a chat summary is not enough because it cannot prove which files, branch, commit, or artifact currently controls the project.

`cn-handoff` makes the handoff:

- filesystem-backed instead of chat-memory-dependent;
- Git-aware and fail-closed when the destination is behind;
- cross-platform on Windows, macOS, and Linux;
- explicit about verified facts, unknowns, blockers, and authorization;
- read-only during resume unless the user separately authorizes implementation.

## Installation

Requires the Codex app or CLI with plugin marketplace support.

```text
codex plugin marketplace add aios-pixel/cross-os-handoff-for-AI-session
codex plugin add cn-handoff@cross-os-handoff-for-ai-session
```

Open a fresh Codex task after installation so the skill catalog reloads.

## Commands

```text
handoff 交班
handoff 任務後交班
handoff 接班
```

- `handoff 交班` verifies the current workspace and maintains the project handoff files.
- `handoff 任務後交班` completes an explicitly authorized task, performs proportional QA, then records the resulting state.
- `handoff 接班` performs read-only reconstruction in a new task and stops after reporting the verified state.

If the project has no handoff convention, the plugin uses:

- `SESSION.md` for complete current state;
- `HANDOFF_交班.md` for the short resume entrypoint.

## Cross-host workflow

On the source computer:

1. Open the real project workspace.
2. Run `handoff 交班`.
3. Review the generated state files.
4. Separately authorize and perform the required Git commit and push.

On the destination computer:

1. Synchronize the same branch by an explicit fast-forward operation.
2. Open a fresh Codex task in that workspace.
3. Run `handoff 接班`.
4. Confirm the reported branch, commit, dirty state, authority chain, and next deliverable.

When the destination is behind its upstream, resume reports synchronization drift and stops. It does not pull, merge, reset, rebase, or continue implementation automatically.

## Privacy and safety

The collectors redact the resolved workspace path and do not collect chat transcripts, hostnames, device names, tokens, credentials, browser data, or account data.

The handoff workflow does not authorize commit, push, deployment, publication, external messaging, or changes to business artifacts unless the user separately requests those actions.

## Platform support

|Platform|Collector|Contract test expectation|
|---|---|---|
|Windows|PowerShell|Windows-native tests run; POSIX-native test skips|
|macOS|POSIX shell|POSIX-native tests run; Windows-native test skips|
|Linux|POSIX shell|POSIX-native tests run; Windows-native test skips|

Run the tests from the plugin directory:

```text
python3 -m unittest discover -s tests -v
```

## Version history

The public history contains verified source snapshots from `v2.0.0` through `v2.1.7`. See [CHANGELOG.md](CHANGELOG.md) and [PUBLICATION.md](PUBLICATION.md).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).

---

# 跨作業系統AI工作階段交接

`cn-handoff`是以檔案系統為基礎的CodexPlugin，用於不同Task、不同電腦及不同作業系統之間的可驗證專案延續。

它不會複製隱藏的對話記憶，而是保存可持久化的專案狀態、核對即時Git工作區、偵測同步漂移，並在新的CodexTask中重建上下文。

## 解決的問題

新的AI工作階段通常會遺失決策、權威檔案、已驗證事實、未完成工作及安全邊界。單純複製對話摘要無法證明目前真正控制專案的是哪個檔案、分支、Commit或產物。

`cn-handoff`提供：

- 不依賴對話記憶的檔案式交接；
- 可辨識Git狀態，目的端落後時採Fail-closed停止；
- 支援Windows、macOS及Linux；
- 清楚區分已驗證事實、未知項目、阻礙及授權邊界；
- 接班預設唯讀，除非使用者另行授權實作。

安裝後請開啟新的CodexTask，使SkillCatalog重新載入。交班端執行`handoff 交班`，接班端完成明確的GitFast-forward後，在新Task執行`handoff 接班`。

本工具不會自動執行Pull、Merge、Reset、Rebase、Commit、Push、部署或發布。
