# neurodesk

[![lint-test](https://github.com/neurodesk/helm-chart/actions/workflows/lint-test.yaml/badge.svg)](https://github.com/neurodesk/helm-chart/actions/workflows/lint-test.yaml)
[![release](https://github.com/neurodesk/helm-chart/actions/workflows/release.yaml/badge.svg)](https://github.com/neurodesk/helm-chart/actions/workflows/release.yaml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Consolidated, installable **JupyterHub application chart** for
[Neurodesk](https://www.neurodesk.org) — the JupyterHub-centric layer shared by
the [ais-devstack](https://github.com/Australian-Imaging-Service/ais-devstack)
and [neurocloud](https://github.com/neurodesk/neurocloud) deployments, packaged
once so both can install it the same way.

It bundles **JupyterHub** (upstream Zero-to-JupyterHub / z2jh), **CVMFS** access
(cvmfs-csi + smarter-device-manager + an optional Squid cache, health probe and
trace-parser), **security profiles** (AppArmor/Seccomp via the Security Profiles
Operator), **JupyterHub glue** (home auto-resize, fluent-bit, shared-storage
RBAC) and **optional XNAT** notebook integration — all behind a single
`values.yaml` control surface, with **render-time validation guards**
(`validation.*`) that fail the install fast on an inconsistent toggle/overlay
combination.

## What this is — and is not

**In scope** (installed / templated by this chart):

- JupyterHub (z2jh) with the neurodesk singleuser baseline (neurodesktop image,
  `/cvmfs` + `/dev/shm` mounts, FUSE device, AppArmor attachment, idle culling).
- CVMFS access: the CERN cvmfs-csi driver, smarter-device-manager (FUSE device
  plugin), the `cvmfs` automount PVC, and the in-house Squid cache, health probe
  and trace-parser.
- Security profiles: `AppArmorProfile` / `SeccompProfile` CRs and (bundled by
  default) the upstream Security Profiles Operator 1.0.0 that loads them onto
  nodes. SPO needs cert-manager; the chart can optionally install it
  (`cert-manager.enabled=true`, off by default) on a cluster that has none.
- JupyterHub glue: RBAC + ConfigMaps for home auto-resize, fluent-bit logging
  and shared teaching / group storage.
- Optional XNAT integration: servers launched from XNAT (XNAT's image,
  resources and data, mounted read-only), the JupyterLab XNAT-upload extension,
  and the NetworkPolicies between hub, notebooks and XNAT. Wired automatically
  under the AIS umbrella chart, where XNAT is in the same release.
- Optional AAF login preset with usernames matching XNAT's.

**Out of scope** (consumed by name through `global` / `infra`, never installed):

- Cluster infrastructure — StorageClass (Longhorn / NFS / …), ingress
  controller, cert-manager and its `Issuer` (unless you opt in to installing
  cert-manager as above), the Prometheus Operator stack, ArgoCD.
- The **XNAT server** itself and its configuration — XNAT is installed by the
  AIS xnat chart (or ais-devstack) and configured in XNAT.
- Cluster-wide security infrastructure (cryptnono, DNS egress filter) — those
  remain the deployment's *infrastructure* layer.

## Quick start

### From the Helm repository

```sh
helm repo add neurodesk https://neurodesk.github.io/helm-chart
helm repo update
helm install neurodesk neurodesk/neurodesk \
  --namespace neurodesk --create-namespace \
  -f my-values.yaml                    # your auth/ingress/secrets overlay
```

(Or pull the chart from OCI — see [Publishing](#publishing).)

### From a local checkout

```sh
# Register the dependency repos once, then build from the committed Chart.lock:
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
helm repo add smarter-device-manager https://smarter-project.github.io/smarter-device-manager
helm dependency build                  # honors Chart.lock (use `helm dependency update` only to bump versions)

helm install neurodesk . \
  --namespace neurodesk --create-namespace \
  -f examples/minimal-values.yaml      # then layer your own auth/ingress/secrets
```

`--namespace` is **required** — the z2jh image-awaiter Job targets the `default`
namespace otherwise. Without `jupyterhub.ingress.enabled` (and a host), the Hub
has no ingress — reach it with `kubectl port-forward svc/proxy-public 8080:80`.

The bundled Security Profiles Operator needs **cert-manager**. On a cluster that
has none, add `--set cert-manager.enabled=true` to either command so the one
release installs it too; on a cluster that already runs cert-manager, leave it
off. See [docs/install.md](docs/install.md).

> [!WARNING]
> The minimal profile ships the `dummy` authenticator, which accepts **any**
> username with no password. Swap to GitHub / OIDC (see
> `examples/{neurocloud,devstack}-values.yaml`) before exposing it anywhere
> beyond a private test cluster. Never commit real client secrets, cookie
> secrets, XNAT passwords or CryptKeeper keys to a values file — see
> [docs/secrets.md](docs/secrets.md).

## Component toggles

Every component is switched from `values.yaml`. Remote subcharts are gated by a
`Chart.yaml` `condition:`; in-house templates by a `{{- if }}` on the same
toggle. See [docs/values.md](docs/values.md) for the full key reference.

| Component | Toggle (default) | Kind | What it deploys |
| --- | --- | --- | --- |
| JupyterHub | `jupyterhub.enabled` (`true`) | remote subchart (z2jh) | Hub, proxy, scheduler, image-puller, singleuser servers |
| CVMFS — CSI driver | `cvmfs.enabled` (`true`) | remote subchart (`cvmfs-csi`) | CERN CVMFS CSI driver + automount StorageClass |
| CVMFS — FUSE device | `cvmfs.enabled` (`true`) | remote subchart (`smarter-device-manager`) | DaemonSet advertising `smarter-devices/fuse` |
| CVMFS — PVC + config | `cvmfs.enabled` (`true`) | in-house | the `cvmfs` PVC + server/proxy config wiring |
| CVMFS — Squid cache | `global.cvmfs.squidEnabled` (`false`) | in-house | in-cluster Squid HTTP cache + Service |
| CVMFS — health probe | `cvmfs.probe.enabled` (`true`) | in-house | per-node probe DaemonSet (`cvmfs_mount_healthy`) |
| CVMFS — trace-parser | `cvmfs.traceParser.enabled` (`false`) | in-house | trace-parser telemetry stack (WIP) |
| Security — profiles | `security.enabled` (`true`) | in-house | `AppArmorProfile` / `SeccompProfile` CRs |
| Security — operator | `security.installOperator` (`true`) | vendored subchart (upstream SPO 1.0.0) | Security Profiles Operator (CRDs + operator + node DaemonSet), in namespace `security-profiles-operator` |
| Security — cert-manager | `cert-manager.enabled` (`false`) | remote subchart (`cert-manager`) | cert-manager, for a cluster that has none (SPO needs it) |
| Glue — home resize | `jupyterGlue.homeResize.enabled` (`false`) | in-house | RBAC to patch nearly-full home PVCs |
| Glue — fluent-bit | `jupyterGlue.fluentbit.enabled` (`false`) | in-house | fluent-bit logging sidecar ConfigMap |
| Glue — shared teaching | `jupyterGlue.sharedTeaching.enabled` (`false`) | in-house | instructor RWX PVCs + RBAC |
| Glue — shared group storage | `jupyterGlue.sharedGroupStorage.enabled` (`false`) | in-house | RBAC to reconcile per-group RWX storage |
| XNAT integration | `xnat.enabled` (`false`) | in-house | XNAT-upload extension ConfigMap + NetworkPolicy |
| XNAT-launched servers | `xnat.jupyterhub.enabled` (`false`) | in-house | hub pre-spawn hook (ConfigMap), Role on XNAT's credentials Secret, hub<->XNAT NetworkPolicy |
| AAF login | `auth.aaf.enabled` (`false`) | in-house | AAF OpenID Connect authenticator preset |
| Extra manifests | `extraManifests` (`[]`) | in-house | arbitrary user-supplied manifests, rendered as-is |

## Documentation

Full docs live in [`docs/`](docs/):

- [architecture.md](docs/architecture.md) — the umbrella model, in/out scope, and
  the "subchart values can't be templated from sibling toggles" Helm caveat.
- [values.md](docs/values.md) — every `values.yaml` key, grouped, with defaults.
- [components.md](docs/components.md) — per component: what/source/toggle/prereqs.
- [install.md](docs/install.md) — prerequisites and the full install walkthrough.
- [ordering.md](docs/ordering.md) — how one `helm install` handles CRD-before-CR,
  StorageClass-before-PVC and the other ordering the devstack scripts did by hand.
- [disabling-components.md](docs/disabling-components.md) — turning CVMFS/security
  off across the subchart boundary: the map-merge (`null`) / list-replace gotchas
  and the `validation.*` guards.
- [security.md](docs/security.md) — SPO bundling (upstream 1.0.0), cert-manager,
  the profile CRs, sync caveats.
- [cvmfs.md](docs/cvmfs.md) — the `global.cvmfs` single source of truth, the CVMFS
  topology and the "run CVMFS yourself" path.
- [xnat.md](docs/xnat.md) — servers launched from XNAT, the AIS umbrella wiring,
  the XNAT-side settings, AAF login and the upload extension.
- [secrets.md](docs/secrets.md) — why secrets never go in `values.yaml`.
- [consuming-from-neurocloud.md](docs/consuming-from-neurocloud.md) /
  [consuming-from-devstack.md](docs/consuming-from-devstack.md) /
  [migration.md](docs/migration.md) — adopting the chart in each deployment, and
  upgrading from 0.1.x.

## Relationship to neurocloud and ais-devstack

This chart is the **shared JupyterHub notebook layer** for both Neurodesk
deployments. Each consumes it as a thin overlay and keeps its own
*infrastructure* layer:

- **[neurocloud](https://github.com/neurodesk/neurocloud)** (ArgoCD
  app-of-apps) points a single `Application` at this OCI chart. On its existing
  cluster, `examples/neurocloud-values.yaml` (GitHub auth + FriendlyKubeSpawner
  glue + ServiceMonitors) runs the chart **alongside** the `mounts` and
  `security` apps and reuses the SPO and CVMFS driver they own; those apps
  (which also carry cryptnono and the DNS filter) stay. Retiring them needs an
  ownership transfer that is not yet rehearsed. See
  [docs/consuming-from-neurocloud.md](docs/consuming-from-neurocloud.md).
- **[ais-devstack](https://github.com/Australian-Imaging-Service/ais-devstack)**
  (script-driven) replaces its numbered JupyterHub install scripts with one
  `helm install` + `examples/devstack-values.yaml` (XNAT overlay). The XNAT
  server and its jars stay in devstack. See
  [docs/consuming-from-devstack.md](docs/consuming-from-devstack.md).

## Publishing

Published two ways:

**1. Classic Helm repository (GitHub Pages):**

```sh
helm repo add neurodesk https://neurodesk.github.io/helm-chart
helm install neurodesk neurodesk/neurodesk -f my-values.yaml
```

Pushing a `v*` tag runs [`.github/workflows/pages.yaml`](.github/workflows/pages.yaml),
which packages the chart and publishes it (+ a merged `index.yaml`) to the
`gh-pages` branch served at `https://neurodesk.github.io/helm-chart`. *(GitHub
Pages requires the repository to be public, or a plan that allows private Pages.)*

**2. OCI artifact (GitHub Container Registry):**

```sh
helm pull oci://ghcr.io/neurodesk/charts/neurodesk --version <x.y.z>
# or, in a Chart.yaml dependency:
#   - name: neurodesk
#     version: <x.y.z>
#     repository: oci://ghcr.io/neurodesk/charts
```

Pushing a `v*` tag runs [`.github/workflows/release.yaml`](.github/workflows/release.yaml),
which packages the chart, `helm push`es it to `oci://ghcr.io/neurodesk/charts`
and attaches the `.tgz` to a GitHub release. Every PR/push runs
[`.github/workflows/lint-test.yaml`](.github/workflows/lint-test.yaml)
(`helm dependency build` → `helm lint` → a `helm template` matrix over the
`ci/ct-values-*.yaml` profiles on Helm 3 and 4 → `ct lint` → a `Chart.lock`
drift check → kind install tests).

## License

[Apache License 2.0](LICENSE) — Copyright Neurodesk.
