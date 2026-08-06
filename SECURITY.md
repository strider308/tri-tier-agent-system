# Security Policy

## Reporting security problems

Do not publish credentials, private configuration, customer data, or
production logs in an issue.

Report suspected vulnerabilities privately to the repository maintainer.

## Current support status

The project is in alpha. It must not be treated as a security boundary or used
to authorize destructive or production actions without human review.

## Permanent safeguards

- Runtime state should not contain secrets.
- `.codegraph/` must remain local.
- Production deployment requires explicit human approval.
- Destructive migrations require explicit human approval.
- Worker reports are evidence inputs, not automatic proof.
