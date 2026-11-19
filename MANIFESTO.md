# Engineering manifesto

Implementation principles for Agentaro. Based on the 24 engineering essentials of Rondo (E1–E6, https://workwithrondo.com/x); this file records the concrete decisions for this project. Decisions not yet made are marked `[TO BE DETERMINED]` and settled in specification sessions.

## Decided

- **Intended use (owner, 2026-11-19):** personal, family or small-business use with few users; no enterprise use for now; never a public internet runtime — only secured local environments. Every security decision is sized for this scope; changing it requires a new specification.
- **Not sold (owner, 2026-11-19):** Agentaro is not a commercial product or service.
- **On-prem:** the system and its data run on the owner's machines. No cloud orchestrators or hosted memory services.
- **Vendor-agnostic:** provider-specific code lives only behind a provider adapter. The rest of the system does not depend on any single vendor.
- **Subscriptions are first-class:** agents can run on subscription plans (e.g. Claude Code, Codex CLI signed in on the host), not only on API keys.
- **Least privilege:** every agent task declares what it may access; read-only by default.
- **Secrets never in the repository**, including subscription credentials and tokens. This repository is public.
- **Tests are mandatory;** fixes address causes and come with a regression test.
- **Security analysis after every implemented specification** (Rondo B20).
- **Commits:** coherent and descriptive, signed with the GitHub noreply address.
- **Stack (spec 001):** latest stable Ruby (4.0.10) and Ruby on Rails (8.1.4.1), generated with `--minimal`. New gems or Rails components need a reason in a specification.
- **Storage:** SQLite only, so a fresh clone runs as is. Database files are never committed.
- **No Docker for now:** agents run on subscriptions signed in on the host (Claude Code, Codex CLI); a container would need extra work to reach those logins. Revisit later (Rondo E18).
- **No encrypted Rails credentials** in the repository: secrets come from environment variables.
- **HTTPS (owner, 2026-11-19):** provided by a TLS-terminating proxy in front of the app, e.g. `tailscale serve`; the app listens only on localhost and does not depend on the proxy vendor. Allowed hostnames come from the environment, never from the repository. No separate specification.
- **Authentication (spec 002):** Rails 8 built-in authentication (`has_secure_password`, database sessions), no Devise; TOTP with `rotp`, QR codes with `rqrcode`. No outgoing mail: password recovery through admin-generated one-time links; admins only on the command line.
- **Audit (specs 003, 004):** own Rack middleware and model concern, no audit gems; separate SQLite database; hash chains; writes that skip callbacks (`update_all`, `update_columns`, …) are forbidden in application code — a test enforces it.
- **Running (spec 005):** real use is production mode via `bin/start` (generic error pages, `AGENTARO_HTTPS_PROXY=1`, allowed hostnames from `AGENTARO_HOSTS`); `bin/dev` only for development on localhost. Tests run in proxy mode (set in `config/environments/test.rb`).
- **Failed sign-ins (spec 005, F4):** counted per typed username, never per account, so failures cost the same for known and unknown names.
- **Interface (spec 006):** plain CSS with design tokens, system fonts, inline SVG icons, no CSS framework; phone menu uses `<details>`.
- **JavaScript (spec 007, owner: "allow JavaScript"):** only first-party files in `app/assets/javascripts/`, no libraries, no CDN; CSP `script-src 'self'` (no inline scripts, no eval). Scripts never build HTML from data. Everything must also work through plain forms when the script is missing. Breakpoints: phone < 640 px, tablet 640–1099 px, desktop above.
- **Time (spec 007):** stored in UTC, shown and computed in Europe/Warsaw (`config.time_zone`); recurring tasks keep their wall-clock time across daylight-saving changes.
- **Machine-local secrets:** generated on first boot into `storage/secrets.yml` (mode 0600, ignored by git); environment variables override.
- **Executors (spec 008, owner):** AI tools are reached as CLIs logged in on the host or as local APIs without a key; Agentaro stores no API keys or tokens. What may run is fixed in code (`Executor::PRESETS`), never typed in the web; programs start without a shell and without Agentaro's environment.
- **Agent identity (specs 009, 011, owner):** the master prompt is written by people only; what an agent learns lives in Agentaro's own memory (SQLite), never in a vendor tool's memory, so it survives a change of executor.
- **Running agents (spec 010):** the scheduler is a thread in the app, not a job system; runs never start late; each run gets its own folder outside `storage/`, and tools are confined by the vendor's own sandbox (Claude Code sandbox settings, Codex `workspace-write`).
- **Local CI:** `bin/ci` (Rails 8.1) is the pipeline; failures are never bypassed.

## To be determined

- Container stack — postponed (see "No Docker for now"); on macOS the Claude login lives in the Keychain, which a Linux container cannot read. [TO BE DETERMINED]
- Interface (web panel, CLI) and its authentication. [TO BE DETERMINED]
- License. [TO BE DETERMINED]
