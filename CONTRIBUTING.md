# Contributing

Contributions are welcome through GitHub issues and pull requests.

## Development

1. Fork the repository.
2. Create a focused branch.
3. Change only the files needed for the issue.
4. Run the contract tests on the native operating system.
5. Confirm that collectors emit no host-specific paths, credentials, or account data.
6. Open a pull request describing behavior changes and verification evidence.

Run tests from `plugins/cn-handoff`:

```text
python3 -m unittest discover -s tests -v
```

Changes to Windows collection behavior should be tested on Windows. Changes to POSIX collection behavior should be tested on macOS or Linux. Cross-platform changes should be verified on both families before release.

## Pull request expectations

- Keep handoff and resume authorization boundaries explicit.
- Preserve read-only behavior for `handoff 接班`.
- Treat synchronization drift as a stop condition.
- Add or update tests for behavior changes.
- Do not include real user paths, credentials, tokens, chat transcripts, or private project files.

By submitting a contribution, you agree that it is licensed under Apache-2.0.
