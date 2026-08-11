## Change summary

- What bounded change is being made?
- What user or operational outcome does it support?

## Authority and risk

- Relevant authority or design documents:
- Risk/authorization/privacy impact:
- Does this touch generated, private, runtime, or installation data?

## Validation

- [ ] Targeted tests pass.
- [ ] `scripts/verify-repository.ps1` passes.
- [ ] `src/tri-agent.ps1 doctor` passes.
- [ ] `git diff --check` passes.
- [ ] PowerShell changes parse successfully.
- [ ] Sensitive/private/generated data checks pass.

## Documentation

- [ ] User-facing documentation updated or not applicable.
- [ ] Security/support impact considered.
- [ ] Release-note impact considered.

## Review hygiene

- [ ] No credentials, secrets, customer data, private paths, or generated run
      state is staged.
- [ ] The working tree contains only intended files.
