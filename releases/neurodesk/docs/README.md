# neurodesk chart — documentation

`neurodesk` is the consolidated, installable JupyterHub application chart for
[Neurodesk](https://www.neurodesk.org). It is the JupyterHub-centric layer
shared by the two Neurodesk deployment repositories — script-driven
[ais-devstack](https://github.com/Australian-Imaging-Service/ais-devstack)
and the ArgoCD app-of-apps
[neurocloud](https://github.com/neurodesk/neurocloud) — packaged once so both
can install it the same way.

It bundles **JupyterHub** (upstream Zero-to-JupyterHub), **CVMFS** access
(cvmfs-csi + smarter-device-manager + an optional Squid cache, health probe and
trace-parser), **security profiles** (AppArmor/Seccomp via the bundled
upstream Security Profiles Operator 1.0.0), **JupyterHub glue** (home auto-resize, fluent-bit, shared
storage RBAC) and **optional XNAT** notebook integration. **Render-time
validation guards** (`validation.*`) fail the install fast when a component
toggle and the z2jh singleuser block disagree.

Cluster *infrastructure* — StorageClass (Longhorn/NFS), ingress controller,
cert-manager Issuer, the full Prometheus stack, ArgoCD — is **not** installed
here. It is consumed by name: StorageClass via the `global` / z2jh
`jupyterhub.hub.db.pvc` / `jupyterhub.singleuser.storage.dynamic` keys, the
ingress controller + cert-manager Issuer via z2jh's own `jupyterhub.ingress.*`
(the `infra:` block now holds only `monitoring`), and the Prometheus stack via
`infra.monitoring.*`. cert-manager itself is required by the bundled SPO; it is
consumed if the cluster runs it, or installed with the release on opt-in
(`cert-manager.enabled=true`) for a cluster that has none.

Published as an OCI artifact at `ghcr.io/neurodesk/charts/neurodesk`.

## Table of contents

| Document | What it covers |
| --- | --- |
| [architecture.md](architecture.md) | What the chart is; the umbrella (remote deps + parent templates) model; in/out scope; component map; the "subchart values can't be templated from sibling toggles" Helm limitation and the opinionated-defaults / overlay workaround. |
| [values.md](values.md) | Every `values.yaml` key documented in tables, grouped by component, with defaults and "breaks-when-off" notes. |
| [components.md](components.md) | Per component: what it deploys, the source it was ported from, its toggle, dependencies, and node/cluster prerequisites. |
| [install.md](install.md) | Prerequisites (Kubernetes ≥ 1.30, where the FUSE device plugin runs (no node label needed), the z2jh StorageClass keys, cert-manager, `values.schema.json` fail-fast), `helm dependency build` (honors the committed `Chart.lock`), the required explicit `--namespace`, `helm install` (existing cert-manager / standalone / external SPO), per-component enable/disable + the merge-gotcha cookbook, the `validation.*` guards, the `extraManifests` escape hatch, the `helm template \| kubectl apply` alternative, and **teardown / uninstall** (stop user servers first; the pre-delete cleanup hook; the PVCs it deletes; what stays by design). |
| [ordering.md](ordering.md) | How one `helm install` handles the install ordering the devstack numbered scripts did by hand: CRD-before-CR, StorageClass-before-PVC, the (non-)SPO-webhook race and SPO's cert-manager dependency, runtime vs install-time deps, and upgrades. |
| [disabling-components.md](disabling-components.md) | Turning CVMFS/security off across the subchart boundary: the Helm map-merge gotcha (null the **whole submap**, not the leaf) and list-replace (restate what you keep), the external-SPO case, and the `validation.*` guards. |
| [security.md](security.md) | SPO bundling (upstream 1.0.0, vendored with local patches; fixed `security-profiles-operator` namespace), the cert-manager requirement, the `installOperator` / `assumeCrdsPresent` toggles and SPO guards, shared-cluster collisions (cluster-scoped profile names), AppArmor/Seccomp CRs (what the AppArmor profile allows; seccomp is audit-only + manual attach), the manual node-load fallback, and the singleuser `securityContext` sync caveat. |
| [cvmfs.md](cvmfs.md) | The `global.cvmfs` single source of truth (server URL + single squid toggle), cvmfs-csi, smarter-device-manager, the `cvmfs` PVC, the probe (scheduling) and trace-parser, where the FUSE device plugin runs, Squid `clientCidrs`, and running CVMFS yourself. |
| [xnat.md](xnat.md) | Optional XNAT: what the chart ships (extension ConfigMap, NetworkPolicy) vs what stays in ais-devstack (XNAT server + jars); how to enable it. |
| [secrets.md](secrets.md) | Why secrets never go in `values.yaml`; `existingSecret` / sealed-secrets / SOPS; the exact secrets each deployment needs. |
| [consuming-from-neurocloud.md](consuming-from-neurocloud.md) | A fresh bundled install vs adopting the chart on an existing neurocloud (reusing the SPO and CVMFS driver owned by its `security` / `mounts` apps, which stay); the multi-source Argo CD `Application`; what neurocloud keeps; why consolidation needs an (unrehearsed) ownership transfer. |
| [consuming-from-devstack.md](consuming-from-devstack.md) | Replacing ais-devstack's numbered JupyterHub scripts with one `helm install`; what devstack keeps. |
| [migration.md](migration.md) | The omit/keep tables for both repos (neurocloud: fresh vs existing cluster), a branch-install-verify rollout plan with consolidation as a plan only, and **0.1.x -> 0.2.0** (breaking changes; which releases can upgrade in place). |

## Quick start

```sh
# Register the dependency repos, then build from the committed Chart.lock:
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
helm repo add smarter-device-manager https://smarter-project.github.io/smarter-device-manager
helm dependency build                # honors Chart.lock (use `helm dependency update` only to bump)

helm install neurodesk . \
  --namespace neurodesk --create-namespace \
  -f my-values.yaml                  # your auth/ingress/secrets overlay
  # add --set cert-manager.enabled=true on a cluster with NO cert-manager
```

`--namespace` is **required** (the z2jh image-awaiter Job targets `default`
otherwise). See [install.md](install.md) for prerequisites (Kubernetes ≥ 1.30,
StorageClass, SPO and cert-manager, Prometheus CRDs) and the full walkthrough.
No node label is needed for CVMFS: the FUSE device plugin runs on every Linux
node.

## Known limitations / fast-follows

- **No `imagePullSecrets` on in-house pods yet.** The chart's own pods (Squid,
  the CVMFS probe, the trace-parser, the node-sysctl helper, the XNAT installer
  init-container) do not yet wire `imagePullSecrets`. Airgapped / private-registry
  clusters that need pull credentials for those images aren't covered yet —
  planned.
- **No helm-unittest golden tests yet.** Render correctness is covered by
  `helm lint`/`template` and the `ci/ct-values-*.yaml` profiles, but there are no
  helm-unittest snapshot/golden tests asserting the rendered output — planned.
- **First cold spawn can exceed `start_timeout`.** With the pre-puller off (the
  default), the **first** spawn on a node pulls the multi-GB `neurodesktop` image
  lazily. The chart raises **`jupyterhub.singleuser.startTimeout`** to `600`
  seconds (z2jh's default is 300); on very slow registries raise it further (or
  re-enable the pre-puller for pre-warmed nodes). See
  [ordering.md](ordering.md#the-z2jh-image-pre-puller-is-disabled-by-default).
