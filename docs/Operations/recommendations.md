---
linkTitle: "Recommendations"
title: "Operational recommendations"
weight: 10
---

## Purpose

These recommendations provide a practical, high-level path for deploying and operating AIS chart-based services when Helm defaults are not enough for site-specific requirements.

## Deployment lifecycle (high level)

1. **Plan**
   - Define security and compliance requirements.
   - Decide deployment model (single-site, federated, cloud/on-prem).
   - Confirm ownership model (platform team, app team, shared).

2. **Baseline platform**
   - Kubernetes cluster readiness (RBAC, ingress, storage classes, backups).
   - Network policies and DNS strategy.
   - Observability baseline (logs, metrics, alerts).

3. **Configuration strategy**
   - Keep base chart values minimal.
   - Layer site overrides in version control.
   - Separate secrets from non-sensitive config.

4. **Release workflow**
   - Validate with `helm lint` / `helm template` before apply.
   - Promote through environments (dev -> test -> prod).
   - Prefer progressive rollout patterns where possible.

5. **Operate**
   - Monitor app health, storage growth, and DB performance.
   - Review security posture regularly.
   - Test restore paths and disaster recovery procedures.

## Decision points

### 1) Database placement

- **Use bundled DB** for simple/dev setups.
- **Use external managed DB** for production-scale and stronger operational controls.

### 2) Secret management

- Start with Kubernetes secrets where appropriate.
- For shared/federated operations, prefer encrypted secrets workflows (e.g. SOPS + KMS/GPG).

### 3) Change control

- Use Git PRs for all values/template changes.
- Require peer review for security, networking, and storage-impacting changes.

## Recommended tooling

- **Git**: source of truth for chart config and overlays.
- **SOPS**: encrypt sensitive values in-repo.
- **GnuPG/KMS**: key management for encrypted workflows.
- **git-secrets**: prevent accidental credential commits.
- **CI**: automate lint/render checks on every PR.

## Minimum validation checklist

- [ ] Rendered manifests look correct for target environment.
- [ ] No plaintext secrets introduced.
- [ ] Resource requests/limits match cluster policy.
- [ ] Ingress/TLS configuration matches site routing model.
- [ ] Backup and restore path documented and tested.

## References

- [PostgreSQL DB tuning](./PostgreSQL-DB-Tuning/)
- [External PostgreSQL connection](./External-PGSQL-DB-Connection/)
- [Logging with EFK](./Logging-With-EFK/)
- [Autoscaling XNAT on Kubernetes](./Autoscaling-XNAT-Kubernetes-with-EKS/)
