# Risk Model

Every Tri-Tier task is classified from R0 through R4.

| Class | Meaning | Default tier | Minimum evidence |
|---|---|---|---|
| R0 | Documentation-only change | Luna | E2 |
| R1 | Isolated low-risk task | Luna | E2 |
| R2 | Normal product change | Terra | E3 |
| R3 | High-risk system change | Sol | E4 |
| R4 | Owner-controlled action | Sol | E5 |

## R0

Documentation changes that do not alter product, security, policy, or runtime behaviour.

## R1

Bounded, mechanical, read-only, or locally verifiable tasks.

## R2

Normal product work requiring implementation, independent review, and integrated validation.

## R3

Authentication, authorization, privacy, tenant isolation, migrations, billing,
security boundaries, encryption, or other sensitive system changes.

## R4

Production deployment, protected-branch merge, destructive data operation,
secret rotation, release publication, customer charging, or owner policy change.

R4 work may be prepared and verified, but the controlled action must stop for
explicit owner approval.
