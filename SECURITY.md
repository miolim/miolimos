# Security Policy

## Reporting a vulnerability

Please do **not** open a public issue for security vulnerabilities.

Instead, report them privately to the maintainer by email
(see the maintainer's GitHub profile). Include:

- a description of the issue and its impact,
- steps to reproduce (or a proof of concept), and
- the affected version / commit if known.

You will receive an acknowledgement as soon as possible, and we will work
with you on a fix and coordinated disclosure.

## Supported versions

miolimOS is pre-1.0 and moves quickly. Security fixes are applied to the
`main` branch; once tagged releases exist, the latest release will be the
supported one.

## Notes for self-hosters

- Always set a strong `LOCKBOX_MASTER_KEY` and your own Rails master key;
  never reuse the maintainer's credentials.
- Change the seeded admin password immediately after first setup.
- Agent API tokens are full credentials — scope agents with least-privilege
  capabilities and rotate tokens if leaked (see
  [docs/agents.md](docs/agents.md)).
- Keep the customer portal and the main app behind HTTPS.
