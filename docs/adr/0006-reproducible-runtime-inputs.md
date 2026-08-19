# ADR 0006: Lock Runtime Dependencies and Docker Base Images

## Status

Accepted

## Context

RagOnFire depends on a large Python stack, two Docker base images, and Apache
AGE built from source. Direct dependency pins are not enough to keep installs
repeatable because transitive Python dependencies and floating Docker tags can
change underneath the same source checkout.

## Decision

Install the host runtime from `rag-anything/requirements.lock`, pin Docker base
images by digest, and build Apache AGE from a fixed commit.

## Consequences

Clean installs are more reproducible. Dependency updates become an explicit
maintenance task: regenerate the lock file, refresh Docker digests, verify the
AGE ref, and run the smoke checks.
