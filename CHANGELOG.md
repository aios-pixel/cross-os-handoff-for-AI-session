# Changelog

All notable changes to this project are documented here.

The public Git history was reconstructed from verified release snapshots. Private repository history, private project documents, and host-specific paths were intentionally excluded.

## [2.1.6] - 2026-07-23

### Changed

- Hardened collector execution and environment-state boundaries.
- Preserved the caller's `GIT_OPTIONAL_LOCKS` value after Windows collection.
- Expanded cross-platform contract coverage to 18 tests.

## [2.1.5] - 2026-07-23

### Changed

- Failed closed when Git root discovery fails instead of accepting ambiguous workspace state.
- Added regression coverage for Git root discovery failure.

## [2.1.4] - 2026-07-23

### Fixed

- Correctly classified staged, unstaged, and untracked files in the Windows collector.
- Added regression coverage for Windows dirty-state counts.

## [2.1.3] - 2026-07-22

### Fixed

- Reported clean-workspace status counts as zero instead of null.

## [2.1.2] - 2026-07-22

### Changed

- Kept collector inspection read-only in strict sandbox environments.

## [2.1.1] - 2026-07-22

### Changed

- Made contract tests resolve correctly from an installed Plugin cache.

## [2.1.0] - 2026-07-22

### Changed

- Enforced canonical LF line endings for byte-identical cross-host source.
- Hardened synchronization-drift verification during resume.

## [2.0.0] - 2026-07-22

### Added

- Introduced the cross-platform Codex handoff plugin.
- Added Windows PowerShell and POSIX shell workspace collectors.
- Added verified handoff and read-only resume workflows.
- Added collector contract tests.
