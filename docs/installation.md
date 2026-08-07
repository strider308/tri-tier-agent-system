# Isolated installation

Phase 6 installs the public Tri-Tier Agent System into an isolated application
directory. It does not modify the existing private Codex installation, agent
directory, shell profile, or `PATH`.

## Default location

The default target is:

```text
%LOCALAPPDATA%\TriTierAgentSystem\isolated
```

Use `compatibility-check` and `install-plan` before applying changes.

```powershell
.\src\tri-agent.ps1 compatibility-check -Json
.\src\tri-agent.ps1 install-plan -Json
```

An installation requires an exact normalized target confirmation:

```powershell
.\src\tri-agent.ps1 install-apply `
    -ConfirmInstallRoot "$env:LOCALAPPDATA\TriTierAgentSystem\isolated" `
    -Json
```

Upgrading an existing owned installation also requires the current `installId`.
The ID is returned by `install-status`.

## Safety boundaries

The installer rejects targets that overlap:

- the repository source;
- `$HOME\.codex`;
- `CODEX_HOME`;
- filesystem roots;
- symbolic links or reparse-point ancestors.

The installer never changes `PATH`. The installed launchers are placed under
`bin` inside the isolated target.

## Transactions

Files are copied into a sibling staging directory and parsed before activation.
An existing owned installation is moved to a timestamped backup before the
staged payload replaces it. Any pre-commit failure restores the backup.
