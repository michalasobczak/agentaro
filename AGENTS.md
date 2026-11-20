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
- Interface: no inline `style=` or `<script>` (blocked by the Content-Security-Policy; a test enforces it). Scripts are first-party files only; use `textContent`, never `innerHTML`. Calendar positions come from classes in `calendar_grid.css` (generated). Mark admin-only UI `desktop-only` and use `desktop_only_note` on admin pages (spec 006).
- Built in public: never commit secrets, tokens, subscription credentials or personal data. Use the GitHub noreply address for commits.

## Commands

Ruby 4.0.10 must be on `PATH` (on the owner's Mac: `export PATH="/opt/homebrew/opt/ruby/bin:$PATH"`).

- `bin/setup --skip-server` — install gems, prepare SQLite databases
- `bin/rails test` — tests (must pass before every commit)
- `bin/ci` — local CI (setup, tests, seeds)
- `bin/dev` — development server on http://localhost:3000 (this machine only)
- `bin/start` — real use: production mode behind an HTTPS proxy; needs `AGENTARO_HOSTS` (in `storage/settings.env`). It precompiles assets into `public/assets`; development and test ignore that folder and always compile live.
- Throwaway browser checks: never use the test databases (tests run in HTTPS mode and the data leaks into later runs). Use a development server on separate files: `DATABASE_URL=sqlite3:storage/demo.sqlite3 AUDIT_DATABASE_URL=sqlite3:storage/demo_audit.sqlite3`, and delete them afterwards — plus `var/runs/development` if runs were made; never touch `var/runs/production`. Open the demo at `http://demo.localhost:<port>` (the browser may keep a Secure session cookie for `localhost` and `127.0.0.1`). Seed text with non-ASCII characters only with `LANG=en_US.UTF-8`.
- `bin/rails agentaro:admin:create` — first admin (interactive: password, QR code); prefix `RAILS_ENV=production` for production data
- `bin/rails agentaro:audit:verify` / `agentaro:audit:prune` — audit chains

Voice for the director chat (spec 017), optional — files in `storage/voice/` (not tracked):
- `brew install whisper-cpp`, then the model `ggml-large-v3-turbo-q5_0.bin` from huggingface.co/ggerganov/whisper.cpp into `storage/voice/`;
- `python3 -m venv storage/voice/piper-venv && storage/voice/piper-venv/bin/pip install piper-tts`, then the voice `pl_PL-gosia-medium.onnx` (+ `.onnx.json`) from huggingface.co/rhasspy/piper-voices into `storage/voice/`;
- other paths: `AGENTARO_WHISPER_BIN`, `AGENTARO_WHISPER_MODEL`, `AGENTARO_PIPER_BIN`, `AGENTARO_PIPER_VOICE`. Without them the voice button is disabled; text chat works.

Docker for steps in spaces with a working folder (spec 018), optional: `brew install colima docker`, `colima start` (or `brew services start colima` to start it with the Mac). The socket is found at `~/.colima/default/docker.sock` or `~/.docker/run/docker.sock`, or set `AGENTARO_DOCKER_SOCKET`.

Security tools used in the analysis (not in the Gemfile): `gem install bundler-audit brakeman`, then `bundle-audit check --update` and `brakeman -q`.
