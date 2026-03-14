# Research: yoyo-evolve & yoagent — Self-Evolving Agent Framework

**Date:** 2026-03-07
**Sources:**
- https://github.com/yologdev/yoyo-evolve
- https://github.com/yologdev/yoagent

---

## Overview

**yoyo-evolve** is a self-improving coding agent written in Rust (~470 lines). It runs on a 4-hour cron schedule via GitHub Actions, reads its own source code, decides what to improve, implements changes, and commits them — but only if tests pass. No human writes its code.

**yoagent** is the underlying Rust library (crate) that provides the agent loop, tool execution, LLM provider abstraction, and context management. It's the framework yoyo-evolve is built on.

---

## Architecture

```
┌─────────────────────────────────────┐
│  GitHub Actions (cron, every 4hrs)  │  ← Scheduler
├─────────────────────────────────────┤
│  evolve.sh (orchestration script)   │  ← Pipeline
├─────────────────────────────────────┤
│  yoagent (Rust library)             │  ← Agent framework
├─────────────────────────────────────┤
│  Claude API (Anthropic)             │  ← Brain
└─────────────────────────────────────┘
```

---

## yoagent Framework

### What It Provides

- **Core agent loop**: Prompt → LLM stream → Tool execution → Loop if tool calls → Done
- **Built-in tools**: `bash`, `read_file`, `write_file`, `edit_file`, `list_files`, `search`
- **Multi-provider support** (7 protocols, 20+ providers): Anthropic, OpenAI, Gemini, Bedrock, Azure, Vertex AI, and OpenAI-compatible endpoints (xAI, Groq, Cerebras, Mistral, etc.)
- **Event streaming**: Start → TurnStart → MessageUpdate → ToolExecution → TurnEnd → End
- **Context management**: Token tracking, overflow detection, tiered compaction (truncate → summarize → drop middle)
- **Parallel tool execution** by default, with sequential/batched strategies available
- **Sub-agents** via SubAgentTool for task delegation
- **Execution limits**: Max turns, tokens, timeout
- **State persistence** for pause/resume workflows
- **Lifecycle callbacks**: before_turn, after_turn, on_error
- **AgentSkills integration**: Skills are directories with `SKILL.md` files containing YAML frontmatter

### Installation

```toml
[dependencies]
yoagent = "0.5"
tokio = { version = "1", features = ["full"] }
```

### Basic Usage

```rust
use yoagent::agent::Agent;
use yoagent::provider::AnthropicProvider;
use yoagent::types::*;

#[tokio::main]
async fn main() {
    let mut agent = Agent::new(AnthropicProvider)
        .with_system_prompt("You are a helpful assistant.")
        .with_model("claude-sonnet-4-20250514")
        .with_api_key(std::env::var("ANTHROPIC_API_KEY").unwrap());

    let mut rx = agent.prompt("What is Rust's ownership model?").await;

    while let Some(event) = rx.recv().await {
        match event {
            AgentEvent::MessageUpdate {
                delta: StreamDelta::Text { delta }, ..
            } => print!("{}", delta),
            AgentEvent::AgentEnd { .. } => break,
            _ => {}
        }
    }
}
```

### Architecture Modules

- `types.rs` — Message, AgentMessage, AgentEvent, AgentTool trait
- `agent_loop.rs` — Core loop implementation
- `agent.rs` — Stateful Agent with queue management
- `context.rs` — Token tracking and compaction
- `tools/` — Built-in tool implementations
- `provider/` — Multi-protocol provider implementations

---

## yoyo-evolve: The Self-Evolving Agent

### Repository Structure

```
src/main.rs              Agent CLI implementation (~470 lines)
scripts/evolve.sh        Evolution pipeline orchestration
scripts/build_site.py    Journey website generator
skills/                  Skill definitions (assess, evolve, communicate, research, release)
IDENTITY.md              Immutable agent constitution
JOURNAL.md               Append-only session log
LEARNINGS.md             Accumulated research findings
DAY_COUNT                Current evolution day counter
Cargo.toml               Rust project configuration
```

### The Evolution Cycle (evolve.sh)

Each run follows this pipeline:

1. **Gate check** — Sponsorship tiers control how many runs/day (3–6 based on $0/$10/$50 tiers)
2. **Build verification** — `cargo build && cargo test` to confirm baseline health
3. **CI status check** — If last GitHub Actions run failed, prioritize fixing that first
4. **Issue aggregation** — Fetches GitHub issues labeled `agent-input` (community), `agent-self` (backlog), `agent-help-wanted`. Ranks by net votes.
5. **Planning phase** — A planning agent reads IDENTITY.md, src/main.rs, JOURNAL.md, and issues. Produces `SESSION_PLAN.md` with up to 5 tasks. Timeout: 1200s.
6. **Implementation phase** — For each task, a separate agent instance writes tests first, makes changes, runs `cargo fmt + clippy + build + test`. Timeout: 900s per task.
7. **Validation** — If builds fail, agent gets 3 fix attempts. After 3 failures, all changes revert.
8. **Journaling** — Agent writes a summary entry in JOURNAL.md
9. **Issue responses** — Posts comments on addressed GitHub issues, closes resolved ones
10. **Tag & push** — Creates a `day${N}-HH-MM` tag and pushes to main

### The Constitution (IDENTITY.md)

Seven core rules constrain the agent:

1. **Single-focus** — One improvement per session, depth over breadth
2. **Automated quality gates** — All changes must pass compilation + tests
3. **Mandatory journaling** — Every session is documented, successes and failures
4. **Permanent memory** — Journal entries are never deleted
5. **Test-first** — Tests precede feature implementation
6. **Reasoned transparency** — Changes explain their rationale
7. **User-driven priorities** — Community issues outrank self-directed improvements

### Community Interaction

Users influence development through GitHub issues:

- `agent-input` — Feature requests, bug reports, suggestions
- `agent-self` — Issues yoyo creates for itself
- `agent-help-wanted` — Problems requiring human assistance

Issues are prioritized by net votes (thumbs-up minus thumbs-down).

### Web Research Capability

The agent can do web research, but in a scrappy way — no dedicated tool, just bash + curl:

- **Web search**: `curl -s 'https://lite.duckduckgo.com/lite?q=your+query' | sed 's/<[^>]*>//g' | head -60`
- **Read webpages**: curl + sed to strip HTML
- **Rust docs**: Fetches from docs.rs directly
- **GitHub source**: Reads raw files via raw.githubusercontent.com

Research skill enforces: "Arrive with a specific question before searching. No aimless browsing." Findings go to LEARNINGS.md to avoid redundant research.

---

## How to Build Your Own Self-Evolving Agent

### Option 1: Use yoagent (Rust)

```toml
[dependencies]
yoagent = "0.5"
tokio = { version = "1", features = ["full"] }
```

1. Write a minimal agent CLI using yoagent
2. Create an IDENTITY.md defining constraints and improvement goals
3. Write an evolve.sh that pre-checks build, invokes agent, post-checks build, commits or reverts
4. Set up GitHub Actions cron to run evolve.sh on schedule
5. Add JOURNAL.md for the agent to document sessions

### Option 2: Use Any Agent with Tools (Framework-Agnostic)

The pattern doesn't require yoagent. Any agent with file editing + shell execution works:

```bash
#!/bin/bash
# evolve.sh — minimal self-evolution pipeline
set -euo pipefail

cd "$(dirname "$0")"

# 1. Verify current state is healthy
npm test || exit 1  # or cargo test, pytest, etc.

# 2. Ask the agent to improve itself
claude -p "Read your own source code in src/.
  Read IDENTITY.md for your constraints.
  Identify one concrete improvement.
  Implement it. Write tests first.
  Run 'npm test' to verify." --allowedTools bash,read,write,edit

# 3. Verify the changes
if npm test; then
  git add -A
  git commit -m "self-evolution: $(date +%Y-%m-%d-%H%M)"
  git push
else
  git checkout -- .
  git clean -fd
  echo "Evolution failed, reverted."
fi
```

GitHub Actions cron:

```yaml
on:
  schedule:
    - cron: '0 */6 * * *'
jobs:
  evolve:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./evolve.sh
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

### Key Design Decisions

| Decision | Why |
|---|---|
| Immutable constitution (IDENTITY.md) | Prevents agent from removing its own safety constraints |
| Build/test gates | Agent can't break itself — failing changes always revert |
| One change per cycle | Prevents cascading failures; easier to debug and revert |
| Append-only journal | Audit trail; agent learns from past failures |
| Timeouts | Prevents runaway sessions burning API credits |
| Git as safety net | Every commit is a checkpoint; any state recoverable |

### Minimum Viable Self-Evolving Agent

The simplest version needs:

1. An LLM with tool use (Claude, GPT-4, etc.)
2. File read/write/edit tools pointed at the agent's own code
3. A shell tool to run builds and tests
4. A wrapper script that commits on success and reverts on failure
5. A scheduler (cron, GitHub Actions) to run it periodically

The "self-evolution" is just an LLM reading code + a prompt saying "improve this" + quality gates ensuring it can't break things.
