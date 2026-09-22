# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.1.0] - 2026-09-22

### Added

- Onboarding guide in `docs/`, deployed to GitHub Pages by
  `.github/workflows/pages.yml`. It walks the repository file by file and
  records the reasoning behind each decision, for readers who know software
  development but not CI.
- OSS governance files modelled on `Tooark/base-images`: `SECURITY.md`,
  `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SUPPORT.md`, `.github/CODEOWNERS`,
  `.github/FUNDING.yml`, a pull request template and issue forms.
- `SUPPORTED-INTEGRATIONS.md`, recording the support boundaries previously
  scattered across header comments and README gotchas: supported platforms,
  runners and executors, the component-to-image version pairing, and the
  network destinations a scan needs.
- `scripts/check-sync.sh` now also verifies that every copy-paste reference in
  the README, the examples, the onboarding guide and
  `SUPPORTED-INTEGRATIONS.md` pins `COMPONENT_VERSION`. Only the three forms a
  reader actually copies are matched; prose explaining the tagging scheme is
  not. Without it, a release silently left the quick start teaching the
  previous version.

### Changed

- **Minimum Actions Runner version on self-hosted runners.** `action.yml` now
  references `actions/upload-artifact@v7` and `actions/cache@v6`, which run on
  Node.js 24 and require Actions Runner **2.327.1 or newer** — the floor
  introduced by `actions/upload-artifact@v6`. GitHub-hosted runners are
  unaffected. A self-hosted runner older than that will fail the artifact
  upload and the cache steps once `v1` or `v1.0` moves to a release containing
  this change.
- This repository's own workflows moved to `actions/checkout@v7`,
  `actions/configure-pages@v6` and `actions/deploy-pages@v5`. No consumer
  impact; the runners had started warning that Node 20 is deprecated.
- The GitHub example in `examples/` moved to `actions/checkout@v7`, so a reader
  copying it does not start on a version the runner already warns about.

### Fixed

- `scripts/check-sync.sh` no longer trips ShellCheck `SC2013`, which failed the
  CI lint step on every commit and blocked every Dependabot pull request. The
  `ARK_IN_*` parity check now reads names with `while read` fed by process
  substitution, which keeps the loop in the current shell so the failure flag
  survives it.
- The onboarding guide is linked by its canonical address,
  `https://tooark.com/ci-security-scanner/`. The `tooark.github.io` URL used
  until now is a redirect: the organization serves Pages from a custom domain.

## [1.0.0] - 2026-09-21

First release. Pins `ghcr.io/tooark/security-scanner:1.9`.

### Added

- GitLab CI/CD component templates, one job each: `full-scan`, `image-scan`,
  `filesystem-scan`, `config-scan`, `repo-scan`, `dockerfile-lint` and
  `secret-scan`. Usable through `include: remote:` or from a CI/CD Catalog.
- GitHub composite Action (`action.yml`) covering the same seven scans through
  a `command` input, with `exit-code`, `reports-dir` and `report` outputs.
- Shared precedence rule across both platforms: an empty input is never
  forwarded, so `input > CI variable > image default` holds everywhere.
- Secret passthrough (`TRIVY_TOKEN`, `REPORT_TOKEN`, registry credentials and
  friends) via environment rather than inputs.
- Trivy database caching on both platforms, skipped for the two scans that do
  not read the database. GitLab caches `.cache/trivy` under a fixed key; GitHub
  uses `actions/cache` with one entry per day per scanner version, saved from
  an explicit step so a tripped failure gate still populates it.
- `scripts/validate-templates.py` and `scripts/check-sync.sh`, which fail CI on
  undeclared or unused inputs, broken `ARK_IN_*` wiring, and version pins that
  drift from `VERSION`.
- Release workflow that validates, checks the tag against `VERSION`, publishes
  the GitHub release and moves the floating `vMAJOR` and `vMAJOR.MINOR` tags.
- Mirror pipeline in `examples/gitlab-catalog-mirror/` that polls GitHub
  releases on a schedule and republishes to a self-hosted CI/CD Catalog.
- Copy-ready examples for both platforms in `examples/`.

### Security

- `extra_args` is split under `set -f`, so a value such as `*` is passed
  literally instead of expanding against the files in the repository.
- The catalog mirror hands its push token to git through a credential helper
  rather than a remote URL, keeping it out of argv and out of git's errors.
- The third-party `actionlint` image is pinned by digest, and Dependabot keeps
  the remaining action references current.
- The reports directory is tightened again once a scan finishes, limiting the
  world-writable window the non-root container user requires.
- Documented the disclosure paths that configuration can open: the Docker
  socket mount, unredacted Betterleaks output, and Trivy's secret scanner
  writing findings into an uploaded artifact.

[Unreleased]: https://github.com/Tooark/ci-security-scanner/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Tooark/ci-security-scanner/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Tooark/ci-security-scanner/releases/tag/v1.0.0
