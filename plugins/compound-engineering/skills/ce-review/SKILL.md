---
name: ce:review
description: "Structured code review using tiered persona agents, confidence-gated findings, and a merge/dedup pipeline. ARP-specific fork — report-only only."
argument-hint: "[blank to review current branch, or provide PR link] [base:<ref>]"
---

# Code Review

> **Fork note (ARP-specific, 2026-04-15).** This ce-review is a fork of the upstream EveryInc compound-engineering ce-review, adapted for use as the Gemini-side dispatch target of [agent-review-pipeline](https://github.com/onchainyaotoshi/agent-review-pipeline). **Only `mode:report-only` is supported.** Upstream's `interactive`, `autofix`, and `headless` modes have been stripped because ARP's pipeline requires strict read-only semantics (it runs its own auto-fix loop via fingerprint-merged findings from the orchestrator side; any ce-review-side mutation violates ARP's read-only contract + causes double-fix corruption). The fork trades upstream compatibility for clarity — ~200 lines of mode-branch prose removed, orchestrator has less context to parse, hallucination risk reduced.

Reviews code changes using dynamically selected reviewer personas. Spawns persona sub-agents in parallel (ARP callers set Gemini CLI to parallel via the explicit `Dispatch mode: PARALLEL` prompt directive + API key Tier 1 headroom) that return structured JSON. The orchestrator merges and deduplicates findings into a single report and hands the JSON back to the caller. Nothing hits disk — `mode:report-only` is strict no-write.

## When to Use

- As the Gemini-side dispatch from `/arp` (agent-review-pipeline) — the primary consumer.
- Standalone on a PR by a human operator who wants a read-only compound-engineering review without ARP's auto-fix loop.

## Argument Parsing

Parse `$ARGUMENTS` for the following optional tokens. Strip each recognized token before interpreting the remainder as the PR number, GitHub URL, or branch name.

| Token | Example | Effect |
|-------|---------|--------|
| `mode:report-only` | `mode:report-only` | The default and only supported mode. Token is accepted for explicitness but may be omitted. |
| `base:<sha-or-ref>` | `base:abc1234` or `base:origin/main` | Skip scope detection — use this as the diff base directly. Required when the local branch has commits not yet pushed to the PR head. |
| `plan:<path>` | `plan:docs/plans/2026-03-25-001-feat-foo-plan.md` | Load this plan for requirements verification. |

**Rejected tokens.** If `mode:autofix` or `mode:headless` appear in arguments, stop and emit: `Review failed. Reason: mode '<name>' is not supported in this ARP fork. Only mode:report-only is supported.` Do not dispatch agents.

## Mode: report-only (the only mode)

- **Skip all user questions.** Infer intent conservatively if the diff metadata is thin.
- **Never edit files or externalize work.** Do not write `.context/compound-engineering/ce-review/<run-id>/`. Do not create todo files. Do not commit, push, or create a PR. Do not run `mkdir` against `.context/`. See Stage 4 Run ID subsection for the enforcement point.
- **Safe for parallel read-only verification.** Can run concurrently with browser testing on the same checkout (no mutation) — though ARP's caller-side concurrency guards already prevent overlapping `/arp` runs.
- **Do not switch the shared checkout.** If the caller passes an explicit PR or branch target, report-only must run against the current checkout (using `base:<ref>` for scope) or stop instead of running `gh pr checkout` / `git checkout`. ARP always passes `base:<ref>` so this is enforced by contract, not by guard.

## Severity Scale

All reviewers use P0-P3:

| Level | Meaning | Action |
|-------|---------|--------|
| **P0** | Critical breakage, exploitable vulnerability, data loss/corruption | Must fix before merge |
| **P1** | High-impact defect likely hit in normal usage, breaking contract | Should fix |
| **P2** | Moderate issue with meaningful downside (edge case, perf regression, maintainability trap) | Fix if straightforward |
| **P3** | Low-impact, narrow scope, minor improvement | User's discretion |

## Action Routing

Severity answers **urgency**. Routing answers **who acts next** and **whether this skill may mutate the checkout**.

| `autofix_class` | Default owner | Meaning |
|-----------------|---------------|---------|
| `safe_auto` | `review-fixer` | Local, deterministic fix suitable for the in-skill fixer when the current mode allows mutation |
| `gated_auto` | `downstream-resolver` or `human` | Concrete fix exists, but it changes behavior, contracts, permissions, or another sensitive boundary that should not be auto-applied by default |
| `manual` | `downstream-resolver` or `human` | Actionable work that should be handed off rather than fixed in-skill |
| `advisory` | `human` or `release` | Report-only output such as learnings, rollout notes, or residual risk |

Routing rules:

- **Synthesis owns the final route.** Persona-provided routing metadata is input, not the last word.
- **Choose the more conservative route on disagreement.** A merged finding may move from `safe_auto` to `gated_auto` or `manual`, but never the other way without stronger evidence.
- **Only `safe_auto -> review-fixer` enters the in-skill fixer queue automatically.**
- **`requires_verification: true` means a fix is not complete without targeted tests, a focused re-review, or operational validation.**

## Reviewers

17 reviewer personas in layered conditionals, plus CE-specific agents. See the persona catalog included below for the full catalog.

**Always-on (every review):**

| Agent | Focus |
|-------|-------|
| `compound-engineering:review:correctness-reviewer` | Logic errors, edge cases, state bugs, error propagation |
| `compound-engineering:review:testing-reviewer` | Coverage gaps, weak assertions, brittle tests |
| `compound-engineering:review:maintainability-reviewer` | Coupling, complexity, naming, dead code, abstraction debt |
| `compound-engineering:review:project-standards-reviewer` | CLAUDE.md and AGENTS.md compliance -- frontmatter, references, naming, portability |
| `compound-engineering:review:agent-native-reviewer` | Verify new features are agent-accessible |
| `compound-engineering:research:learnings-researcher` | Search docs/solutions/ for past issues related to this PR |

**Cross-cutting conditional (selected per diff):**

| Agent | Select when diff touches... |
|-------|---------------------------|
| `compound-engineering:review:security-reviewer` | Auth, public endpoints, user input, permissions |
| `compound-engineering:review:performance-reviewer` | DB queries, data transforms, caching, async |
| `compound-engineering:review:api-contract-reviewer` | Routes, serializers, type signatures, versioning |
| `compound-engineering:review:data-migrations-reviewer` | Migrations, schema changes, backfills |
| `compound-engineering:review:reliability-reviewer` | Error handling, retries, timeouts, background jobs |
| `compound-engineering:review:adversarial-reviewer` | Diff >=50 changed non-test/non-generated/non-lockfile lines, or auth, payments, data mutations, external APIs |
| `compound-engineering:review:cli-readiness-reviewer` | CLI command definitions, argument parsing, CLI framework usage, command handler implementations |
| `compound-engineering:review:previous-comments-reviewer` | Reviewing a PR that has existing review comments or threads |

**Stack-specific conditional (selected per diff):**

| Agent | Select when diff touches... |
|-------|---------------------------|
| `compound-engineering:review:dhh-rails-reviewer` | Rails architecture, service objects, session/auth choices, or Hotwire-vs-SPA boundaries |
| `compound-engineering:review:kieran-rails-reviewer` | Rails application code where conventions, naming, and maintainability are in play |
| `compound-engineering:review:kieran-python-reviewer` | Python modules, endpoints, scripts, or services |
| `compound-engineering:review:kieran-typescript-reviewer` | TypeScript components, services, hooks, utilities, or shared types |
| `compound-engineering:review:julik-frontend-races-reviewer` | Stimulus/Turbo controllers, DOM events, timers, animations, or async UI flows |

**CE conditional (migration-specific):**

| Agent | Select when diff includes migration files |
|-------|------------------------------------------|
| `compound-engineering:review:schema-drift-detector` | Cross-references schema.rb against included migrations |
| `compound-engineering:review:deployment-verification-agent` | Produces deployment checklist with SQL verification queries |

## Review Scope

Every review spawns all 4 always-on personas plus the 2 CE always-on agents, then adds whichever cross-cutting and stack-specific conditionals fit the diff. The model naturally right-sizes: a small config change triggers 0 conditionals = 6 reviewers. A Rails auth feature might trigger security + reliability + kieran-rails + dhh-rails = 10 reviewers.

## Protected Artifacts

The following paths are compound-engineering pipeline artifacts and must never be flagged for deletion, removal, or gitignore by any reviewer:

- `docs/brainstorms/*` -- requirements documents created by ce:brainstorm
- `docs/plans/*.md` -- plan files created by ce:plan (living documents with progress checkboxes)
- `docs/solutions/*.md` -- solution documents created during the pipeline

If a reviewer flags any file in these directories for cleanup or removal, discard that finding during synthesis.

## How to Run

### Stage 1: Determine scope

Compute the diff range, file list, and diff. Minimize permission prompts by combining into as few commands as possible.

**If `base:` argument is provided (fast path):**

The caller already knows the diff base. Skip all base-branch detection, remote resolution, and merge-base computation. Use the provided value directly:

```
BASE_ARG="{base_arg}"
BASE=$(git merge-base HEAD "$BASE_ARG" 2>/dev/null) || BASE="$BASE_ARG"
```

Then produce the same output as the other paths:

```
echo "BASE:$BASE" && echo "FILES:" && git diff --name-only $BASE && echo "DIFF:" && git diff -U10 $BASE && echo "UNTRACKED:" && git ls-files --others --exclude-standard
```

This path works with any ref — a SHA, `origin/main`, a branch name. Automated callers (ce:work, lfg, slfg) should prefer this to avoid the detection overhead. **Do not combine `base:` with a PR number or branch target.** If both are present, stop with an error: "Cannot use `base:` with a PR number or branch target — `base:` implies the current checkout is already the correct branch. Pass `base:` alone, or pass the target alone and let scope detection resolve the base." This avoids scope/intent mismatches where the diff base comes from one source but the code and metadata come from another.

**If a PR number or GitHub URL is provided as an argument:**

This fork is report-only — do NOT run `gh pr checkout <number-or-url>` on the shared checkout. Tell the caller: "This ARP fork of ce-review cannot switch the shared checkout. Run it from an isolated worktree/checkout that's already on the PR branch, or pass `base:<ref>` to review the current checkout's diff against that ref." Stop here unless the review is already running in an isolated checkout.

First, verify the worktree is clean before switching branches:

```
git status --porcelain
```

If the output is non-empty, inform the user: "You have uncommitted changes on the current branch. Stash or commit them before reviewing a PR, or use standalone mode (no argument) to review the current branch as-is." Do not proceed with checkout until the worktree is clean.

Then check out the PR branch so persona agents can read the actual code (not the current checkout):

```
gh pr checkout <number-or-url>
```

Then fetch PR metadata. Capture the base branch name and the PR base repository identity, not just the branch name:

```
gh pr view <number-or-url> --json title,body,baseRefName,headRefName,url
```

Use the repository portion of the returned PR URL as `<base-repo>` (for example, `EveryInc/compound-engineering-plugin` from `https://github.com/EveryInc/compound-engineering-plugin/pull/348`).

Then compute a local diff against the PR's base branch so re-reviews also include local fix commits and uncommitted edits. Substitute the PR base branch from metadata (shown here as `<base>`) and the PR base repository identity derived from the PR URL (shown here as `<base-repo>`). Resolve the base ref from the PR's actual base repository, not by assuming `origin` points at that repo:

```
PR_BASE_REMOTE=$(git remote -v | awk 'index($2, "github.com:<base-repo>") || index($2, "github.com/<base-repo>") {print $1; exit}')
if [ -n "$PR_BASE_REMOTE" ]; then PR_BASE_REMOTE_REF="$PR_BASE_REMOTE/<base>"; else PR_BASE_REMOTE_REF=""; fi
PR_BASE_REF=$(git rev-parse --verify "$PR_BASE_REMOTE_REF" 2>/dev/null || git rev-parse --verify <base> 2>/dev/null || true)
if [ -z "$PR_BASE_REF" ]; then
  if [ -n "$PR_BASE_REMOTE_REF" ]; then
    git fetch --no-tags "$PR_BASE_REMOTE" <base>:refs/remotes/"$PR_BASE_REMOTE"/<base> 2>/dev/null || git fetch --no-tags "$PR_BASE_REMOTE" <base> 2>/dev/null || true
    PR_BASE_REF=$(git rev-parse --verify "$PR_BASE_REMOTE_REF" 2>/dev/null || git rev-parse --verify <base> 2>/dev/null || true)
  else
    if git fetch --no-tags https://github.com/<base-repo>.git <base> 2>/dev/null; then
      PR_BASE_REF=$(git rev-parse --verify FETCH_HEAD 2>/dev/null || true)
    fi
    if [ -z "$PR_BASE_REF" ]; then PR_BASE_REF=$(git rev-parse --verify <base> 2>/dev/null || true); fi
  fi
fi
if [ -n "$PR_BASE_REF" ]; then BASE=$(git merge-base HEAD "$PR_BASE_REF" 2>/dev/null) || BASE=""; else BASE=""; fi
```

```
if [ -n "$BASE" ]; then echo "BASE:$BASE" && echo "FILES:" && git diff --name-only $BASE && echo "DIFF:" && git diff -U10 $BASE && echo "UNTRACKED:" && git ls-files --others --exclude-standard; else echo "ERROR: Unable to resolve PR base branch <base> locally. Fetch the base branch and rerun so the review scope stays aligned with the PR."; fi
```

Extract PR title/body, base branch, and PR URL from `gh pr view`, then extract the base marker, file list, diff content, and `UNTRACKED:` list from the local command. Do not use `gh pr diff` as the review scope after checkout -- it only reflects the remote PR state and will miss local fix commits until they are pushed. If the base ref still cannot be resolved from the PR's actual base repository after the fetch attempt, stop instead of falling back to `git diff HEAD`; a PR review without the PR base branch is incomplete.

**If a branch name is provided as an argument:**

This fork is report-only — do NOT run `git checkout <branch>` on the shared checkout. Tell the caller: "This ARP fork of ce-review cannot switch the shared checkout. Run it from an isolated worktree/checkout that's already on `<branch>`, or pass `base:<ref>` to review the current checkout's diff against that ref." Stop here unless the review is already running in an isolated checkout.

First, verify the worktree is clean before switching branches:

```
git status --porcelain
```

If the output is non-empty, inform the user: "You have uncommitted changes on the current branch. Stash or commit them before reviewing another branch, or provide a PR number instead." Do not proceed with checkout until the worktree is clean.

```
git checkout <branch>
```

Then detect the review base branch and compute the merge-base. Run the `references/resolve-base.sh` script, which handles fork-safe remote resolution with multi-fallback detection (PR metadata -> `origin/HEAD` -> `gh repo view` -> common branch names):

```
RESOLVE_OUT=$(bash references/resolve-base.sh) || { echo "ERROR: resolve-base.sh failed"; exit 1; }
if [ -z "$RESOLVE_OUT" ] || echo "$RESOLVE_OUT" | grep -q '^ERROR:'; then echo "${RESOLVE_OUT:-ERROR: resolve-base.sh produced no output}"; exit 1; fi
BASE=$(echo "$RESOLVE_OUT" | sed 's/^BASE://')
```

If the script outputs an error, stop instead of falling back to `git diff HEAD`; a branch review without the base branch would only show uncommitted changes and silently miss all committed work.

On success, produce the diff:

```
echo "BASE:$BASE" && echo "FILES:" && git diff --name-only $BASE && echo "DIFF:" && git diff -U10 $BASE && echo "UNTRACKED:" && git ls-files --others --exclude-standard
```

You may still fetch additional PR metadata with `gh pr view` for title, body, and linked issues, but do not fail if no PR exists.

**If no argument (standalone on current branch):**

Detect the review base branch and compute the merge-base using the same `references/resolve-base.sh` script as branch mode:

```
RESOLVE_OUT=$(bash references/resolve-base.sh) || { echo "ERROR: resolve-base.sh failed"; exit 1; }
if [ -z "$RESOLVE_OUT" ] || echo "$RESOLVE_OUT" | grep -q '^ERROR:'; then echo "${RESOLVE_OUT:-ERROR: resolve-base.sh produced no output}"; exit 1; fi
BASE=$(echo "$RESOLVE_OUT" | sed 's/^BASE://')
```

If the script outputs an error, stop instead of falling back to `git diff HEAD`; a standalone review without the base branch would only show uncommitted changes and silently miss all committed work on the branch.

On success, produce the diff:

```
echo "BASE:$BASE" && echo "FILES:" && git diff --name-only $BASE && echo "DIFF:" && git diff -U10 $BASE && echo "UNTRACKED:" && git ls-files --others --exclude-standard
```

Using `git diff $BASE` (without `..HEAD`) diffs the merge-base against the working tree, which includes committed, staged, and unstaged changes together.

**Untracked file handling:** Always inspect the `UNTRACKED:` list, even when `FILES:`/`DIFF:` are non-empty. Untracked files are outside review scope until staged. If the list is non-empty, note the excluded untracked files in the Coverage section of the output — do not stop to ask (report-only is non-interactive by design; ARP callers don't expect mid-dispatch prompts).

### Stage 2: Intent discovery

Understand what the change is trying to accomplish. The source of intent depends on which Stage 1 path was taken:

**PR/URL mode:** Use the PR title, body, and linked issues from `gh pr view` metadata. Supplement with commit messages from the PR if the body is sparse.

**Branch mode:** Run `git log --oneline ${BASE}..<branch>` using the resolved merge-base from Stage 1.

**Standalone (current branch):** Run:

```
echo "BRANCH:" && git rev-parse --abbrev-ref HEAD && echo "COMMITS:" && git log --oneline ${BASE}..HEAD
```

Combined with conversation context (plan section summary, PR description), write a 2-3 line intent summary:

```
Intent: Simplify tax calculation by replacing the multi-tier rate lookup
with a flat-rate computation. Must not regress edge cases in tax-exempt handling.
```

Pass this to every reviewer in their spawn prompt. Intent shapes *how hard each reviewer looks*, not which reviewers are selected.

**When intent is ambiguous:** Infer conservatively from the branch name, diff, PR metadata, and caller context. Note the uncertainty in Coverage or Verdict reasoning. Do not ask questions — this fork is non-interactive by design (ARP callers don't expect mid-dispatch prompts).

### Stage 2b: Plan discovery (requirements verification)

Locate the plan document so Stage 6 can verify requirements completeness. Check these sources in priority order — stop at the first hit:

1. **`plan:` argument.** If the caller passed a plan path, use it directly. Read the file to confirm it exists.
2. **PR body.** If PR metadata was fetched in Stage 1, scan the body for paths matching `docs/plans/*.md`. If exactly one match is found and the file exists, use it as `plan_source: explicit`. If multiple plan paths appear, treat as ambiguous — demote to `plan_source: inferred` for the most recent match that exists on disk, or skip if none exist or none clearly relate to the PR title/intent. Always verify the selected file exists before using it — stale or copied plan links in PR descriptions are common.
3. **Auto-discover.** Extract 2-3 keywords from the branch name (e.g., `feat/onboarding-skill` -> `onboarding`, `skill`). Glob `docs/plans/*` and filter filenames containing those keywords. If exactly one match, use it. If multiple matches or the match looks ambiguous (e.g., generic keywords like `review`, `fix`, `update` that could hit many plans), **skip auto-discovery** — a wrong plan is worse than no plan. If zero matches, skip.

**Confidence tagging:** Record how the plan was found:
- `plan:` argument -> `plan_source: explicit` (high confidence)
- Single unambiguous PR body match -> `plan_source: explicit` (high confidence)
- Multiple/ambiguous PR body matches -> `plan_source: inferred` (lower confidence)
- Auto-discover with single unambiguous match -> `plan_source: inferred` (lower confidence)

If a plan is found, read its **Requirements Trace** (R1, R2, etc.) and **Implementation Units** (checkbox items). Store the extracted requirements list and `plan_source` for Stage 6. Do not block the review if no plan is found — requirements verification is additive, not required.

### Stage 3: Select reviewers

Read the diff and file list from Stage 1. The 4 always-on personas and 2 CE always-on agents are automatic. For each cross-cutting and stack-specific conditional persona in the persona catalog included below, decide whether the diff warrants it. This is agent judgment, not keyword matching.

**File-type awareness for conditional selection:** Instruction-prose files (Markdown skill definitions, JSON schemas, config files) are product code but do not benefit from runtime-focused reviewers. The adversarial reviewer's techniques (race conditions, cascade failures, abuse cases) target executable code behavior. For diffs that only change instruction-prose files, skip adversarial unless the prose describes auth, payment, or data-mutation behavior. Count only executable code lines toward line-count thresholds.

**`previous-comments` is PR-only.** Only select this persona when Stage 1 gathered PR metadata (PR number or URL was provided as an argument, or `gh pr view` returned metadata for the current branch). Skip it entirely for standalone branch reviews with no associated PR -- there are no prior comments to check.

Stack-specific personas are additive. A Rails UI change may warrant `kieran-rails` plus `julik-frontend-races`; a TypeScript API diff may warrant `kieran-typescript` plus `api-contract` and `reliability`.

For CE conditional agents, check if the diff includes files matching `db/migrate/*.rb`, `db/schema.rb`, or data backfill scripts.

Announce the team before spawning:

```
Review team:
- correctness (always)
- testing (always)
- maintainability (always)
- project-standards (always)
- agent-native-reviewer (always)
- learnings-researcher (always)
- security -- new endpoint in routes.rb accepts user-provided redirect URL
- kieran-rails -- controller and Turbo flow changed in app/controllers and app/views
- dhh-rails -- diff adds service objects around ordinary Rails CRUD
- data-migrations -- adds migration 20260303_add_index_to_orders
- schema-drift-detector -- migration files present
```

This is progress reporting, not a blocking confirmation.

### Stage 3b: Discover project standards paths

Before spawning sub-agents, find the file paths (not contents) of all relevant standards files for the `project-standards` persona. Use the native file-search/glob tool to locate:

1. Use the native file-search tool (e.g., Glob in Claude Code) to find all `**/CLAUDE.md` and `**/AGENTS.md` in the repo.
2. Filter to those whose directory is an ancestor of at least one changed file. A standards file governs all files below it (e.g., `plugins/compound-engineering/AGENTS.md` applies to everything under `plugins/compound-engineering/`).

Pass the resulting path list to the `project-standards` persona inside a `<standards-paths>` block in its review context (see Stage 4). The persona reads the files itself, targeting only the sections relevant to the changed file types. This keeps the orchestrator's work cheap (path discovery only) and avoids bloating the subagent prompt with content the reviewer may not fully need.

### Stage 4: Use the sub-agent skills

#### Skill name allowlist (hallucination guard)

Before activating any sub-agent skill, confirm its name appears **verbatim** in this allowlist. If the name you are about to activate is not on the list, **STOP — you have hallucinated it.** Re-check the persona catalog and pick an existing name, or skip the dispatch. No valid review outcome involves fabricating a skill name.

The 21 valid names:

| Group | Skill names |
|---|---|
| Always-on persona (4) | `correctness-reviewer`, `testing-reviewer`, `maintainability-reviewer`, `project-standards-reviewer` |
| Always-on CE (2) | `agent-native-reviewer`, `learnings-researcher` |
| Cross-cutting conditional (8) | `security-reviewer`, `performance-reviewer`, `api-contract-reviewer`, `data-migrations-reviewer`, `reliability-reviewer`, `adversarial-reviewer`, `cli-readiness-reviewer`, `previous-comments-reviewer` |
| Stack-specific conditional (5) | `dhh-rails-reviewer`, `kieran-rails-reviewer`, `kieran-python-reviewer`, `kieran-typescript-reviewer`, `julik-frontend-races-reviewer` |
| CE conditional (2) | `schema-drift-detector`, `deployment-verification-agent` |

The allowlist is the source of truth. If the diff seems to call for a specialized reviewer not on the list (`generalist`, `reviewer`, `code-reviewer`, `architect`, or any name you have invented), the correct fallback is the always-on set plus whatever cross-cutting actually applies — never fabricate a new name. An orchestrator that dispatches a non-existent skill wastes the dispatch budget on a no-op activation and corrupts the review outcome.

#### Model tiering

Persona sub-agents do focused, scoped work and should use a fast mid-tier model to reduce cost and latency without sacrificing review quality. The orchestrator itself stays on the default (most capable) model.

Use the platform's mid-tier model for all persona and CE sub-agents. In Claude Code, pass `model: "sonnet"` in the Agent tool call. On other platforms, use the equivalent mid-tier (e.g., `gpt-4o` in Codex). If the platform has no model override mechanism or the available model names are unknown, omit the model parameter and let agents inherit the default -- a working review on the parent model is better than a broken dispatch from an unrecognized model name.

CE always-on agents (agent-native-reviewer, learnings-researcher) and CE conditional agents (schema-drift-detector, deployment-verification-agent) also use the mid-tier model since they perform scoped, focused work.

The orchestrator (this skill) stays on the default model because it handles intent discovery, reviewer selection, finding merge/dedup, and synthesis -- tasks that benefit from stronger reasoning.

#### No Run ID, no artifact directory

This fork is report-only. Do NOT generate a `RUN_ID`. Do NOT run `mkdir` against `.context/compound-engineering/ce-review/`. Do NOT pass `{run_id}` to any persona sub-agent in Stage 4 Spawning. Do NOT write any file under `.context/compound-engineering/ce-review/`. Persona sub-agents return compact JSON inline only — the orchestrator keeps their responses in memory for Stage 5 merge, nothing hits disk.

**If you are about to run `mkdir -p ".context/compound-engineering/ce-review/..."`, STOP — you are violating the report-only contract that is the entire reason this fork exists.** On 2026-04-15 an orchestrator-level review run produced 11 persona JSON files under `.context/compound-engineering/ce-review/<fabricated-run-id>/` despite `mode:report-only` being in the prompt. Prior prose instructions weren't enforced strongly enough at the point where `RUN_ID` generation happens. This subsection is the enforcement point — the Run ID bash block from upstream is gone, not gated.

#### Spawning

Omit the `mode` parameter when dispatching sub-agents so the user's configured permission settings apply. Do not pass `mode: "auto"`.

Spawn each selected persona reviewer as a sub-agent using the subagent template included below. **Parallel dispatch by default in this fork** — ARP callers set Gemini CLI parallel via the explicit `Dispatch mode: PARALLEL` directive in the prompt body and run with API key Tier 1 auth (~1000 RPM Flash headroom) which has sufficient capacity for 6+ concurrent persona calls. Sequential is the fallback for platforms without adequate concurrent-call capacity (see Fallback section). Each persona sub-agent receives:

1. Their persona file content (identity, failure modes, calibration, suppress conditions)
2. Shared diff-scope rules from the diff-scope reference included below
3. The JSON output contract from the findings schema included below
4. PR metadata: title, body, and URL when reviewing a PR (empty string otherwise). Passed in a `<pr-context>` block so reviewers can verify code against stated intent
5. Review context: intent summary, file list, diff
6. **For `project-standards` only:** the standards file path list from Stage 3b, wrapped in a `<standards-paths>` block appended to the review context

Persona sub-agents are **strictly non-mutating**: they review and return structured JSON inline. No file writes anywhere — not even to `.context/`. Not even their own full analysis. This fork has no artifact directory (see "No Run ID, no artifact directory" above).

Non-mutating ≠ "no shell access." Reviewer sub-agents may use non-mutating inspection commands when needed to gather evidence or verify scope, including read-oriented `git` / `gh` usage such as `git diff`, `git show`, `git blame`, `git log`, and `gh pr view`. They must not edit project files, change branches, commit, push, create PRs, or otherwise mutate the checkout or repository state.

Each persona sub-agent returns compact JSON with merge-tier fields only — inline, no file write. The compact JSON shape:

```json
{
  "reviewer": "security",
  "findings": [
    {
      "title": "User-supplied ID in account lookup without ownership check",
      "severity": "P0",
      "file": "orders_controller.rb",
      "line": 42,
      "confidence": 0.92,
      "autofix_class": "gated_auto",
      "owner": "downstream-resolver",
      "requires_verification": true,
      "pre_existing": false,
      "suggested_fix": "Add current_user.owns?(account) guard before lookup"
    }
  ],
  "residual_risks": [...],
  "testing_gaps": [...]
}
```

Detail-tier fields (`why_it_matters`, `evidence`) are inlined in the compact return in this fork (no on-disk artifact). `suggested_fix` is required when the finding is actionable — the caller uses it directly from the compact return since there's no artifact to look up.

**CE always-on agents** (agent-native-reviewer, learnings-researcher) are dispatched as standard Agent calls, in parallel alongside persona reviewers. Give them the same review context bundle the personas receive: any PR metadata gathered in Stage 1, intent summary, review base branch name when known, `BASE:` marker, file list, diff, and `UNTRACKED:` scope notes. Do not invoke them with a generic "review this" prompt. Their output is unstructured and synthesized separately in Stage 6.

**CE conditional agents** (schema-drift-detector, deployment-verification-agent) are also dispatched as standard Agent calls when applicable. Pass the same review context bundle plus the applicability reason (for example, which migration files triggered the agent). For schema-drift-detector specifically, pass the resolved review base branch explicitly so it never assumes `main`. Their output is unstructured and must be preserved for Stage 6 synthesis just like the CE always-on agents.

#### Gemini CLI dispatch (parallel)

On Gemini CLI, persona agents are installed as skills under `~/.gemini/skills/`. Each persona skill name matches the agent's last segment: `correctness-reviewer`, `security-reviewer`, `adversarial-reviewer`, etc. To dispatch a reviewer, activate the persona skill by name and pass the review context.

**Parallel dispatch (default in this fork):** Invoke all selected persona skills in a single batch so they run concurrently. API key Tier 1 auth (Flash: ~1000 RPM) has sufficient server capacity for 6+ concurrent persona activations — the 2025-era sequential-default constraint was driven by OAuth `cloudcode-pa.googleapis.com` server-cap saturation, which API key endpoint doesn't share. Order within the batch: always-on personas + cross-cutting conditionals + stack-specific conditionals + CE agents all activated at once. Collect all results, then proceed to Stage 5 merge. Expected wall time 3-5 minutes for ~10 personas on a medium-sized PR (~20 turns per persona).

**Concurrency guard:** Validate via `scripts/probe-gemini.sh gemini-3-flash-preview` before a first dispatch on a new account / API key tier. If the probe fails with 429, the caller (ARP) should not proceed — it means the current quota tier (free OAuth or free API key) is marginal, and parallel 6-persona burst will trip. Tier 1 paid API key is the documented configuration for this fork.

**Invocation pattern for each persona:**

```
Activate the {persona-name} skill.
Pass the following review context:
- Intent: {intent_summary}
- Files: {file_list}
- Diff: {diff_content}
- PR context: {pr_metadata_or_empty}
- Run ID: {run_id}
- Reviewer name: {persona_name}
- Standards paths (project-standards only): {standards_paths}
```

**CE always-on and conditional agents** follow the same pattern. Activate them by their skill names: `agent-native-reviewer`, `learnings-researcher`, `schema-drift-detector`, `deployment-verification-agent`.

### Stage 5: Merge findings

Convert multiple reviewer compact JSON returns into one deduplicated, confidence-gated finding set. The compact returns contain merge-tier fields (title, severity, file, line, confidence, autofix_class, owner, requires_verification, pre_existing) plus the optional suggested_fix. Detail-tier fields (why_it_matters, evidence) are on disk in the per-agent artifact files and are not loaded at this stage.

1. **Validate.** Check each compact return for required top-level and per-finding fields, plus value constraints. Drop malformed returns or findings. Record the drop count.
   - **Top-level required:** reviewer (string), findings (array), residual_risks (array), testing_gaps (array). Drop the entire return if any are missing or wrong type.
   - **Per-finding required:** title, severity, file, line, confidence, autofix_class, owner, requires_verification, pre_existing
   - **Value constraints:**
     - severity: P0 | P1 | P2 | P3
     - autofix_class: safe_auto | gated_auto | manual | advisory
     - owner: review-fixer | downstream-resolver | human | release
     - confidence: numeric, 0.0-1.0
     - line: positive integer
     - pre_existing, requires_verification: boolean
   - Do not validate against the full schema here -- the full schema (including why_it_matters and evidence) applies to the artifact files on disk, not the compact returns.
2. **Confidence gate.** Suppress findings below 0.60 confidence. Exception: P0 findings at 0.50+ confidence survive the gate -- critical-but-uncertain issues must not be silently dropped. Record the suppressed count. This matches the persona instructions and the schema's confidence thresholds.
3. **Deduplicate.** Compute fingerprint: `normalize(file) + line_bucket(line, +/-3) + normalize(title)`. When fingerprints match, merge: keep highest severity, keep highest confidence, note which reviewers flagged it.
4. **Cross-reviewer agreement.** When 2+ independent reviewers flag the same issue (same fingerprint), boost the merged confidence by 0.10 (capped at 1.0). Cross-reviewer agreement is strong signal -- independent reviewers converging on the same issue is more reliable than any single reviewer's confidence. Note the agreement in the Reviewer column of the output (e.g., "security, correctness").
5. **Separate pre-existing.** Pull out findings with `pre_existing: true` into a separate list.
6. **Resolve disagreements.** When reviewers flag the same code region but disagree on severity, autofix_class, or owner, annotate the Reviewer column with the disagreement (e.g., "security (P0), correctness (P1) -- kept P0"). This transparency helps the user understand why a finding was routed the way it was.
7. **Normalize routing.** For each merged finding, set the final `autofix_class`, `owner`, and `requires_verification`. If reviewers disagree, keep the most conservative route. Synthesis may narrow a finding from `safe_auto` to `gated_auto` or `manual`, but must not widen it without new evidence.
8. **Partition the work.** Build three sets:
   - in-skill fixer queue: only `safe_auto -> review-fixer`
   - residual actionable queue: unresolved `gated_auto` or `manual` findings whose owner is `downstream-resolver`
   - report-only queue: `advisory` findings plus anything owned by `human` or `release`
9. **Sort.** Order by severity (P0 first) -> confidence (descending) -> file path -> line number.
10. **Collect coverage data.** Union residual_risks and testing_gaps across reviewers.
11. **Preserve CE agent artifacts.** Keep the learnings, agent-native, schema-drift, and deployment-verification outputs alongside the merged finding set. Do not drop unstructured agent output just because it does not match the persona JSON schema.

### Stage 6: Synthesize and present

Assemble the final report using **pipe-delimited markdown tables for findings** from the review output template included below. Other report sections (Applied Fixes, Learnings, Coverage, etc.) use bullet lists and the `---` separator before the verdict, as shown in the template. See also the "Caller consumption note (ARP-specific)" below — ARP overrides this table format with a JSON schema.

1. **Header.** Scope, intent, reviewer team with per-conditional justifications.
2. **Findings.** Rendered as pipe-delimited tables grouped by severity (`### P0 -- Critical`, `### P1 -- High`, `### P2 -- Moderate`, `### P3 -- Low`). Each finding row shows `#`, file, issue, reviewer(s), confidence, and synthesized route. Omit empty severity levels. Never render findings as freeform text blocks or numbered lists.
3. **Requirements Completeness.** Include only when a plan was found in Stage 2b. For each requirement (R1, R2, etc.) and implementation unit in the plan, report whether corresponding work appears in the diff. Use a simple checklist: met / not addressed / partially addressed. Routing depends on `plan_source`:
   - **`explicit`** (caller-provided or PR body): Flag unaddressed requirements as P1 findings with `autofix_class: manual`, `owner: downstream-resolver`. These enter the residual actionable queue and can become todos.
   - **`inferred`** (auto-discovered): Flag unaddressed requirements as P3 findings with `autofix_class: advisory`, `owner: human`. These stay in the report only — no todos, no autonomous follow-up. An inferred plan match is a hint, not a contract.
   Omit this section entirely when no plan was found — do not mention the absence of a plan.
4. **Pre-existing.** Separate section, does not count toward verdict.
5. **Learnings & Past Solutions.** Surface learnings-researcher results: if past solutions are relevant, flag them as "Known Pattern" with links to docs/solutions/ files.
6. **Agent-Native Gaps.** Surface agent-native-reviewer results. Omit section if no gaps found.
7. **Schema Drift Check.** If schema-drift-detector ran, summarize whether drift was found. If drift exists, list the unrelated schema objects and the required cleanup command. If clean, say so briefly.
8. **Deployment Notes.** If deployment-verification-agent ran, surface the key Go/No-Go items: blocking pre-deploy checks, the most important verification queries, rollback caveats, and monitoring focus areas. Keep the checklist actionable rather than dropping it into Coverage.
9. **Coverage.** Suppressed count, residual risks, testing gaps, failed/timed-out reviewers, and any intent uncertainty. (Applied Fixes + Residual Actionable Work sections from upstream are dropped in this report-only fork — no fix phase ever runs; actionable findings have their fix metadata attached to the finding itself for the caller to route.)
10. **Verdict.** Ready to merge / Ready with fixes / Not ready. Fix order if applicable. When an `explicit` plan has unaddressed requirements, the verdict must reflect it — a PR that's code-clean but missing planned requirements is "Not ready" unless the omission is intentional. When an `inferred` plan has unaddressed requirements, note it in the verdict reasoning but do not block on it alone.

Do not include time estimates.

**Format verification:** Before delivering the report, verify the findings sections use pipe-delimited table rows (`| # | File | Issue | ... |`) not freeform text. If you catch yourself rendering findings as prose blocks separated by horizontal rules or bullet points, stop and reformat into tables.

**Caller consumption note (ARP-specific).** ARP's dispatch wrapper appends a JSON schema suffix to the prompt that overrides this table format when the caller wants machine-parseable output. When that suffix is present, emit the JSON array per the caller's schema instead of the pipe-delimited table. Only one output form — whichever the caller requested. Do not emit both.

## Quality Gates

Before delivering the review, verify:

1. **Every finding is actionable.** Re-read each finding. If it says "consider", "might want to", or "could be improved" without a concrete fix, rewrite it with a specific action. Vague findings waste engineering time.
2. **No false positives from skimming.** For each finding, verify the surrounding code was actually read. Check that the "bug" isn't handled elsewhere in the same function, that the "unused import" isn't used in a type annotation, that the "missing null check" isn't guarded by the caller.
3. **Severity is calibrated.** A style nit is never P0. A SQL injection is never P3. Re-check every severity assignment.
4. **Line numbers are accurate.** Verify each cited line number against the file content. A finding pointing to the wrong line is worse than no finding.
5. **Protected artifacts are respected.** Discard any findings that recommend deleting or gitignoring files in `docs/brainstorms/`, `docs/plans/`, or `docs/solutions/`.
6. **Findings don't duplicate linter output.** Don't flag things the project's linter/formatter would catch (missing semicolons, wrong indentation). Focus on semantic issues.

## Language-Aware Conditionals

This skill uses stack-specific reviewer agents when the diff clearly warrants them. Keep those agents opinionated. They are not generic language checkers; they add a distinct review lens on top of the always-on and cross-cutting personas.

Do not spawn them mechanically from file extensions alone. The trigger is meaningful changed behavior, architecture, or UI state in that stack.

## After Review

Report-only contract: after Stage 6 emits the findings (pipe-delimited table OR JSON array per caller schema), **stop.** No fixer queue. No policy questions. No commits. No pushes. No PRs. No `.context/` artifacts. No todo files. Everything routed actionable by the schema (`autofix_class`, `owner`) remains as metadata on the findings themselves — the caller (ARP or a human operator) decides what to do with them.

The full Stage 6 report is the deliverable. Nothing after it.

## Fallback

If the platform doesn't support parallel sub-agents, run reviewers sequentially. Everything else (stages, output format, merge pipeline) stays the same.

---

## Included References

### Persona Catalog

@./references/persona-catalog.md

### Subagent Template

@./references/subagent-template.md

### Diff Scope Rules

@./references/diff-scope.md

### Findings Schema

@./references/findings-schema.json

### Review Output Template

@./references/review-output-template.md
