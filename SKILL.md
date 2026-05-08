---
name: context-codec
description: "Bidirectional context compression protocol for persistent agents. Maintains a running semantic digest between turns instead of replaying full history. Encodes skill outputs and tool results into dense structured payloads before they enter the context window. Use when sessions are long-running, multi-turn, or involve heavy tool/skill output. Reduces token burn by 60-80% on long sessions."
version: 1.0.0
metadata: {"openclaw":{"emoji":"🧬","requires":{"bins":["bash"]}}}
---

# Context Codec — Bidirectional Context Compression Protocol

## What This Is

A streaming compression protocol for OpenClaw agent conversations. Instead of
accumulating raw message history and compressing after the fact, Context Codec
**prevents bloat at the source** by maintaining a living compressed state.

Think of it as the difference between:
- **Existing tools**: Record the whole movie, then compress the file (post-hoc)
- **Context Codec**: Stream-encode as you go, like H.264 for conversations (pre-emptive)

## Core Concepts

### 1. The Running Digest (Keyframe)

A structured, compressed representation of the entire conversation state so far.
Updated incrementally after each turn — never rebuilt from scratch.

Format:
```
## DIGEST v1 | Turn {N} | {timestamp}
### GOAL: {current_user_objective_in_one_line}
### STATE: {what_has_been_accomplished}
### CONTEXT: {key_facts_decisions_constraints}
### PENDING: {open_questions_or_next_steps}
### ARTIFACTS: {files_created_modified_with_paths}
### TOOL_CACHE: {compressed_tool_results_still_relevant}
```

### 2. Delta Encoding (Between Turns)

After each assistant response, encode only what changed:
```
## DELTA T{N}→T{N+1}
+STATE: {new_accomplishment}
+CONTEXT: {new_fact_or_decision}
-PENDING: {resolved_item}
+PENDING: {new_open_item}
~ARTIFACTS: {modified_file_path}
```

The delta is merged into the digest. Old deltas are discarded.

### 3. Skill Output Encoding (Inbound Compression)

When a tool or skill returns verbose output, encode it BEFORE it enters context:

**Raw tool output (wasteful):**
```
The git log shows 47 commits since last Tuesday. The most recent commit
was by user jdoe at 2024-03-28 14:32:00 with message "fix: resolve
race condition in session handler". The previous commit was by user
asmith at 2024-03-28 13:15:00 with message "feat: add webhook retry
logic"... [2000 more tokens of commit history]
```

**Codec-encoded (dense):**
```
GIT_LOG|since=Tue|count=47|latest={jdoe,2024-03-28T14:32,"fix:race-cond/session-handler"}|prev={asmith,2024-03-28T13:15,"feat:webhook-retry"}|summary=mostly-fixes,2-features,0-breaking
```

### 4. Agent Internal Reasoning (Outbound Compression)

For multi-step reasoning that doesn't need to be human-readable, the agent
uses compressed internal notation:

**Verbose (wasteful):**
```
I need to first check if the file exists, then read its contents,
then parse the JSON, then extract the relevant fields, and finally
format the output for the user.
```

**Compressed (dense):**
```
PLAN: chk_exist→read→parse_json→extract_fields→fmt_output
```

## Helper Scripts

Context Codec ships with bash scripts that handle deterministic operations.
The agent MUST use these scripts for file I/O, validation, and metrics — never
write digest/metrics files by hand.

Scripts live at: `~/.openclaw/workspace/skills/context-codec/scripts/`

| Script | Purpose |
|--------|---------|
| `codec.sh <cmd>` | Main entry point — routes to sub-scripts |
| `codec-init.sh` | Initialize workspace directory structure |
| `codec-digest.sh <cmd>` | Digest CRUD, validation, token counting |
| `codec-metrics.sh <cmd>` | Compression stats tracking |

### Key Script Commands

```bash
bash scripts/codec.sh init                    # Initialize workspace
bash scripts/codec.sh status                  # Show digest + compression stats
bash scripts/codec.sh digest                  # Print current digest
bash scripts/codec.sh validate                # Check digest format
bash scripts/codec.sh check-limit             # Check token count vs max
bash scripts/codec.sh ratio                   # Show compression ratio
bash scripts/codec.sh archive                 # Archive current turn
bash scripts/codec.sh reset                   # Reset digest + metrics
echo "<new digest>" | bash scripts/codec.sh update   # Write new digest from stdin

bash scripts/codec-metrics.sh record -t 5 -r 3000 -c 200  # Record turn stats
```

## Workflow

