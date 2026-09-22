# Supported integrations

What this component is tested and supported on, and where the boundaries are.

Anything not listed here may still work — it is simply not something a bug
report can be held against. When in doubt, open an issue with the environment
filled in; the `bug` template asks for exactly the fields this page indexes.

🌍 Companion pages: [README.md](README.md) · [SUPPORT.md](SUPPORT.md) ·
[CONTRIBUTING.md](CONTRIBUTING.md)

---

## Platforms

| Platform                               | How it is consumed                          | Status         |
| -------------------------------------- | ------------------------------------------- | -------------- |
| **GitHub Actions**                     | `uses: Tooark/ci-security-scanner@v1.0.0`   | ✅ Supported   |
| **GitLab CI — remote include**         | `include: - remote: ".../templates/*.yml"`  | ✅ Supported   |
| **GitLab CI — CI/CD Catalog**          | `include: - component: $CI_SERVER_FQDN/...` | ✅ Supported   |
| **Direct invocation**                  | `docker run` / `src/run-scanner.sh`         | ⚠️ Best effort |
| Jenkins, Azure DevOps, CircleCI, Drone | —                                           | ❌ Not covered |

The component is a packaging layer. On an unsupported CI system you can still
run the underlying image directly — that is
[`Tooark/base-images`](https://github.com/Tooark/base-images/tree/main/security-scanner)
territory, not this repository's.

The CI/CD Catalog only lists components hosted on the GitLab instance itself, so
that route requires the mirror project in
[`examples/gitlab-catalog-mirror/`](examples/gitlab-catalog-mirror/).

---

## Runners and executors

| Requirement                     | GitHub Actions                                | GitLab CI                                  |
| ------------------------------- | --------------------------------------------- | ------------------------------------------ |
| Operating system                | **Linux only**                                | **Linux only**                             |
| Container runtime               | Docker CLI + daemon on the runner             | Provided by the executor                   |
| Executor / label                | `ubuntu-latest` or a Linux self-hosted runner | `docker`, `docker+machine` or `kubernetes` |
| Windows / macOS                 | ❌ Not supported                              | ❌ Not supported                           |
| GitLab `shell` / `ssh` executor | —                                             | ❌ Not supported                           |

**Why Linux and Docker.** The GitHub Action does not run the tools itself — it
runs `docker run ghcr.io/tooark/security-scanner:<tag>`. Without a working
Docker daemon on the runner there is nothing to execute.

**Why the executor matters on GitLab.** The templates run the job _inside_ the
scanner image and clear its entrypoint (`entrypoint: [""]`). An executor that
ignores the `image:` keyword — `shell`, `ssh` — will run the script on the
runner host, where `ark-tools` does not exist.

### Minimum Actions Runner version

GitHub-hosted runners always satisfy this. A **self-hosted** runner must be
recent enough for the `actions/*` versions that [`action.yml`](action.yml)
references. Any dependency bump that raises this floor is recorded in
[`CHANGELOG.md`](CHANGELOG.md) as a consumer-visible change — check it before
moving a floating tag on a fleet of self-hosted runners.

---

## Scans

All seven scans are available on both platforms. On GitLab each is a separate
template; on GitHub they are selected through the `command` input.

| Scan              | GitLab template       | Action `command`  | Tool        |
| ----------------- | --------------------- | ----------------- | ----------- |
| `full-scan`       | `full-scan.yml`       | `full-scan`       | all three   |
| `image-scan`      | `image-scan.yml`      | `image-scan`      | Trivy       |
| `filesystem-scan` | `filesystem-scan.yml` | `filesystem-scan` | Trivy       |
| `config-scan`     | `config-scan.yml`     | `config-scan`     | Trivy       |
| `repo-scan`       | `repo-scan.yml`       | `repo-scan`       | Trivy       |
| `dockerfile-lint` | `dockerfile-lint.yml` | `dockerfile-lint` | Hadolint    |
| `secret-scan`     | `secret-scan.yml`     | `secret-scan`     | Betterleaks |

Input names, defaults and precedence are identical on both sides; only the
case convention differs (`snake_case` on GitLab, `kebab-case` on GitHub).

### Scan-specific requirements

| Scan                                           | Requires                                                                 |
| ---------------------------------------------- | ------------------------------------------------------------------------ |
| `secret-scan`, and `full-scan` secrets         | Full git history — `fetch-depth: 0` / `GIT_DEPTH: "0"`                   |
| `image-scan` of an image built in the same job | `docker-socket: "true"` on GitHub; `docker:dind` service on GitLab       |
| `image-scan` of an image in a registry         | Network reach, plus registry credentials when it is private              |
| `dockerfile-lint`                              | One Dockerfile per job — use `full-scan` with `dockerfiles:` for several |
| Any Trivy scan                                 | Network reach to the vulnerability database, or a `trivy_server`         |

A shallow clone is the trap worth repeating: Betterleaks walks the history, and
with the default shallow clone it sees almost nothing **and does not complain**.

---

## Versions

| Component version | Scanner image                         | Status  |
| ----------------- | ------------------------------------- | ------- |
| `1.x`             | `ghcr.io/tooark/security-scanner:1.9` | Current |

[`VERSION`](VERSION) is the single source of truth for this pairing, and
`scripts/check-sync.sh` fails CI when any template or the Action drifts from
it. Overriding `scanner_version` / `scanner-version` to a tag this table does
not list is allowed and occasionally useful, but it is unsupported: the
component's inputs are written against the variables a specific image reads.

### Reference tags

| Reference | Resolves to                    | Mutable            |
| --------- | ------------------------------ | ------------------ |
| `v1.0.0`  | Exactly that release           | No                 |
| `v1.0`    | Newest patch of 1.0            | Yes                |
| `v1`      | Newest release of the 1.x line | Yes                |
| `main`    | Unreleased work                | Yes — never pin it |

---

## Network

| Destination                     | Needed for                          | Avoidable with                                              |
| ------------------------------- | ----------------------------------- | ----------------------------------------------------------- |
| `ghcr.io`                       | Pulling the scanner image           | A mirror, via `scanner_image`                               |
| Trivy vulnerability database    | Every Trivy scan                    | `trivy_server`, or `TRIVY_SKIP_DB_UPDATE` with a warm cache |
| `raw.githubusercontent.com`     | GitLab remote include only          | The CI/CD Catalog mirror                                    |
| `api.github.com` · `github.com` | The catalog mirror's scheduled sync | —                                                           |

Fully air-gapped instances are not a supported configuration today. The pieces
exist — a mirrored image, a Trivy server, the catalog mirror instead of a
remote include — but the combination is untested.

---

## Reports and formats

Report formats, SBOM formats and the consolidated `ark-report-tools` envelope
are produced by the image, not by this component. The component forwards the
format inputs and uploads whatever lands in the reports directory.

The authoritative list of supported values for `trivy_format`,
`hadolint_format`, `betterleaks_format` and `sbom_format` is the `options:`
block of each input in [`templates/`](templates/), which mirrors the
[image README](https://github.com/Tooark/base-images/blob/main/security-scanner/README.md).

---

## Not supported

- Windows and macOS runners, on either platform
- GitLab `shell` and `ssh` executors
- CI systems other than GitHub Actions and GitLab CI
- Container runtimes other than Docker on the GitHub side (Podman is untested)
- Fully air-gapped installations
- Scanner image tags outside the pairing table above
- `main` as a pinned reference
