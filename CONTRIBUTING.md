# Contributing

Contributions are welcome.

## Development rules

1. Keep Luna, Terra, and Sol responsibilities distinct.
2. Add tests for routing or state-machine changes.
3. Do not commit credentials, generated runtime state, or machine-specific paths.
4. Keep public interfaces backward compatible unless the change is documented.
5. Use independent review for security-sensitive changes.

## Validation

```powershell
pwsh .\scripts\verify-repository.ps1
```
