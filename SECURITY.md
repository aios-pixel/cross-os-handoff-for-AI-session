# Security policy

## Supported version

Security fixes are applied to the latest released version.

## Reporting a vulnerability

Use GitHub private vulnerability reporting when it is available for this repository. Do not include credentials, tokens, private keys, real personal data, or private project files in a public issue.

If private reporting is unavailable, open a public issue containing only a minimal, redacted description and request a private follow-up channel.

## Security boundaries

`cn-handoff` is designed to:

- avoid collecting chat transcripts and hidden conversation state;
- redact resolved workspace paths in collector output;
- avoid hostnames, device names, credentials, tokens, and account data;
- keep resume operations read-only;
- stop when Git synchronization drift makes local authority potentially stale.

These controls reduce accidental disclosure but do not replace repository access control, secret scanning, backups, or review of handoff files before publication.
