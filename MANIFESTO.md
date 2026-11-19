# Engineering manifesto

Implementation principles for Agentaro. Based on the 24 engineering essentials of Rondo (E1–E6, https://workwithrondo.com/x); this file records the concrete decisions for this project. Decisions not yet made are marked `[TO BE DETERMINED]` and settled in specification sessions.

## Decided

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
- **Local CI:** `bin/ci` (Rails 8.1) is the pipeline; failures are never bypassed.

## To be determined

- Container stack — postponed (see "No Docker for now"); on macOS the Claude login lives in the Keychain, which a Linux container cannot read. [TO BE DETERMINED]
- Interface (web panel, CLI) and its authentication. [TO BE DETERMINED]
- License. [TO BE DETERMINED]
