# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately through the repository's
configured private security-reporting channel (for example, a GitHub private
security advisory when enabled). Do not open a public issue for a suspected
vulnerability.

Do not include credentials, access tokens, private configuration, customer
data, or production logs in public issues or pull requests. If a report
contains sensitive evidence, redact it and use the private channel instead.

When reporting a problem, include the affected version or commit, impact,
minimal reproduction steps, and a safe description of the evidence. Do not
send secrets as proof of impact.

## Support status and limitations

This project is alpha software. It is not a security boundary and does not
provide certification, authorization, or production-readiness guarantees.
Review destructive, production, privacy, and authorization decisions with a
human owner.

Security reports may not receive the response time or compatibility guarantees
of a supported production release. See [SUPPORT.md](SUPPORT.md) for ordinary
usage questions and bug reports.

## Security boundaries

- Runtime and durable state must not contain secrets.
- `.codegraph/`, `.tri-tier/`, and `.agent-runs/` are local or generated data
  boundaries and must remain out of public commits.
- The private Codex installation is outside this repository and must not be
  modified by repository workflows or installation commands.
- Production deployment and destructive migrations require explicit human
  approval.
- Worker reports and automated checks are evidence inputs, not automatic proof.
