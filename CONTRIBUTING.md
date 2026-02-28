# Contributing Guidelines

Thanks for contributing to `kyaky/charts`.

## How to contribute

1. Fork this repository (or create a feature branch if you have write access).
2. Create a branch from `master` using a clear name, for example:
   - `fix/xnat-values-defaults`
   - `docs/readme-quickstart`
3. Make focused changes (one topic per PR when possible).
4. Open a Pull Request with:
   - problem statement
   - summary of changes
   - rollout/upgrade impact
   - validation steps

## Technical requirements

For chart changes, include:

- updated chart templates and/or values
- version bump where applicable
- notes on backward compatibility (breaking or non-breaking)

Recommended checks before submitting:

```bash
# Lint chart(s)
helm lint releases/*

# Render templates for quick validation
helm template test releases/<chart-name> -f releases/<chart-name>/values.yaml > /tmp/<chart-name>.yaml
```

## Documentation requirements

If behavior changes, update docs in the same PR:

- `README.md` for user-facing quick start changes
- `docs/` for deployment guidance
- chart `README`/values comments where applicable

## PR review and release

- Keep PRs small and reviewable.
- Maintainers may request splitting large PRs.
- Releases are managed by maintainers after review and merge.