### On Session Start
1. Run `bash scripts/codec.sh status` to check for existing digest
2. If digest exists, read it with `bash scripts/codec.sh digest`
3. If not, run `bash scripts/codec.sh init` to create initial state
4. Use the digest as session context instead of raw JSONL history

### On Each User Message
1. Read current digest via `bash scripts/codec.sh digest`
2. Append user message to context (raw — human input stays readable)
3. Agent processes with digest + current message (NOT full history)

### On Each Assistant Response
1. Agent responds normally to the user
2. **Immediately after**, generate a DELTA encoding of what changed
3. Merge DELTA into the running digest to produce the new digest
4. Run `bash scripts/codec.sh archive` to archive the previous turn
5. Pipe the new digest: `echo "<new digest>" | bash scripts/codec.sh update`
6. Run `bash scripts/codec.sh check-limit` — if over limit, self-compress
7. Record metrics: `bash scripts/codec-metrics.sh record -t N -r RAW -c COMPRESSED`

### On Tool/Skill Output
1. Intercept the raw output
2. Apply encoding rules (see Encoding Rules below)
3. Store encoded version in digest under TOOL_CACHE
4. Pass encoded version to agent context (not raw)

### On Session End or /compact
1. Run `bash scripts/codec.sh archive` to archive final turn
2. The digest serves as the session summary

## Encoding Rules for Tool Output

### Rule 1: Structured Data → Key-Value Shorthand
```
# Input: JSON API response with 50 fields
# Output: API_RESP|status=200|items=23|next_page=true|top={id:445,name:"widget"}
```

### Rule 2: Lists → Count + Top-N + Summary
```
# Input: 200-line file listing
# Output: FILES|count=200|types={ts:89,md:34,json:22,other:55}|largest={dist/bundle.js,2.4MB}
```

### Rule 3: Logs/Output → Pattern + Exceptions
```
# Input: 500 lines of build output
# Output: BUILD|status=fail|duration=34s|errors=2|err1={src/index.ts:45,"type-mismatch"}|err2={src/utils.ts:12,"missing-import"}|warnings=7
```

### Rule 4: Code → Signature + Purpose
```
# Input: Full function body (40 lines)
# Output: FN|name=processQueue|args=(items:T[],opts:Config)|returns=Promise<Result[]>|purpose=batch-process-with-retry|lines=40|complexity=moderate
```

### Rule 5: Conversations/Messages → Sentiment + Key Points
```
# Input: 30 Slack messages from a channel
# Output: MSGS|channel=#dev|count=30|period=2h|topics={deploy-issue,hotfix-plan}|sentiment=urgent|decision="rollback-to-v2.3"|action={@jdoe:"deploy-v2.3-by-5pm"}
```

## Commands

When the user runs a `/codec` command, execute the corresponding script:

| Command | Implementation |
|---------|---------------|
| `/codec status` | `bash scripts/codec.sh status` |
| `/codec digest` | `bash scripts/codec.sh digest` |
| `/codec reset` | `bash scripts/codec.sh reset` |
| `/codec validate` | `bash scripts/codec.sh validate` |
| `/codec ratio` | `bash scripts/codec.sh ratio` |
| `/codec encode <text>` | Apply encoding rules (see below) to the provided text |
| `/codec decode <encoded>` | Expand encoded text back to readable form |
| `/codec audit` | `ls -lh ~/.openclaw/workspace/.context-codec/turns/` |

## Guardrails

- **Never discard user messages** — human input is always stored raw in turn archives
- **Never encode user-facing output** — only internal reasoning and tool results get compressed
- **Digest must be self-contained** — reading ONLY the digest should give full context
- **Lossy is OK for tool output** — exact bytes don't matter, semantics do
- **Lossless for decisions** — any decision, commitment, or user preference is preserved verbatim
- **Fail open** — if encoding fails or is ambiguous, pass through raw text rather than lose information
- **Always use scripts for file I/O** — never write digest.md or metrics.json directly
- **Always validate after update** — run `bash scripts/codec.sh validate` after writing a new digest
- **Always check token limit** — run `bash scripts/codec.sh check-limit` after each digest update; if it exits non-zero, self-compress by merging CONTEXT entries and removing stale TOOL_CACHE entries
- **Always record metrics** — after each turn, run `bash scripts/codec-metrics.sh record` with raw and compressed token counts

## Compression Ratio Targets

| Content Type | Target Ratio | Method |
|---|---|---|
| Tool output (JSON/logs) | 10:1 to 50:1 | Key-value shorthand |
| Conversation history | 5:1 to 15:1 | Running digest |
| Code blocks | 3:1 to 8:1 | Signature + purpose |
| Agent reasoning | 4:1 to 10:1 | Compressed notation |
| User messages | 1:1 (no compression) | Preserved raw |

