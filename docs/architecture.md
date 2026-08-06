# Architecture

The Tri-Tier Agent System divides responsibility rather than merely assigning
different model sizes.

## Terra

Terra owns coordination, decomposition, dependencies, durable state, and
continuation.

## Luna

Luna owns bounded execution: investigation, implementation, tests, repair, and
evidence collection.

## Sol

Sol owns independent review, architecture, high-risk analysis, adjudication,
and phase-level acceptance recommendations.

## Independence requirement

The worker that implemented a change cannot provide its final independent
approval.
