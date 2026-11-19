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

## To be determined

- Language, runtime and package manager. [TO BE DETERMINED]
- Storage (e.g. SQLite or files). [TO BE DETERMINED]
- Container stack — the essentials prefer Docker Compose; note that subscription logins on macOS live in the Keychain, which a Linux container cannot read. [TO BE DETERMINED]
- Interface (web panel, CLI) and its authentication. [TO BE DETERMINED]
- License. [TO BE DETERMINED]
