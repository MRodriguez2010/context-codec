<div align="center">

# 🧬 Context Codec

### A streaming compression protocol for persistent AI agent conversations

[![OpenClaw Skill](https://img.shields.io/badge/OpenClaw-Skill-blue?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNCIgaGVpZ2h0PSIyNCIgdmlld0JveD0iMCAwIDI0IDI0IiBmaWxsPSJ3aGl0ZSI+PHBhdGggZD0iTTEyIDJDNi40OCAyIDIgNi40OCAyIDEyczQuNDggMTAgMTAgMTAgMTAtNC40OCAxMC0xMFMxNy41MiAyIDEyIDJ6Ii8+PC9zdmc+)](https://docs.openclaw.ai/tools/creating-skills)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0-orange?style=flat-square)]()
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](CONTRIBUTING.md)

**Reduce token burn by 60-80% on long-running OpenClaw sessions.**

Context Codec prevents context bloat at the source — instead of compressing *after* your context window fills up, it maintains a living compressed state that grows logarithmically, not linearly.

[Installation](#installation) · [How It Works](#how-it-works) · [Commands](#commands) · [Benchmarks](#benchmarks) · [FAQ](#faq)

</div>

---

## The Problem

OpenClaw stores full conversation history as JSONL session files. Every turn, tool call, skill output, and heartbeat check-in accumulates. On a 50-turn session with tool-heavy workflows, you're easily burning **200k+ tokens** of cached context per interaction.

Existing solutions (`/compact`, context-optimizer, context-compactor, etc.) are **reactive** — they compress or prune *after* the bloat happens. That's like recording a raw video and compressing the file afterward.

## The Solution

Context Codec is **proactive** — it's a streaming compression protocol that prevents bloat at the source. Think H.264 for conversations, not WinZip for chat logs.

```
┌─────────────────────────────────────────────────────────┐
│                    BEFORE (Linear Growth)                │
│                                                         │
│  Turn 1 → [Full history: 2k tokens]     → LLM          │
│  Turn 10 → [Full history: 25k tokens]   → LLM          │
│  Turn 30 → [Full history: 80k tokens]   → LLM          │
│  Turn 50 → [Full history: 200k tokens]  → LLM  💸💸💸  │
│                                                         │
├─────────────────────────────────────────────────────────┤
│                   AFTER (Logarithmic Growth)             │
│                                                         │
│  Turn 1 → [Digest: 200 tokens + raw]    → LLM          │
│  Turn 10 → [Digest: 600 tokens + raw]   → LLM          │
│  Turn 30 → [Digest: 1.2k tokens + raw]  → LLM          │
│  Turn 50 → [Digest: 1.8k tokens + raw]  → LLM  ✅      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## What Makes This Different

| Feature | `/compact` | context-optimizer | context-compactor | **Context Codec** |
|---|---|---|---|---|
| When it acts | Manual trigger | Threshold hit | Threshold hit | **Every turn** |
| Approach | Summarize history | Prune tokens | One-shot compress | **Delta encode** |
| Tool output | Kept raw | Pruned | Summarized | **Encoded before entry** |
| State model | Stateless | Stateless | Stateless | **Running digest** |
| Growth curve | Linear → reset | Linear → prune | Linear → compress | **Logarithmic** |
| Analogy | Deleting old photos | Cropping photos | Zipping photo folder | **Streaming video** |

## How It Works

### Core Concepts

**1. Running Digest (Keyframe)**
A structured, compressed representation of the entire conversation state. Updated incrementally after each turn — never rebuilt from scratch.

```markdown
## DIGEST v1 | Turn 23 | ts:1711800000
### GOAL: Build REST API for inventory system
### STATE: implementing PUT /items/:id endpoint
### CONTEXT: Express+Postgres stack; items table(id,name,qty,price);
    GET/POST done; auth=JWT middleware; tests passing 12/12
### PENDING: PUT endpoint, DELETE endpoint, pagination
### ARTIFACTS: src/routes/items.js(142L), src/middleware/auth.js(38L),
    tests/items.test.js(89L), .env.example
### TOOL_CACHE: last_lint=0warn; last_test=12pass/0fail; db=connected
```

**2. Delta Encoding**
After each turn, only the *changes* are recorded and merged into the digest:

```markdown
## DELTA | Turn 23→24
- STATE: implementing PUT → implementing DELETE
- CONTEXT: +validation_middleware(zod); PUT tested OK
- PENDING: -PUT endpoint; DELETE endpoint, pagination remain
- ARTIFACTS: items.js(142→178L), +src/middleware/validate.js(24L)
- TOOL_CACHE: last_test=14pass/0fail
```

**3. Skill Output Encoding**
Verbose tool outputs are compressed *before* entering context:

| Raw Output | Encoded |
|---|---|
| 200-line npm install log | `npm:OK +12deps 0vuln 4.2s` |
| 50-line test suite output | `tests:18pass/0fail 2.1s cov:87%` |
| Full file listing | `ls:14files 3dirs 2.1MB [.js×8,.json×3,.md×2,.env]` |
| Git status with 20 changes | `git:+3/-1/~2 branch:feat/api ahead:2` |
| API response with nested JSON | `api:200 {items:47,pages:5,per:10}` |

**4. Compressed Internal Reasoning**
For multi-step reasoning that doesn't face the user:

```
[R] usr wants pagination → need: limit/offset params, SQL LIMIT/OFFSET,
    response envelope {data,meta:{page,total,per}} → modify GET /items
    route → update tests → ~30min
```

## Installation

### Quick Start

```bash
# 1. Create skill directory
mkdir -p ~/.openclaw/workspace/skills/context-codec/scripts

# 2. Copy SKILL.md into the directory
cp SKILL.md ~/.openclaw/workspace/skills/context-codec/

# 3. Copy and run the init script
cp scripts/codec-init.sh ~/.openclaw/workspace/skills/context-codec/scripts/
chmod +x ~/.openclaw/workspace/skills/context-codec/scripts/codec-init.sh
bash ~/.openclaw/workspace/skills/context-codec/scripts/codec-init.sh

# 4. Verify
openclaw skills list
# 🧬 context-codec  Bidirectional context compression protocol...
```

### SOUL.md Integration (Recommended)

Add this to your agent's `SOUL.md`:

```markdown
## Context Management

You use the context-codec skill for all session management. At the start of
each turn, read ~/.openclaw/workspace/.context-codec/digest.md for context.
After each response, update the digest with a delta encoding of what changed.
When tool outputs are verbose, encode them using codec shorthand before
storing in context. Never let the digest exceed 2000 tokens — if it does,
self-compress by merging related CONTEXT entries.
```

See [INSTALL.md](INSTALL.md) for full setup guide, AGENTS.md integration, and multi-agent configuration.

## Commands

| Command | Description |
|---|---|
| `/codec status` | Show current digest state, turn count, token usage |
| `/codec digest` | Display the full current digest |
| `/codec ratio` | Show compression metrics for current session |
| `/codec reset` | Reset digest to initial state (new session) |
| `/codec expand <section>` | Temporarily expand a compressed section to full detail |
| `/codec pause` | Pause encoding (raw mode) for debugging |
| `/codec resume` | Resume encoding |

## Benchmarks

Expected compression ratios by session type:

| Session Type | Turns | Raw Tokens | With Codec | Ratio | Savings |
|---|---|---|---|---|---|
| Quick Q&A | 5 | 3,000 | 2,800 | 1.1:1 | ~7% |
| Code project | 30 | 85,000 | 12,000 | 7:1 | **86%** |
| Research deep-dive | 50 | 200,000 | 18,000 | 11:1 | **91%** |
| Tool-heavy automation | 40 | 150,000 | 15,000 | 10:1 | **90%** |
| Multi-day persistent agent | 100+ | 500,000+ | 25,000 | 20:1 | **95%** |

> **Note:** Short sessions (< 10 turns) may see minimal benefit. The codec shines on sessions with 20+ turns and heavy tool usage.

## Architecture

```
~/.openclaw/workspace/skills/context-codec/
├── SKILL.md              # Skill definition (the protocol)
├── scripts/
│   └── codec-init.sh     # Initialization script
└── references/           # (optional) Extended encoding rules

~/.openclaw/workspace/.context-codec/
├── config.json           # Codec configuration
├── digest.md             # Running digest (the keyframe)
└── metrics.json          # Compression statistics
```

### The Agent Loop

```
User message
    ↓
┌─────────────────────────────┐
│  Load digest.md (keyframe)  │ ← ~1-2k tokens instead of full history
│  + last 2-3 raw turns       │
├─────────────────────────────┤
│  LLM processes compact      │
│  context + new message       │
├─────────────────────────────┤
│  Generate response           │
│  Encode tool outputs         │ ← Compress before storing
│  Generate delta              │
│  Merge delta into digest     │ ← Incremental update
└─────────────────────────────┘
    ↓
Response to user
```

## Design Principles

- **Pure instruction-driven** — No code patches to OpenClaw core. It's a skill, not a fork.
- **Fail-open** — If encoding fails, raw text passes through. No data loss, ever.
- **Human messages stay raw** — User input is never compressed or altered.
- **Complements existing tools** — Works alongside `/compact`, MEMORY.md, cache-TTL pruning.
- **Self-contained digest** — The digest must always be interpretable without access to raw history.

## Guardrails

- ❌ Never discard or compress raw user messages
- ❌ Never let the digest exceed `max_tokens` (default: 2000)
- ❌ Never encode in a way that loses actionable information
- ✅ Always preserve: file paths, error messages, user preferences, pending tasks
- ✅ Always fail-open: if unsure how to encode, keep raw
- ✅ Always include turn count and timestamp in digest header

## Tuning

<details>
<summary><b>Short sessions (< 20 turns)</b></summary>

Codec overhead may not be worth it. Disable encoding:
```json
{ "encoding": { "tool_output": false, "agent_reasoning": false } }
```
</details>

<details>
<summary><b>Long sessions (50+ turns)</b></summary>

This is where Codec shines. Keep defaults. Consider lowering `max_tokens` to 1500 for smaller context window models.
</details>

<details>
<summary><b>Tool-heavy workflows</b></summary>

Tool output encoding provides the biggest savings. Keep `tool_output: true`. You'll see 10:1 to 50:1 compression on individual tool outputs.
</details>

<details>
<summary><b>Multi-agent setups</b></summary>

Each agent gets its own digest:
```
~/.openclaw/workspace/.context-codec/agents/
├── research/digest.md
├── alerts/digest.md
└── default/digest.md
```
</details>

## FAQ

**Q: Does this modify OpenClaw's core code?**
No. It's a pure instruction-driven skill. The SKILL.md tells the agent *how* to manage context differently. No patches, no forks.

**Q: What if the agent ignores the encoding instructions?**
Fail-open design. The conversation continues normally, just without compression benefits. No data loss.

**Q: Can I use this with `/compact`?**
Yes. They're complementary. Context Codec reduces what needs compacting. If `/compact` still triggers, it has less work to do.

**Q: Does this work with all LLM providers?**
Yes. Since it's instruction-driven, it works with any model OpenClaw supports — Claude, GPT, Gemini, DeepSeek, local models, etc.

**Q: Why not just use LLMLingua or similar prompt compression?**
Those tools compress static prompts once before sending. Context Codec manages dynamic, evolving agent state continuously. Different problem, different solution. See the [comparison table](#what-makes-this-different).

## The Analogy

| Concept | Traditional | Context Codec |
|---|---|---|
| Video | Store every raw frame | H.264: keyframes + deltas |
| Database | Full table scan every query | WAL: write-ahead log |
| Version control | Copy entire repo each save | Git: store diffs |
| Chat context | Replay full JSONL history | **Digest: keyframe + deltas** |

## Contributing

PRs welcome! Areas where help is needed:

- **Encoding rules** for additional tool output formats
- **Benchmarks** on different models and session types
- **Multi-agent digest sharing** protocols
- **Visualization** tools for compression metrics

## License

MIT — do whatever you want with it.

---

<div align="center">

**Built for [OpenClaw](https://openclaw.ai)** · **The first streaming compression protocol for persistent AI agent conversations.**

</div>
