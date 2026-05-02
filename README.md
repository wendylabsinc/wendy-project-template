# wendy-project-template

Standard GitHub Actions templates for all WendyOS projects.

## How it works

1. Add `.github/wendy-template.yml` to your repo to opt in.
2. When this repo's `main` branch changes, a sync workflow discovers every opted-in repo and opens a PR with updated workflow files.

## Marker file

```yaml
# .github/wendy-template.yml
type: swift  # one of: swift, go, node, python, rust, firmware

overrides:
  # See defaults/<type>.yml for all available keys and their defaults
  swift_versions: ["6.2"]
  platforms: [ubuntu-latest, macos-latest]
```

## What gets synced

- `.github/workflows/ci.yml` — build, lint, test
- `.github/workflows/release.yml` — release artifacts on `v*` tags (swift, go, rust, firmware)
- `.github/workflows/docs-update.yml` — Claude-powered docs PR after merge
- `.github/workflows/security-scan.yml` — Trivy + Gitleaks + language-specific scanners
- `.github/dependabot.yml` — weekly dependency and Actions updates

## Secrets required (org-level)

- `WENDY_TEMPLATE_SYNC_TOKEN` — GitHub App token or PAT with `contents:write` and `pull-requests:write` on all wendy-sh repos and `wendylabsinc/docs`
- `ANTHROPIC_API_KEY` — used by `docs-update.yml` in downstream repos
