# Security Policy

## Reporting a vulnerability

The Tooark ci-security-scanner maintainers take security seriously — this
component runs inside CI/CD pipelines that hold registry credentials, report
webhooks and, when configured to, the host's Docker socket. If you believe you
have found a security vulnerability in the GitLab templates, the GitHub
composite Action, `src/run-scanner.sh`, the validation scripts, the release
workflow or the CI/CD Catalog mirror pipeline, please report it **privately**
so we can address it before public disclosure.

### How to report

**Do NOT** open a public GitHub issue for security vulnerabilities.

Instead, use one of the following channels:

1. **Preferred** — GitHub Security Advisories:
   [Report a vulnerability](https://github.com/Tooark/ci-security-scanner/security/advisories/new)
2. **Email** — `security@tooark.com` (PGP key available on request)

Please include:

- A description of the vulnerability and its impact
- Steps to reproduce (proof of concept if possible)
- The component version (e.g. `v1.0.0`) and how it is consumed (GitHub Action,
  GitLab remote include, CI/CD Catalog component)
- The runner or executor it was reproduced on, and whether it is shared
- Your name / handle for credit (optional)

### What to expect

| Milestone                            | Target time                                             |
| ------------------------------------ | ------------------------------------------------------- |
| Acknowledgment of report             | Within **72 hours**                                     |
| Initial triage & severity assessment | Within **5 business days**                              |
| Fix and coordinated disclosure plan  | Within **30 days** (may be extended for complex issues) |
| Public advisory (if applicable)      | After a fixed release is published                      |

We follow the principles of
[Coordinated Vulnerability Disclosure (CVD)](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure).

## Supported versions

| Version | Supported |
| ------- | --------- |
| `1.x`   | ✅        |
| `< 1.0` | ❌        |

Security fixes land on the newest release of the supported line. The floating
`v1` and `v1.0` tags are force-moved on each release, so a pipeline pinned to
either picks the fix up automatically; a pipeline pinned to an exact patch
must be updated by hand.

## Scope

### In scope

- Command or argument injection reachable from a template input, an action
  input, or an environment variable this component forwards
- Leaking a secret into the job log, the rendered pipeline configuration, an
  uploaded artifact or a report payload
- Privilege escalation on the runner beyond what the documented options imply
- Tampering with the release process: the floating tags, the catalog mirror's
  push token, or an unpinned third-party action running in this repository's CI

### Out of scope

**Vulnerabilities inside the scanner image.** Trivy, Hadolint, Betterleaks and
the `ark-tools` CLI ship in `ghcr.io/tooark/security-scanner`, built from
[`Tooark/base-images`](https://github.com/Tooark/base-images/tree/main/security-scanner).
Report those there — the private channels are the same.

**Findings the scanner reported in your own project.** A CVE, a Dockerfile
warning or a detected secret in your repository is the tool working, not a
vulnerability in this component.

**Documented behaviour of an option you enabled.** The README's
[Security notes](README.md#security-notes) spell out the disclosure paths that
configuration can open. These are choices the consumer makes, not defects:

- `docker-socket: "true"` mounts `/var/run/docker.sock`, which is an
  unrestricted control plane for the host's Docker daemon. It is off by
  default and only needed to scan an image built earlier in the same job.
- `betterleaks_redact: "0"` writes detected secrets to the report in
  cleartext. The default is `100`.
- Adding `secret` to `trivy_scanners` puts Trivy's secret findings into the
  uploaded artifact, which anyone with read access to the project can download.

If you believe one of these defaults is wrong, or that a documented behaviour
is worse than documented, open an issue — or report it privately if describing
it would itself disclose a live secret.

## Hardening this component already applies

- Action inputs reach shell only as environment variables, never spliced into
  a `run:` block, so a crafted input value cannot become a command.
- Secrets travel through the environment rather than inputs, because input
  values are visible in the rendered pipeline configuration.
- `extra_args` is word-split under `set -f`, so a value such as `*` is passed
  literally instead of expanding against the files in the repository.
- Workflow tokens are scoped: `contents: read` for CI, `contents: write` only
  for the release job, `pages: write` only for the Pages job.
- The third-party `actionlint` image is pinned by digest, and Dependabot keeps
  the remaining action references current.
- The reports directory is opened up only for the duration of the scan, because
  the image drops to a non-root user, and tightened again afterwards.
- The catalog mirror hands its push token to git through a credential helper
  rather than a remote URL, keeping it out of argv and out of git's errors.

## A note on pinning

Each release force-moves `v1` and `v1.0`. Pinning either means code you have
not reviewed runs in your pipeline after the next release. `v1.0.0` is never
moved, but a GitHub tag can in principle be rewritten by anyone with push
access; a remote include pinned to a commit SHA is the only fully immutable
reference.