## File Structure

```
{workspace}/skills/context-codec/
├── SKILL.md               # This file (protocol + instructions)
└── scripts/
    ├── codec.sh           # Main entry point
    ├── codec-init.sh      # Initialize workspace
    ├── codec-digest.sh    # Digest CRUD, validation, token counting
    └── codec-metrics.sh   # Compression stats tracking

{workspace}/.context-codec/
├── digest.md              # Current running digest (the "keyframe")
├── config.json            # Codec settings
├── turns/                 # Archived individual turns (audit trail)
│   ├── T001.md
│   ├── T002.md
│   └── ...
└── metrics.json           # Compression stats over time
```

## config.json Defaults

```json
{
  "version": "1.0.0",
  "encoding": {
    "tool_output": true,
    "agent_reasoning": true,
    "user_messages": false
  },
  "digest": {
    "max_tokens": 2000,
    "update_strategy": "delta_merge",
    "archive_turns": true
  },
  "metrics": {
    "track_compression_ratio": true,
    "track_token_savings": true
  }
}
```

## Integration with OpenClaw Built-ins

Context Codec is designed to **complement**, not replace, OpenClaw's existing
context management:

- **Works WITH /compact**: When /compact runs, it can use the digest as a
  superior summary source instead of re-summarizing raw history
- **Works WITH cache-TTL pruning**: Codec reduces what needs to be cached in
  the first place
- **Works WITH MEMORY.md**: Codec handles ephemeral session state; MEMORY.md
  handles persistent cross-session knowledge
- **Works WITH compaction modes**: Set `compaction: "safeguard"` and let Codec
  handle the heavy lifting before compaction even triggers

## Example Session

### Turn 1 (User)
> "Help me debug why the API tests are failing"

### Digest after Turn 1
```
## DIGEST v1 | Turn 1 | 2024-03-28T10:00:00Z
### GOAL: Debug failing API tests
### STATE: Just started
### CONTEXT: (none yet)
### PENDING: Identify which tests fail, find root cause
### ARTIFACTS: (none)
### TOOL_CACHE: (empty)
```

### Turn 2 (Agent runs test suite, gets 200 lines of output)

**Raw output**: 200 lines, ~3000 tokens
**Encoded**: `TESTS|suite=api|total=45|pass=41|fail=4|fail_list={test_auth_flow:timeout@auth.ts:89,test_create_user:assertion@users.ts:134,test_delete_user:assertion@users.ts:201,test_rate_limit:timeout@middleware.ts:45}|duration=12.4s`
**Encoded size**: ~80 tokens (37:1 compression)

### Digest after Turn 2
```
## DIGEST v1 | Turn 2 | 2024-03-28T10:01:00Z
### GOAL: Debug failing API tests
### STATE: Identified 4 failing tests out of 45
### CONTEXT: 2 timeouts (auth, rate_limit), 2 assertion failures (user CRUD)
### PENDING: Inspect auth.ts:89 and middleware.ts:45 for timeout causes
### ARTIFACTS: (none)
### TOOL_CACHE: TESTS|suite=api|total=45|pass=41|fail=4|fail_list={...}
```

**Without Codec**: Context now holds 3000+ tokens of raw test output
**With Codec**: Context holds ~200 tokens of digest + encoded results

### Turn 10 (deep into debugging)

**Without Codec**: Context holds ~25,000 tokens of accumulated history
**With Codec**: Context holds ~2,500 tokens (digest + recent encoded results)

**Savings: ~90% token reduction by Turn 10**

## Why This Is Different From Existing Tools

| Existing Tool | What It Does | Limitation |
|---|---|---|
| context-optimizer | Prunes AFTER context bloats | Reactive, not preventive |
| context-compactor | Summarizes old messages | Loses detail, one-shot |
| /compact | Manual compression trigger | User must remember to run it |
| MEMORY.md | Persists facts across sessions | Doesn't help within a session |
| cache-TTL pruning | Prunes expired cache entries | Only affects cache, not content |
| **context-codec** | **Prevents bloat at the source** | **Proactive, continuous, bidirectional** |

## Performance Notes

- Digest update adds ~100-200ms per turn (LLM generates the delta)
- Tool output encoding is done by the agent inline (no extra API call)
- Storage overhead is minimal (~2KB per digest, ~1KB per archived turn)
- The digest itself should stay under 2000 tokens (configurable)
- If digest exceeds max_tokens (check via `bash scripts/codec.sh check-limit`),
  self-compress by merging CONTEXT entries and pruning stale TOOL_CACHE entries
