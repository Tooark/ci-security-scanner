# Summary

<!--
Explain what this PR does and why. Reference the issue(s) it closes.
Example: "Closes #42 — add trivy_ignorefile to the three Trivy templates."
-->

## Affected area(s)

- [ ] `templates/` — GitLab CI/CD components
- [ ] `action.yml` — GitHub composite Action
- [ ] `src/run-scanner.sh` — the runner behind the Action
- [ ] `scripts/` — validation run in CI and locally
- [ ] `.github/workflows/` — this repository's own CI
- [ ] `VERSION` — scanner image or component version
- [ ] `docs/` — onboarding guide
- [ ] `examples/` — copy-ready pipelines
- [ ] Governance / documentation only

## Type of change

- [ ] `feat` — new input, new scan, new capability
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `refactor` — no functional change
- [ ] `build` / `ci` — workflow or tooling change
- [ ] `chore` — version bumps, dependency updates
- [ ] Breaking change (describe it under "Consumer impact")

## Consumer impact

<!--
Does this change what runs inside someone else's pipeline? action.yml and
templates/ do; .github/workflows/ does not. Call out anything that raises a
requirement on the consumer's side — a new minimum runner version, a new
permission, a changed default, a removed input — and add it to CHANGELOG.md.
-->

- [ ] No consumer-visible change (this repo's own CI, docs or tooling only)
- [ ] Consumer-visible; described above and recorded in `CHANGELOG.md`

## Checklist

- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
- [ ] `python3 scripts/validate-templates.py` passes
- [ ] `./scripts/check-sync.sh` passes
- [ ] `shellcheck -s bash src/run-scanner.sh scripts/check-sync.sh` passes
- [ ] Version pins were changed only through `VERSION`
- [ ] `README.md` and `README.pt-BR.md` updated **and in sync** (if docs changed)
- [ ] `CHANGELOG.md` updated under `[Unreleased]`

### If this PR adds or renames an input

All four places, or `check-sync.sh` will say so:

- [ ] The template's `spec:inputs` — with `description`, and `options`/`regex` where they apply
- [ ] The template's `variables:` block, as `ARK_IN_*`
- [ ] `action.yml` — same input in `kebab-case`, staged as `ARK_IN_*` through `env:`
- [ ] `src/run-scanner.sh` — forwarded, and only when non-empty
- [ ] The default matches on both platforms, and an empty value is still never forwarded

## Notes for reviewers

<!-- Anything specific to focus on, alternatives considered, follow-up work, etc. -->
