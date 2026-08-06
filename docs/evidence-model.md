# Evidence Model

Tri-Tier assigns evidence levels from E0 through E5.

| Level | Meaning | Example |
|---|---|---|
| E0 | Unsupported statement | A worker says tests pass without output |
| E1 | Code inspection | A reviewer reads the affected implementation |
| E2 | Static or targeted validation | Lint, type check, parser, or targeted test |
| E3 | Integrated validation | Relevant build or integrated test suite |
| E4 | Runtime verification | Browser, staging, manual, or runtime behaviour |
| E5 | Independent reproduction | A separate reviewer reproduces the result |

## Minimum evidence by risk

| Risk | Minimum evidence |
|---|---|
| R0 | E2 |
| R1 | E2 |
| R2 | E3 |
| R3 | E4 |
| R4 | E5 with independent reproduction |

A material claim with no evidence is E0 and cannot satisfy any task gate.
