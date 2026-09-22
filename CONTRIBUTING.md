# Contributing to ci-security-scanner

First off, thank you for considering contributing to
**Tooark ci-security-scanner**! 🎉

This repository publishes one thing twice: the CI configuration that runs the
Tooark `security-scanner` image, as GitLab CI/CD component templates and as a
GitHub composite Action. Keeping those two front ends interchangeable is the
constraint that shapes almost every rule below.

If you are new to CI pipelines, read the
[onboarding guide](https://tooark.github.io/ci-security-scanner/) first — it
explains what each file does and why.

## Table of contents

- [Ways to contribute](#ways-to-contribute)
- [What belongs here and what does not](#what-belongs-here-and-what-does-not)
- [Repository layout](#repository-layout)
- [Development workflow](#development-workflow)
- [Adding or renaming an input](#adding-or-renaming-an-input)
- [Versioning](#versioning)
- [Commit convention](#commit-convention)
- [Documentation standards](#documentation-standards)
- [Releasing](#releasing)
- [Pull Request checklist](#pull-request-checklist)
- [Community](#community)

---

## Ways to contribute

- 🐛 **Report bugs** — open an issue with the `bug` template.
- ✨ **Suggest improvements** — open an issue with the `feature` template.
- 📖 **Improve documentation** — the READMEs (English and Portuguese) and the
  onboarding guide in `docs/` are first-class.
- 🔒 **Review security** — question a default, a mount, or a place where a
  value could reach a shell.
- 💻 **Write code** — templates, the Action, the runner script, validation.

---

## What belongs here and what does not

This component **forwards configuration**; it does not implement scanning.
Trivy, Hadolint, Betterleaks and the `ark-tools` CLI live in the image, built
from [`Tooark/base-images`](https://github.com/Tooark/base-images/tree/main/security-scanner).

| Change                                               | Repository    |
| ---------------------------------------------------- | ------------- |
| A new input that forwards a variable the image reads | here          |
| An input behaves differently on GitLab and GitHub    | here          |
| A job fails before `ark-tools` starts                | here          |
| A tool needs a flag the image does not expose        | `base-images` |
| The report format or the consolidated envelope       | `base-images` |

Before proposing a new input, check that it cannot already be done by
redeclaring the generated GitLab job or setting the matching environment
variable — a generated job is an ordinary job, and every image variable is
already forwarded.

---

## Repository layout

```text
templates/          GitLab CI/CD component templates, one job each
action.yml          GitHub composite Action
src/run-scanner.sh  Shared runner behind the Action
scripts/            Validation run in CI and locally
examples/           Ready-to-copy pipelines for both platforms
docs/               Onboarding guide, published to GitHub Pages
VERSION             Single source of truth for versions
```

---

## Development workflow

```bash
python3 -m pip install pyyaml

python3 scripts/validate-templates.py   # structure, input wiring, dead inputs
./scripts/check-sync.sh                 # version pinning and cross-platform parity
shellcheck -s bash src/run-scanner.sh scripts/check-sync.sh
```

Run all three before opening a PR. CI runs them, plus `actionlint`, plus a
self-scan in which the Action in this repository scans this repository.

**Install `shellcheck` locally.** It is the one check with no Python fallback,
it fails on `info`-level findings, and it is the easiest of the three to
discover only after CI has turned red.

`validate-templates.py` exists because GitLab reports these problems only when
a pipeline is created — which happens in a _consuming_ project, not here. A
template that references an undeclared input, or declares one it never uses,
must never reach a tag.

---

## Adding or renaming an input

An input lives in **four places**. Miss one and `check-sync.sh` fails the
build — which is the point, because the failure mode it replaces is silent:
the input exists in the documentation, the user sets it, and nothing happens.

1. The template's `spec:inputs` — with a `description`, plus `options` or
   `regex` where the value is constrained. This block is the authoritative
   reference for users.
2. The template's `variables:` block, staged as `ARK_IN_<NAME>`.
3. `action.yml` — the same input in `kebab-case`, with the same default,
   handed to the runner through `env:` as `ARK_IN_<NAME>`.
4. `src/run-scanner.sh` — forwarded to the container.

Three rules that are not negotiable:

**Names and defaults match across platforms.** GitLab uses `snake_case`,
GitHub uses `kebab-case`; everything else about the input is identical. A
change that lands on one side only needs a stated reason.

**An empty input is never forwarded.** That is what makes
`input > CI variable > image default` hold. Forwarding an empty value would
overwrite, with an empty string, a variable the project set globally.

**Inputs never reach a shell as text.** They arrive as environment variables.
A value spliced into a `run:` block or a `script:` line is a command injection
waiting for the right input.

---

## Versioning

The project follows [Semantic Versioning](https://semver.org/).

[`VERSION`](VERSION) is the single source of truth for both the component
version and the scanner image tag that every template and the Action pin:

```text
COMPONENT_VERSION=1.0.0
SCANNER_IMAGE=ghcr.io/tooark/security-scanner
SCANNER_VERSION=1.9
```

Bumping the scanner image is a three-step change: edit `VERSION`, run
`./scripts/check-sync.sh`, update the pins it flags. Never edit a pin directly.

What counts as breaking here is anything that changes what runs inside a
consumer's pipeline: a removed or renamed input, a changed default, or a new
minimum runner version pulled in by an action referenced from `action.yml`.
Record it in `CHANGELOG.md` — the consumer cannot see the diff, only the tag.

---

## Commit convention

We use [**Conventional Commits**](https://www.conventionalcommits.org/).

Format:

```text
<type>(<scope>): <short summary>
```

Common types: `feat`, `fix`, `docs`, `refactor`, `build`, `ci`, `chore`.

Use the area as the scope when it applies:

```text
feat(templates): add trivy_ignorefile to the Trivy scans
fix(action): treat an empty path as the workspace root
chore(version): bump the scanner image to 1.10
docs(readme): document the distributed cache caveat
```

---

## Documentation standards

- The repository ships a **bilingual README**: `README.md` in English and
  `README.pt-BR.md` in Portuguese, with the language selector at the top.
  **Keep both in sync** — a change in one requires the same change in the
  other.
- Every input is documented in the template's `spec:inputs` block. That block
  is the reference; the README summarizes, it does not replace it.
- `docs/` holds the onboarding guide, published to GitHub Pages. It explains
  _why_ a decision was made; the README explains _how_ to use the component.
  Resist adding a third place that says the same thing — there is no
  `check-sync.sh` for prose.
- Comments in the templates and in `src/run-scanner.sh` record the reason a
  line exists, not what it does. Several of them are the only surviving record
  of a bug that took a while to find.

---

## Releasing

Releases are cut from tags:

1. Update `COMPONENT_VERSION` in `VERSION`.
2. Move the `[Unreleased]` entries in `CHANGELOG.md` under the new version.
3. Tag `vMAJOR.MINOR.PATCH` and push it.

[`.github/workflows/release.yml`](.github/workflows/release.yml) validates the
templates, **refuses a tag that disagrees with `COMPONENT_VERSION`**, creates
the release with generated notes, and force-moves the floating `vMAJOR` and
`vMAJOR.MINOR` tags.

Marketplace listing is a manual opt-in the API cannot set: open the release on
GitHub and tick _Publish this Action to the GitHub Marketplace_.

The GitLab CI/CD Catalog only lists components hosted on the GitLab instance
itself, so publishing there goes through the mirror project described in
[`examples/gitlab-catalog-mirror/`](examples/gitlab-catalog-mirror/).

---

## Pull Request checklist

The [PR template](.github/PULL_REQUEST_TEMPLATE.md) carries the full list. The
short version:

- [ ] The three local validations pass
- [ ] A new input landed in all four places
- [ ] Names and defaults match on both platforms
- [ ] `README.md` and `README.pt-BR.md` are in sync
- [ ] `CHANGELOG.md` has an `[Unreleased]` entry
- [ ] Consumer-visible changes are called out explicitly

---

## Community

- 💬 Questions and support: [`SUPPORT.md`](SUPPORT.md)
- 🔒 Security reports: [`SECURITY.md`](SECURITY.md) — never a public issue
- 🤝 Expected behaviour: [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md)
