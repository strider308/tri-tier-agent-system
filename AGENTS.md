# Repository Agent Instructions

## Authority order

1. Current user instruction
2. Approved implementation plan
3. This file
4. Architecture and security documentation
5. Existing tests
6. Current implementation

## Responsibilities

### Terra

Coordinates execution, creates bounded task briefs, tracks state, and decides
the next action.

### Luna

Investigates, implements, tests, repairs, and records evidence.

### Sol

Reviews architecture, security, privacy, correctness, and acceptance evidence.

## Prohibited behaviour

- Do not commit secrets.
- Do not commit `.codegraph/`.
- Do not perform production deployment without explicit approval.
- Do not allow an implementer to approve its own work.
- Do not claim validation without command or runtime evidence.
