# compound-engineering-plugin (fork)

Review-only fork of [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) for Gemini CLI.

Trimmed to 30 skills: 1 ce-review skill + 28 reviewer personas + 1 learnings-researcher. All workflow skills (brainstorm, plan, work, compound, etc) and non-review agents removed.

## What's different from upstream

| Change | Why |
|--------|-----|
| Patch A: `transformContentForGemini` spawn-pattern rewrite | Converts "Spawn X-reviewer as sub-agent" to "Use the X-reviewer skill" |
| Patch B: Gemini CLI dispatch section in ce-review Stage 4 | Explicit skill activation instructions + sequential fallback |
| Removed 59 non-review skills/agents | Reduces context from 89 to 30 skills (tighter token budget) |

> **Branch:** Patches live on `fix/gemini-ce-review-dispatch`. Upstream `main` tracks EveryInc and does not carry these fixes — clone with `-b fix/gemini-ce-review-dispatch` or you will install an unpatched tree.

## Install

### Prerequisites

- [Bun](https://bun.sh) runtime
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm i -g @google/gemini-cli`)

### One command

```bash
git clone -b fix/gemini-ce-review-dispatch \
  https://github.com/onchainyaotoshi/compound-engineering-plugin.git
cd compound-engineering-plugin
bun install
./install.sh
```

This builds Gemini skills from source and deploys to `~/.gemini/skills/`.

### Manual steps

```bash
bun install
bun run src/index.ts install compound-engineering --to gemini
cp -r .gemini/skills/* ~/.gemini/skills/
rm -rf .gemini
```

## Usage

### Report-only (recommended for automation)

```bash
cd /your/project
gemini -m gemini-3.1-pro-preview --approval-mode yolo \
  --include-directories ~/.gemini/commands/ce \
  -p "Use the ce-review skill to review changes in report-only mode with base:HEAD~3"
```

On pro-tier quota exhaustion, cascade to `gemini-2.5-pro`. `gemini-2.5-flash` is **not recommended** for full `/ce:review` — empirically hangs silent or terminates with "quota exhausted" without producing findings. Gate behind an explicit opt-in (e.g. `ALLOW_FLASH_FALLBACK=1`) if you must try it.

### Interactive

```bash
gemini -m gemini-3.1-pro-preview --approval-mode yolo \
  --include-directories ~/.gemini/commands/ce
# then type: /ce:review mode:report-only base:HEAD~3
```

### Flags

| Flag | Purpose |
|------|---------|
| `-m gemini-3.1-pro-preview` | Primary model. Cascade: 3.1-pro-preview → 2.5-pro → (opt-in) 2.5-flash |
| `--approval-mode yolo` | Auto-approve all tool calls (required — `plan` blocks shell access `/ce:review` needs) |
| `--include-directories ~/.gemini/commands/ce` | Narrow scope. **Do not use `~/.gemini`** — it grants read on `settings.json` (MCP env, API keys) |

## Verify

```bash
gemini skills list | grep ce-review   # should show [Enabled]
```

## Included Reviewers

**Always-on:** correctness, testing, maintainability, project-standards, agent-native, learnings

**Conditional (selected per diff):** security, performance, api-contract, data-migrations, reliability, adversarial, cli-readiness, previous-comments, dhh-rails, kieran-rails/python/typescript, julik-frontend-races

**CE conditional:** schema-drift-detector, deployment-verification
