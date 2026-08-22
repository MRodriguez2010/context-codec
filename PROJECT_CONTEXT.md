# Context Codec — Project Context

## Purpose

Context Codec is an OpenClaw skill and small shell-tool suite for maintaining a compact, structured digest of a long-running agent conversation. It provides digest initialization, validation, update/archive/reset commands, and user-supplied compression metrics.

It is a protocol and bookkeeping tool. It does not patch an LLM, alter a model context window, automatically intercept every OpenClaw message, or prove that a generated summary preserves all relevant meaning.

## Current reality

- `SKILL.md` defines the agent-side protocol and shorthand.
- `scripts/codec-init.sh` creates local digest/config/metrics state.
- `scripts/codec-digest.sh` validates, reads, updates, archives, limits, backs up, and resets the digest.
- `scripts/codec-metrics.sh` records and summarizes raw/compressed token counts supplied to it.
- `scripts/codec.sh` is the command dispatcher.
- `scripts/test-harness.sh` tests file lifecycle, validation, metrics arithmetic, limits, reset, multi-agent paths, and a simulated multi-turn sequence.
- The README’s large savings figures are projections/simulations, not independent model-quality or real-session benchmarks. Metrics prove arithmetic on supplied counts, not causal token savings or semantic fidelity.

## Runtime model

```text
OpenClaw agent instructions
        |
        +-- reads/writes digest through the codec scripts
        +-- decides what details to retain
        +-- records estimated/raw/compressed counts

Local .context-codec state
        +-- config.json
        +-- digest.md
        +-- metrics.json / metrics.log
        +-- archived turn digests
```

The scripts do not control what OpenClaw sends to a provider. Effective context reduction depends on the agent actually using the digest and on surrounding platform behavior.

## Accuracy, privacy, and safety boundaries

- Compression is lossy unless the agent retains every decision-critical fact. “Fail open” in the instructions does not itself guarantee preservation.
- Digest and archived turns can contain filenames, errors, user preferences, private business context, or secrets copied from tool output. Keep runtime state private and out of Git.
- Do not encode hidden reasoning or claim access to model-private chain-of-thought. Store concise decisions, evidence, constraints, and next actions instead.
- Never use a digest as the sole record for legal, financial, medical, security, incident, or destructive-operation decisions.
- Validate against the authoritative files/systems before acting on compressed state.
- Multi-agent use needs ownership/locking rules; the current shell scripts do not provide robust concurrent-writer coordination.

## Source and backup boundaries

- This private GitHub repository is a secondary source/history backup. Installed skill copies and local `.context-codec` runtime state are separate.
- Do not commit digests, metrics logs derived from private sessions, agent memory, raw conversations, tokens, or credentials.
- Installation into an active OpenClaw workspace is an operational change and should be reviewed separately from this source backup.

## Verification

```bash
bash scripts/test-harness.sh
bash -n scripts/*.sh
```

Before making product claims, add real-session evaluation with a fixed task set, baseline/control runs, objective task-completion scoring, fact-retention checks, exact provider token accounting where available, and failure cases. Synthetic counts are useful unit fixtures, not benchmarks.

## Documentation and licensing gaps

- The README displays an MIT badge, but this snapshot has no tracked `LICENSE` file.
- The README links to contribution material that is not present in the tracked tree.
- Do not publish or accept contributions until the owner deliberately chooses a license and adds matching files.

## Maturity and product path

- **Current phase:** working shell-tool prototype and protocol experiment.
- **Website showcase:** suitable as an experiment if projected savings are clearly labeled and a real evaluation is added.
- **Sellable-product potential:** low as a standalone SaaS; moderate as a tested observability/context-management component.
- **Public-source candidate:** technically small and sanitizable, but not ready until claims, license, concurrent writes, retention/privacy, and real benchmarks are addressed.

## Resume point

Run the shell harness, add locking/atomic update behavior, separate measured results from illustrative projections, build a small reproducible benchmark corpus, and add an owner-chosen license before considering a public duplicate.
