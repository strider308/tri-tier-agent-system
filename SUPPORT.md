# Support

## Start here

Read the [README](README.md), [quickstart](docs/quickstart.md), and [command
reference](docs/command-reference.md) first. From the repository root, verify
the checkout with:

```powershell
pwsh -NoProfile -File .\scripts\verify-repository.ps1
pwsh -NoProfile -File .\src\tri-agent.ps1 doctor
```

## Bug reports

Use the bug-report issue template when the problem is not a suspected security
vulnerability. Include the version or commit, operating system and PowerShell
version, the command or smallest safe reproduction, expected behavior, actual
behavior, and relevant verifier or doctor output.

Remove credentials, access tokens, customer data, production logs, private
paths, and generated run state before posting.

## Feature requests

Use the feature-request template. Describe the user outcome, scope, trade-offs,
and how the change would preserve routing, evidence, recovery, and review
boundaries.

## Security problems

Do not report suspected vulnerabilities in a public issue. Follow the private
reporting guidance in [SECURITY.md](SECURITY.md) instead.
