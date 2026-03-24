# Babysitter

Supervisor for AI dev agents. Runs role-based coding sessions with **fresh context per step** — no degradation from long sessions.

Built on the [Hats](https://github.com/deadsimple-xyz/hats) framework. Hats defines the roles and project structure. Babysitter automates the pipeline — replacing the human who would normally switch between roles.

## Install

```bash
brew tap deadsimple-xyz/tap
brew install babysitter
hash -r   # or open a new terminal
```

Requires [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code).

## Usage

```bash
cd my-app
babysitter .
```

First run asks for your API key (get one at [console.anthropic.com](https://console.anthropic.com/settings/keys)):

```
$ babysitter .

No API key found.

Babysitter needs an Anthropic API key for the Brain.
Get one at: https://console.anthropic.com/settings/keys

Paste your API key: sk-ant-...
Saved to ~/.babysitter/key.json

What should I do?
> finish the tests
```

That's it. Babysitter reads the project state, plans which roles to run, and executes.

### Update or change the key

```bash
nano ~/.babysitter/key.json
```

Or delete and babysitter will ask again:

```bash
rm ~/.babysitter/key.json
```

## How It Works

```
babysitter .
> implement login
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

## Project Setup

Babysitter works with projects that have a `.hats/` directory. Set one up with [Hats](https://github.com/deadsimple-xyz/hats):

```bash
cd my-app
claude --plugin-dir ../hats
/hats:init
```

Or just run `babysitter .` on a fresh project — the Manager will create the structure.

### Two ways to work

| | **Hats (manual)** | **Babysitter (automated)** |
|---|---|---|
| **How** | `claude --plugin-dir ../hats` | `babysitter .` |
| **Who switches roles** | You | The Brain |
| **Context** | One long session (can degrade) | Fresh session per step |
| **Best for** | Exploring, discussing, fixing | Grinding through implementation |

You can mix both. Start with babysitter, it gets stuck, jump into Hats to fix something, then re-run babysitter.

## Roles

| Role | Writes | Cannot touch |
|------|--------|-------------|
| **Manager** | `.hats/manager/*.feature` | code, tests |
| **Designer** | `.hats/designer/` | code, tests |
| **CTO** | `.hats/shared/stack.md` | code, tests |
| **QA** | `.hats/qa/`, `.hats/shared/qa-report.md` | implementation code |
| **Developer** | project source code | `.hats/qa/`, specs |

Enforced by the MCP gate — the Developer can't write to test files, QA can't write code.

## Command Gate

| Decision | Commands |
|----------|----------|
| **ALLOW** | `rspec`, `ruby`, `bundle`, `jest`, `pytest`, `curl`, `cat`, `ls`, `grep`, `git status/log/diff` |
| **DENY** | `rm -rf`, `git push main`, `deploy`, `DROP TABLE` |

Rules in `rules/gate.yml`.

## Limits

- **Max 10 steps** per session
- **Max 5 developer passes** — stops if tests still fail
- Stops immediately on role violations

## Session Files

Every run saves to `~/.local/share/babysitter/sessions/`:

```
session-20260324-193541/
  task.md                      # Brain's plan and success criteria
  step1_manager_output.txt     # Raw agent output
  manager_review.md            # Brain's evaluation
  step3_test_output.txt        # Test results
  log.txt                      # Full log
```

## License

MIT
