# compound-engineering-plugin (fork)

Review-only fork of [EveryInc/compound-engineering-plugin](https://github.com/EveryInc/compound-engineering-plugin) for Gemini CLI.

Trimmed to 30 skills: 1 ce-review skill + 28 reviewer personas + 1 learnings-researcher. All workflow skills (brainstorm, plan, work, compound, etc) and non-review agents removed.

## What's different from upstream

| Change | Why |
|--------|-----|
| Patch A: `transformContentForGemini` spawn-pattern rewrite | Converts "Spawn X-reviewer as sub-agent" to "Use the X-reviewer skill" |
| Patch B: Gemini CLI dispatch section in ce-review Stage 4 | Explicit skill activation instructions + sequential fallback |
| Removed 59 non-review skills/agents | Reduces context from 89 to 30 skills, works on flash models |

## Install

### Prerequisites

- [Bun](https://bun.sh) runtime
- [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm i -g @google/gemini-cli`)

### One command

```bash
git clone https://github.com/onchainyaotoshi/compound-engineering-plugin.git
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
gemini -m gemini-2.5-flash --approval-mode yolo \
  --include-directories ~/.gemini \
  -p "Use the ce-review skill to review changes in report-only mode with base:HEAD~3"
```

### Interactive

```bash
gemini -m gemini-2.5-flash --approval-mode yolo --include-directories ~/.gemini
# then type: /ce:review mode:report-only base:HEAD~3
```

### Flags

| Flag | Purpose |
|------|---------|
| `-m gemini-2.5-flash` | Use flash model (pro when quota available) |
| `--approval-mode yolo` | Auto-approve all tool calls |
| `--include-directories ~/.gemini` | Allow reading skills outside project |

## Verify

```bash
gemini skills list | grep ce-review   # should show [Enabled]
```

## Included Reviewers

**Always-on:** correctness, testing, maintainability, project-standards, agent-native, learnings

**Conditional (selected per diff):** security, performance, api-contract, data-migrations, reliability, adversarial, cli-readiness, previous-comments, dhh-rails, kieran-rails/python/typescript, julik-frontend-races

**CE conditional:** schema-drift-detector, deployment-verification
