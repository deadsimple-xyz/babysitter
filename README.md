# Babysitter

Supervisor for AI dev agents. Runs role-based coding sessions with **fresh context per step** — no degradation from long sessions.

```
babysitter ../my-app "finish the tests"
```

Babysitter spawns Claude Code agents (Manager, QA, Developer) one at a time, each in a clean session. A Brain (Claude API) evaluates every step and decides what happens next. If something goes wrong, it stops and tells you why.

## How It Works

```
You: babysitter ../my-app "implement login"
 │
 ├─ Brain: analyzes task → plan: manager → qa → developer
 │
 ├─ Manager (fresh claude session)
 │    writes .feature specs, exits
 │    Brain: "specs look good, next: qa"
 │
 ├─ QA (fresh claude session)
 │    writes tests from specs, runs them once, exits
 │    Brain: "tests written, 5 failing as expected, next: developer"
 │
 ├─ Developer (fresh claude session)
 │    reads qa-report, writes code, exits
 │    Babysitter runs tests externally
 │    Brain: "3 still failing, send back to developer"
 │
 ├─ Developer (fresh claude session — clean context)
 │    reads updated qa-report, fixes remaining, exits
 │    Babysitter runs tests → all pass
 │    Brain: "done"
 │
 └─ DONE
```

Every agent invocation is a **fresh Claude session**. No accumulated context, no degradation. The Brain makes all decisions via short, stateless API calls.

## Install

```bash
brew tap deadsimple-xyz/tap
brew install babysitter
```

Or clone and run directly:

```bash
git clone https://github.com/deadsimple-xyz/babysitter.git
cd babysitter
bin/babysitter ../my-app "finish the tests"
```

No gem dependencies — pure Ruby stdlib.

### Requirements

- **Claude Code CLI** (`claude`) — [install](https://docs.anthropic.com/en/docs/claude-code)
- **Anthropic API key** — for the Brain (see below)

## API Key Setup

Babysitter needs `ANTHROPIC_API_KEY` for the Brain — the component that analyzes tasks, evaluates agent output, and decides next steps. The agents themselves run through Claude Code (which has its own auth).

### Set it for the current session

```bash
export ANTHROPIC_API_KEY=sk-ant-...
babysitter ../my-app "fix the tests"
```

### Set it permanently

Add to your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
echo 'export ANTHROPIC_API_KEY=sk-ant-...' >> ~/.zshrc
source ~/.zshrc
```

### Get an API key

1. Go to [console.anthropic.com](https://console.anthropic.com/)
2. Create an account or sign in
3. Go to **API Keys** → **Create Key**
4. Copy the key (starts with `sk-ant-`)

The Brain uses Claude Sonnet by default — each call is ~1K tokens, so a full session costs a few cents.

## Usage

```bash
# Basic — Brain plans everything
babysitter <workdir> "<prompt>"

# Examples
babysitter ../my-app "implement the login feature"
babysitter ../my-app "finish the tests"
babysitter ../my-app "fix the failing auth tests"
babysitter . "add email validation"
```

Babysitter reads the project's `.hats/` directory to understand current state — what specs exist, what tests exist, what's passing or failing — and plans accordingly.

## What Each Role Does

| Role | Reads | Writes | Cannot touch |
|------|-------|--------|-------------|
| **Manager** | `.hats/shared/`, `.hats/designer/` | `.hats/manager/*.feature` | code, tests |
| **Designer** | `.hats/manager/`, `.hats/shared/` | `.hats/designer/` | code, tests |
| **CTO** | `.hats/manager/`, `.hats/designer/` | `.hats/shared/stack.md` | code, tests |
| **QA** | `.hats/manager/`, `.hats/shared/` | `.hats/qa/`, `.hats/shared/qa-report.md` | implementation code |
| **Developer** | `.hats/manager/`, `.hats/shared/qa-report.md` | project source code | `.hats/qa/`, specs |

Permissions are enforced by the MCP gate — the Developer literally can't write to test files, and QA can't write implementation code.

## Session Files

Every run creates a session directory at `~/.local/share/babysitter/sessions/`:

```
session-20260324-193541/
  task.md                      # Brain's analysis: what to do, success criteria
  step1_manager_output.txt     # Raw agent output
  manager_review.md            # Brain's evaluation
  step2_qa_output.txt
  qa_review.md
  step3_developer_output.txt
  step3_test_output.txt        # External test run results
  developer_review.md
  log.txt                      # Full timestamped log
```

If something goes wrong, read the review files — the Brain explains what happened and why it stopped.

## Command Gate

Every shell command an agent runs goes through the gate:

| Decision | Commands |
|----------|----------|
| **ALLOW** | `rspec`, `ruby`, `bundle`, `jest`, `pytest`, `curl`, `cat`, `ls`, `grep`, `git status/log/diff` |
| **DENY** | `rm -rf`, `git push main`, `deploy`, `DROP TABLE`, `rake *prod*` |
| **ASK** | everything else |

Gate rules are in `rules/gate.yml`.

## Limits

- **Max 10 steps** per session (safety limit)
- **Max 5 developer passes** — if tests still fail after 5 attempts, babysitter stops
- Brain stops immediately on role violations (developer editing tests, QA writing code, etc.)

## Compatible with Hats

Babysitter uses the same `.hats/` directory structure as the [Hats](https://github.com/deadsimple-xyz/hats) framework. You can:

1. Run babysitter for automated sessions
2. Jump into manual Hats mode (`claude --plugin-dir ../hats`) to fix something
3. Re-run babysitter to continue

They read and write the same files.

## License

MIT
