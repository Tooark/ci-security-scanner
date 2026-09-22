# Mirror project for a self-hosted CI/CD Catalog

GitLab only lists components that live in a project on the GitLab instance
itself, so a GitHub repository cannot be published to the catalog directly.
This directory holds the pipeline for a small mirror project that closes that
gap: it watches releases of
[`Tooark/ci-security-scanner`](https://github.com/Tooark/ci-security-scanner),
copies `templates/` across when the version moves, and publishes the new
version to the internal catalog.

GitHub stays the source of truth. Nothing is authored here.

## What the pipeline does

| Job       | Trigger                              | What it does                                                                                                       |
| --------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `sync`    | weekly schedule, manual run, or push | Reads the newest upstream release; if that version has no tag yet, commits the new `templates/` and pushes the tag |
| `release` | the tag pushed by `sync`             | Publishes that tag to the CI/CD Catalog                                                                            |

Re-running `sync` when nothing changed is a no-op, so the schedule can be as
aggressive as you like.

## One-time setup

1. **Create the project** on your GitLab instance, for example
   `tooark/ci-security-scanner`. Give it a **description** — the catalog
   refuses to publish a project without one.

2. **Seed it** with this file as `.gitlab-ci.yml` at the repository root:

   ```bash
   git clone https://gitlab.example.com/tooark/ci-security-scanner.git
   cd ci-security-scanner
   curl -fsSLO https://raw.githubusercontent.com/Tooark/ci-security-scanner/main/examples/gitlab-catalog-mirror/.gitlab-ci.yml
   git add .gitlab-ci.yml
   git commit -m "chore: add catalog sync pipeline"
   git push
   ```

   `templates/`, `README.md`, `LICENSE` and `VERSION` arrive with the first
   sync — there is no need to copy them by hand.

3. **Mark it as a catalog resource**: _Settings > General > Visibility, project
   features, permissions_ and turn on **CI/CD Catalog project**. The project
   becomes findable only after the first release is published.

4. **Create a project access token** with the `write_repository` scope and the
   Maintainer role, so the `sync` job can push commits and tags. Add it under
   _Settings > CI/CD > Variables_ as:

   | Variable             | Value                    | Flags             |
   | -------------------- | ------------------------ | ----------------- |
   | `CATALOG_PUSH_TOKEN` | the project access token | Masked, Protected |

   If the default branch is protected, either mark the variable as protected
   and allow the token to push to it, or drop the protection on the variable.

5. **Allow the token past branch protection**: _Settings > Repository >
   Protected branches_ — the token's user needs push rights on the default
   branch, and _Protected tags_ must allow it to create tags.

6. **Add the schedule**: _Build > Pipeline schedules > New schedule_, cron
   `0 6 * * 1` (Mondays at 06:00) on the default branch.

7. Optionally set `UPSTREAM_TOKEN` to a GitHub token. It is only needed if the
   instance shares an egress IP with enough other traffic to hit GitHub's
   unauthenticated rate limit of 60 requests per hour.

## Using the published component

Once the first release lands, projects on the instance include it by path:

```yaml
include:
  - component: $CI_SERVER_FQDN/tooark/ci-security-scanner/full-scan@1.0.0
    inputs:
      image: "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
      trivy_severity: "CRITICAL,HIGH"
```

`$CI_SERVER_FQDN` resolves to the instance host, so the same snippet works in
every project without hardcoding the domain.

## Version mapping

GitHub tags carry a `v` prefix (`v1.0.0`); the catalog expects a bare semantic
version (`1.0.0`). The `sync` job strips the prefix, so upstream `v1.2.3`
becomes catalog version `1.2.3`.

## When a sync goes wrong

| Symptom                                          | Cause                                                                          |
| ------------------------------------------------ | ------------------------------------------------------------------------------ |
| `CATALOG_PUSH_TOKEN is not set`                  | The CI/CD variable is missing, or it is protected and the branch is not        |
| `remote: You are not allowed to push code`       | The token's user lacks push rights on the protected branch or tag              |
| The release job runs but the catalog stays empty | The **CI/CD Catalog project** toggle is off, or the project has no description |
| `API rate limit exceeded`                        | Set `UPSTREAM_TOKEN` to a GitHub token                                         |
