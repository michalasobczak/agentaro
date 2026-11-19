# Instructions for AI assistants

This project follows the Rondo methodology and Context-Driven Development (CDD): https://workwithrondo.com

## Sources of truth

| Artifact | Role |
|---|---|
| `README.md` | "Here and now": current domain picture, functional architecture, critical path, spec list with statuses. |
| `specs/` | "I would like": intent, scope, rules and gates of every change. Fixed 9-section structure — see `specs/TEMPLATE.md`. |
| `CHANGELOG.md` | "This is what was actually built", by date. |
| Tests | Proof of what the CHANGELOG claims. |
| `MANIFESTO.md` | Engineering principles and concrete implementation decisions. |

## Rules

- Do not guess requirements. Ask Socratic questions until goal, scope and acceptance criteria are clear. Mark gaps as `[TO BE DETERMINED]` and ask the owner.
- Implement only closed specifications. A spec is closed after the owner's review.
- Every change ends with a CHANGELOG entry and an updated README.
- Tests are mandatory. Do not change expected results just to make a test pass.
- Fixes: reproduce with a test, fix the cause, add a CHANGELOG entry (and a spec when behaviour changes).
- After every implemented specification, run a security analysis of this spec and all previous ones: look for regressions and gaps (Rondo B20). Findings are fixed like any change: spec, reproducing test, CHANGELOG entry. A round ends only after the analysis.
- Revalidate context after each cycle: rebuild it from specs, CHANGELOG, README and tests, checked against the code; mark outdated claims as invalid.
- Built in public: never commit secrets, tokens, subscription credentials or personal data. Use the GitHub noreply address for commits.

## Commands

Ruby 4.0.10 must be on `PATH` (on the owner's Mac: `export PATH="/opt/homebrew/opt/ruby/bin:$PATH"`).

- `bin/setup --skip-server` — install gems, prepare SQLite databases
- `bin/rails test` — tests (must pass before every commit)
- `bin/ci` — local CI (setup, tests, seeds)
- `bin/dev` — run the app on http://localhost:3000
