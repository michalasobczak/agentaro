# CHANGELOG

## 2026-11-19

- Repository created: `michalasobczak/agentaro`, public, built in public.
- CDD artifacts set up following workwithrondo.com/x: `README.md`, `AGENTS.md` (+ `CLAUDE.md`), `MANIFESTO.md`, `specs/TEMPLATE.md` (nine sections), `CHANGELOG.md`. No code or tests yet.
- Spec 001 Initial project structure: Ruby 4.0.10 (Homebrew), Rails 8.1.4.1 generated with `rails new --minimal --database=sqlite3` (only Active Record, Action Controller, Action View, test unit; Propshaft, Puma, sqlite3). Removed from the generated app: PWA views, `config/master.key` and `config/credentials.yml.enc` (nothing to encrypt yet; a public repo would carry a file nobody can decrypt). Docker, Kamal, CI workflows, jobs, mail, JavaScript tooling not generated. `.gitignore` merged with Rails entries; SQLite files ignored.
- Test `test/integration/health_check_test.rb` (`/up` returns 200). Gates: `bin/ci` passed (1 test, seeds); server booted, `/up` 200; no database, key or `.env` tracked.
- Security analysis (B20) after spec 001: `bundle-audit` — no known vulnerabilities (1379 advisories, 2026-11-19); dev server listens on 127.0.0.1/::1 only; production defaults keep `force_ssl`; no secrets in the repository. Note: production will need `SECRET_KEY_BASE` from the environment. No findings to fix.
