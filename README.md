<div align="left">
  <img src="media/banner-ci-security-scanner.png" alt="CI Security Scanner" width="100%" />
</div>

# CI Security Scanner

Reusable CI configuration for the Tooark
[`security-scanner`](https://github.com/Tooark/base-images/tree/main/security-scanner)
image — **Trivy** (vulnerabilities), **Hadolint** (Dockerfile lint) and
**Betterleaks** (secret detection) behind one `ark-tools` CLI, producing a
single `ark-report-tools v1.2` report.

One repository, two front ends:

- **GitLab** — CI/CD component templates in [`templates/`](templates/), usable
  through `include: remote:` from anywhere, or published to a CI/CD Catalog.
- **GitHub** — a composite Action defined by [`action.yml`](action.yml).

Input names, defaults and precedence are the same on both sides; only the
syntax differs.

New to CI pipelines? The
[onboarding guide](https://tooark.github.io/ci-security-scanner/) walks through
every file in this repository and the reasoning behind each decision, written
for readers who know software development but not CI. Source in
[`docs/`](docs/).

🌍 **Languages:** ![USA Flag](https://flagcdn.com/w20/us.png) **English (this file)** · [![Brazil Flag](https://flagcdn.com/w20/br.png) Português](README.pt-BR.md)

---

## Contents

- [Quick start](#quick-start)
- [Templates and commands](#templates-and-commands)
- [Trivy database cache](#trivy-database-cache)
- [Inputs](#inputs)
- [How precedence works](#how-precedence-works)
- [Secrets](#secrets)
- [Security notes](#security-notes)
- [Overriding what inputs do not expose](#overriding-what-inputs-do-not-expose)
- [Versioning](#versioning)
- [Publishing](#publishing)
- [Gotchas](#gotchas)
- [Repository layout](#repository-layout)
- [Development](#development)
- [License](#license)

---

## Quick start

### GitLab — remote include

Works on gitlab.com and on any instance that can reach
`raw.githubusercontent.com`. No catalog required.

```yaml
include:
  - remote: "https://raw.githubusercontent.com/Tooark/ci-security-scanner/v1.0.0/templates/full-scan.yml"
    inputs:
      stage: test
      image: "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
      trivy_severity: "CRITICAL,HIGH"
      hadolint_failure_level: "warning"
```

### GitLab — CI/CD Catalog

Once the [mirror project](examples/gitlab-catalog-mirror/) has published a
version to your instance:

```yaml
include:
  - component: $CI_SERVER_FQDN/tooark/ci-security-scanner/full-scan@1.0.0
    inputs:
      image: "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
      trivy_severity: "CRITICAL,HIGH"
```

### GitHub Actions

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0 # Betterleaks needs the full git history

- uses: Tooark/ci-security-scanner@v1.0.0
  with:
    command: full-scan
    image: "myapp:${{ github.sha }}"
    docker-socket: "true" # only when scanning an image built on this runner
    trivy-severity: CRITICAL,HIGH
```

Longer examples live in [`examples/`](examples/).

---

## Templates and commands

Each GitLab template generates exactly one job. On GitHub the same scans are
selected through the `command` input of the single Action.

| GitLab template                                        | Action `command`  | What it does                                                    |
| ------------------------------------------------------ | ----------------- | --------------------------------------------------------------- |
| [`full-scan.yml`](templates/full-scan.yml)             | `full-scan`       | Image + source + secrets + Dockerfile lint, one merged report   |
| [`image-scan.yml`](templates/image-scan.yml)           | `image-scan`      | Trivy vulnerability scan of a container image                   |
| [`filesystem-scan.yml`](templates/filesystem-scan.yml) | `filesystem-scan` | Trivy scan of the source tree (lockfiles, OS and language deps) |
| [`config-scan.yml`](templates/config-scan.yml)         | `config-scan`     | Trivy IaC / misconfiguration scan                               |
| [`repo-scan.yml`](templates/repo-scan.yml)             | `repo-scan`       | Trivy repository scan; accepts a remote URL                     |
| [`dockerfile-lint.yml`](templates/dockerfile-lint.yml) | `dockerfile-lint` | Hadolint on one Dockerfile                                      |
| [`secret-scan.yml`](templates/secret-scan.yml)         | `secret-scan`     | Betterleaks over the working tree and git history               |

Reports land in `scan-reports/` and are uploaded as artifacts. `full-scan` also
writes the consolidated `full-scan-report.json`.

### Failure gates

| Tool        | Fails when                                     | Turn it off with                        |
| ----------- | ---------------------------------------------- | --------------------------------------- |
| Trivy       | A severity in `trivy_severity_fail` has a fix  | `trivy_exit_code: "0"`                  |
| Hadolint    | A finding at `hadolint_failure_level` or above | `hadolint_failure_level: "none"`        |
| Betterleaks | Any secret is detected                         | `betterleaks_fail_on_findings: "false"` |

On GitHub, `soft-fail: "true"` turns any gate into the `exit-code` output
instead of failing the step.

---

## Trivy database cache

Downloading the vulnerability database on every build is the slowest part of a
scan and the easiest way to hit registry rate limits, so both platforms cache
it. `dockerfile-lint` and `secret-scan` skip the cache entirely — Hadolint and
Betterleaks never read the database.

**GitLab** points `TRIVY_CACHE_DIR` at `$CI_PROJECT_DIR/.cache/trivy` and caches
that path under the fixed key `ark-trivy-db`, so every branch shares one
database.

> On a self-hosted instance, runner caches are stored on the runner's own disk
> by default. With several runners, a job only hits the cache when it lands on
> the runner that wrote it. Configuring
> [distributed caching](https://docs.gitlab.com/runner/configuration/autoscale/#distributed-runners-caching)
> (S3 or equivalent) in `config.toml` is what makes the hit rate consistent.

**GitHub** keeps the database in `RUNNER_TEMP`, which the job wipes on exit, so
the mount alone would only help across steps. `actions/cache` carries it
between runs with one entry per day per scanner version, falling back to the
previous day so Trivy refreshes an existing database rather than fetching a
whole one.

The save is a separate `actions/cache/save` step rather than the automatic post
step, because the post step is skipped when an earlier step failed — and this
action fails by design when a gate trips. Without the split, only repositories
that found nothing would ever populate the cache.

### Turning it off or freezing it

| Goal                     | GitLab                            | GitHub                 |
| ------------------------ | --------------------------------- | ---------------------- |
| Disable the cache        | Override the job with `cache: []` | `trivy-cache: "false"` |
| Reuse without refreshing | `TRIVY_SKIP_DB_UPDATE: "true"`    | same, as job `env`     |

A cached database is still refreshed when Trivy considers it stale; the cache
saves the download, it does not freeze the data. `TRIVY_SKIP_DB_UPDATE` does
freeze it, which trades result accuracy for speed — the image forwards it to
Trivy, which reads the variable natively.

---

## Inputs

GitLab uses `snake_case`, GitHub Actions uses `kebab-case`. Otherwise the names
and meanings match one to one.

### Present on every template

| GitLab                 | Action                    | Default                           | Notes                                                               |
| ---------------------- | ------------------------- | --------------------------------- | ------------------------------------------------------------------- |
| `job_name`             | —                         | `security:<command>`              | Change it to generate the job more than once                        |
| `stage`                | —                         | `test`                            | The stage must exist in the pipeline                                |
| `scanner_image`        | `scanner-image`           | `ghcr.io/tooark/security-scanner` |                                                                     |
| `scanner_version`      | `scanner-version`         | `1.9`                             | Pin it                                                              |
| `allow_failure`        | `soft-fail`               | `false`                           | GitLab marks the job non-blocking; the Action reports the exit code |
| `rules`                | —                         | `[{when: on_success}]`            | GitHub uses the workflow's own `if:`                                |
| `tags`                 | —                         | `[]`                              | Runner selection                                                    |
| `timeout`              | —                         | `1h`                              |                                                                     |
| `reports_dir`          | `reports-dir`             | `scan-reports`                    |                                                                     |
| `artifacts_expire_in`  | `artifact-retention-days` | `7 days` / `7`                    | Artifact retention                                                  |
| `report_url`           | `report-url`              | —                                 | Webhook targets, comma-separated                                    |
| `report_fail_on_error` | `report-fail-on-error`    | —                                 | Fail when the upload fails                                          |
| `extra_args`           | `extra-args`              | —                                 | Flags forwarded after the `--` separator                            |

### Scan targets

| GitLab        | Action        | Used by                                                           |
| ------------- | ------------- | ----------------------------------------------------------------- |
| `image`       | `image`       | `full-scan` (empty skips the image step), `image-scan` (required) |
| `scan_path`   | `path`        | `full-scan`                                                       |
| `path`        | `path`        | `filesystem-scan`, `config-scan`, `secret-scan`                   |
| `target`      | `target`      | `repo-scan`                                                       |
| `dockerfile`  | `dockerfile`  | `dockerfile-lint`                                                 |
| `dockerfiles` | `dockerfiles` | `full-scan`, comma-separated, relative to the scan path           |

On GitHub, paths are relative to the workspace; the Action rewrites them
against the container mount point.

### Tool knobs

`trivy_severity`, `trivy_severity_fail`, `trivy_ignore_unfixed`,
`trivy_ignore_unfixed_fail`, `trivy_exit_code`, `trivy_format`,
`trivy_scanners`, `trivy_timeout`, `trivy_server`, `trivy_ignorefile`,
`hadolint_failure_level`, `hadolint_config`, `hadolint_format`,
`betterleaks_fail_on_findings`, `betterleaks_redact`, `betterleaks_config`,
`betterleaks_baseline`, `sbom`, `sbom_format`, `scan_mode`, `skip_image`,
`skip_lint`, `skip_secrets`, `no_git`.

Each maps to the matching environment variable documented in the
[image README](https://github.com/Tooark/base-images/blob/main/security-scanner/README.md).
Every template declares the ones it supports, with descriptions and allowed
values, in its `spec:inputs` block — that is the authoritative reference.

### GitHub-only inputs

| Input             | Default            | Notes                                                                |
| ----------------- | ------------------ | -------------------------------------------------------------------- |
| `command`         | `full-scan`        | Selects the scan                                                     |
| `docker-socket`   | `false`            | Mounts `/var/run/docker.sock` so Trivy can read locally built images |
| `trivy-cache`     | `true`             | Caches the vulnerability database under `RUNNER_TEMP`                |
| `soft-fail`       | `false`            | Report the exit code instead of failing the step                     |
| `upload-artifact` | `true`             | Uploads `reports-dir` with `actions/upload-artifact`                 |
| `artifact-name`   | `security-reports` |                                                                      |

Outputs: `exit-code`, `reports-dir`, `report`.

---

## How precedence works

Every tunable resolves in the same order on both platforms:

```text
input  >  CI/CD variable (GitLab) or job env (GitHub)  >  image default
```

An **empty input is never forwarded**. That is deliberate: it lets a project
set `TRIVY_SEVERITY` once as a global variable and leave the matching input
blank in every job, rather than repeating it. Setting both means the input
wins.

---

## Secrets

Input values are visible in the rendered pipeline configuration, so secrets
never travel as inputs. Pass them as masked CI/CD variables (GitLab) or job
`env` (GitHub), and they are forwarded to the container automatically:

`TRIVY_TOKEN`, `TRIVY_USERNAME`, `TRIVY_PASSWORD`, `REPORT_TOKEN`,
`REPORT_HEADERS`, `REPORT_SBOM_URL`, `REPORT_SBOM_TOKEN`.

```yaml
# GitHub
- uses: Tooark/ci-security-scanner@v1.0.0
  env:
    REPORT_TOKEN: ${{ secrets.REPORT_TOKEN }}
  with:
    report-url: https://security-hub.example.com/api/reports
```

Betterleaks redacts every secret in the report by default
(`betterleaks_redact: "100"`), and the job log prints only rule, file, line and
short commit — never the secret itself.

---

## Security notes

Four things are worth knowing before you wire this into a pipeline that holds
credentials.

**`docker-socket: "true"` hands the container root on the runner.** The Docker
socket is an unrestricted control plane for the daemon, so anything inside the
container can start a privileged container and read the host. It is off by
default and only needed to scan an image built earlier in the same job — an
image already pushed to a registry does not need it. On a shared self-hosted
runner, prefer pushing to a registry and scanning from there.

**Reports can contain the secrets they found.** Two settings turn an artifact
into a disclosure: `betterleaks_redact: "0"` writes detected secrets in
cleartext, and adding `secret` to `trivy_scanners` puts Trivy's findings in the
report. Artifacts are downloadable by everyone with read access to the
repository or project, so leave redaction at its default unless the artifact
destination is as restricted as the secrets themselves.

**Floating tags are mutable by design.** Each release force-moves `v1` and
`v1.0`, so pinning either means code you have not reviewed runs in your
pipeline after the next release. `v1.0.0` is never moved, but a GitHub tag can
in principle be rewritten by anyone with push access; a remote include pinned
to a commit SHA is the only fully immutable reference:

```yaml
include:
  - remote: "https://raw.githubusercontent.com/Tooark/ci-security-scanner/<commit-sha>/templates/full-scan.yml"
```

**The reports directory is briefly world-writable on GitHub runners.** The
image drops to uid 1000, which is not the runner user, so the directory is
opened up for the duration of the scan and tightened again afterwards. On
ephemeral runners this is immaterial; on a self-hosted runner with concurrent
jobs, another job could write into it during the scan.

### What was checked

`eval` appears in the templates and in `src/run-scanner.sh`, but only ever
iterates a hardcoded list of variable names — no input reaches it. Word
splitting of `extra_args` is deliberate and runs under `set -f`, so a value
like `*` cannot expand against repository files. Workflow expressions reach
`run:` blocks through `env:` rather than string interpolation.
`scripts/validate-templates.py` uses `yaml.safe_load`. Workflow tokens are
scoped: `contents: read` for CI, `contents: write` only for the release job.
The third-party `actionlint` image is pinned by digest, and Dependabot tracks
the rest.

---

## Overriding what inputs do not expose

A generated GitLab job is an ordinary job. Redeclare it by name to change
anything the inputs do not cover:

```yaml
"security:full-scan":
  needs: ["build"]
  services:
    - docker:27-dind
  cache: [] # disable the Trivy database cache
  variables:
    TRIVY_SCANNERS: "vuln,secret,misconfig,license"
```

To run the same scan twice with different settings, include the template twice
with a different `job_name` — see
[`examples/gitlab/remote-include.gitlab-ci.yml`](examples/gitlab/remote-include.gitlab-ci.yml).

---

## Versioning

Releases are tagged `vMAJOR.MINOR.PATCH`. Each release also moves two floating
tags so consumers can track a line without editing pipelines on every patch:

| Reference | Resolves to                    | Use when                           |
| --------- | ------------------------------ | ---------------------------------- |
| `v1.0.0`  | Exactly that release           | Reproducible pipelines             |
| `v1.0`    | Newest patch of 1.0            | Automatic patch updates            |
| `v1`      | Newest release of the 1.x line | Automatic minor and patch updates  |
| `main`    | Unreleased work                | Never in a pipeline you care about |

[`VERSION`](VERSION) is the single source of truth for both the component
version and the scanner image tag that every template and the Action pin.
`scripts/check-sync.sh` fails CI if any of them drift, and the release workflow
refuses a tag that disagrees with `COMPONENT_VERSION`.

Bumping the scanner image is therefore a three-line change: edit `VERSION`,
run `./scripts/check-sync.sh`, update the pins it flags.

---

## Publishing

### GitHub Releases

Push a `v*.*.*` tag. [`.github/workflows/release.yml`](.github/workflows/release.yml)
validates the templates, checks the tag against `VERSION`, creates the release
with generated notes and moves the floating tags.

### GitHub Marketplace

Marketplace listing is a manual opt-in that the API cannot set: open the
release on GitHub and tick **Publish this Action to the GitHub Marketplace**.
Only needed once; later releases offer the same checkbox.

### GitLab CI/CD Catalog

The catalog only lists components hosted on the GitLab instance itself, so a
GitHub repository cannot be published to it directly. Set up the mirror project
described in [`examples/gitlab-catalog-mirror/`](examples/gitlab-catalog-mirror/):
it polls GitHub releases on a schedule, copies `templates/` across when the
version moves, and publishes to the internal catalog.

---

## Gotchas

**The GitLab entrypoint override is required.** The image entrypoint execs
`ark-tools` directly, and GitLab Runner keeps the image entrypoint and attaches
a shell to it. Every template sets `entrypoint: [""]`; removing it breaks the
job before the script runs.

**`GIT_DEPTH: "0"` matters for secret scanning.** Betterleaks walks the git
history. With GitLab's default shallow clone, or GitHub's default
`fetch-depth: 1`, it silently sees almost nothing. The templates set
`git_depth: "0"`; on GitHub set `fetch-depth: 0` on `actions/checkout`.

**Scanning an image built in the same GitHub job needs the socket.** Trivy
looks the image up in the local daemon, which the container cannot reach
without `docker-socket: "true"`. Images already pushed to a registry do not
need it.

**File ownership on GitHub runners.** The image drops to the non-root `app`
user (uid 1000), which is not the runner user. The Action creates the reports
directory world-writable and hands ownership back afterwards, and declares the
workspace as a git safe directory. Custom `reports-dir` values inherit this.

**Dockerfile lint handles one file per job.** Use `full-scan` with
`dockerfiles: "a,b,c"`, or include `dockerfile-lint` once per file with
different `job_name` values.

**The empty `tags` default renders as `tags: []`.** GitLab has no way for an
input to omit a keyword, and an empty tag list is how you say "any runner".
Pipelines accept it; only GitLab's editor JSON schema rejects empty arrays
([gitlab#551088](https://gitlab.com/gitlab-org/gitlab/-/issues/551088)), and
that schema applies to `.gitlab-ci.yml` files, not to these templates.

---

## Repository layout

```text
templates/                  GitLab CI/CD component templates, one job each
action.yml                  GitHub composite Action
src/run-scanner.sh          Shared runner behind the Action
scripts/                    Validation run in CI and locally
examples/                   Ready-to-copy pipelines for both platforms
docs/                       Onboarding guide, published to GitHub Pages
SUPPORTED-INTEGRATIONS.md   Platforms, runners and versions supported
VERSION                     Single source of truth for versions
```

---

## Development

```bash
python3 -m pip install pyyaml

python3 scripts/validate-templates.py   # structure, input wiring, dead inputs
./scripts/check-sync.sh                 # version pinning and cross-platform parity
shellcheck -s bash src/run-scanner.sh scripts/check-sync.sh
```

CI runs all three, plus `actionlint`, plus a self-scan in which the Action in
this repository scans this repository.

When adding an input, touch all four places or `check-sync.sh` will say so:
the template's `spec:inputs`, the template's `variables:` block as `ARK_IN_*`,
`action.yml`, and `src/run-scanner.sh`.

---

## License

MIT — see [LICENSE](LICENSE).
