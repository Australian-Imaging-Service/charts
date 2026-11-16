# Consuming this chart from ais-devstack

[ais-devstack](https://github.com/Australian-Imaging-Service/ais-devstack)
stands the platform up with a sequence of **numbered, script-driven steps**:
install JupyterHub, mount CVMFS, apply security, run a squid cache, wire XNAT —
each its own script. This chart replaces that JupyterHub-centric sequence with a
**single `helm install`**, while devstack keeps the XNAT server and the cluster
infrastructure it already manages.

## Before / after

| ais-devstack step (today) | After |
| --- | --- |
| JupyterHub install scripts (the numbered `5` / `6` / `8` / `9` steps) | `helm install` with `jupyterhub.*` |
| `cvmfs_mount` step | `cvmfs.*` + `cvmfs-csi` + `smarter-device-manager` |
| squid script | `global.cvmfs.squidEnabled=true` |
| security step (AppArmor/Seccomp + SPO `0.10.1-dev`) | `security.*` + bundled upstream SPO 1.0.0 (runs in namespace `security-profiles-operator`). devstack's `0.10.1-dev` SPO is not compatible and must not run alongside; see [migration.md](migration.md#01x---020) for a cluster that already has it. |
| XNAT-upload notebook wiring | `xnat.enabled=true` (notebook-side ConfigMap + NetworkPolicy) |

All of the above become one `helm install -f examples/devstack-values.yaml`
with `xnat.enabled=true`.

## What devstack keeps

- **The XNAT server + its jars** — `xnat-web`, its database, and the
  server-side plugins/jars stay in ais-devstack. This chart only wires the
  *notebook* side to it (see [xnat.md](xnat.md)).
- **Cluster infrastructure** — Longhorn (StorageClass) and the **nfs-server**
  remain devstack's responsibility; the chart consumes the StorageClass by name
  (hub DB + home PVCs via the z2jh keys `jupyterhub.hub.db.pvc.storageClassName` /
  `jupyterhub.singleuser.storage.dynamic.storageClass`; `global.storageClassName`
  only for this chart's own in-house PVCs).
- **cert-manager** — devstack installs it itself. The bundled SPO uses it, so
  keep `cert-manager.enabled=false` (as `examples/devstack-values.yaml` does):
  a second cert-manager would collide.
- **Cleanup / teardown** — devstack's existing cleanup scripts stay; uninstall
  the chart with `helm uninstall` as part of them, after stopping every user
  server (the chart's pre-delete hook refuses otherwise). `helm uninstall` **deletes**
  the PVCs the release created, including `hub-db-dir` (hub state) and
  `cvmfs-squid-cache`, and **leaves** the cluster-wide SPO CRDs, the
  `security-profiles-operator` namespace and the per-user `claim-*` home PVCs —
  see [install.md#teardown--uninstall](install.md#teardown--uninstall).

## Sample install

Replace the numbered JupyterHub scripts with:

```sh
# 1. Prereqs devstack already does elsewhere: StorageClass (Longhorn) and
#    nfs-server. (No FUSE node label is needed any more: the chart runs its FUSE
#    device plugin on every Linux node.)

# 2. Vendor subcharts (from a source checkout; skip if installing the OCI artifact).
#    Chart.lock is committed, so add the two HTTP repos and `build` (honors the lock):
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
helm repo add smarter-device-manager https://smarter-project.github.io/smarter-device-manager
helm dependency build

# 3. One install replacing scripts 5/6/8/9 + cvmfs_mount + security + squid,
#    with XNAT notebook integration on:
helm upgrade --install neurodesk . \
  --namespace neurodesk --create-namespace \
  -f examples/devstack-values.yaml \
  --set xnat.enabled=true \
  --set xnat.server.host=xnat-web.ais-xnat.svc.cluster.local \
  --set xnat.server.namespace=ais-xnat
```

`examples/devstack-values.yaml` carries the devstack overlay: the XNAT-flavoured
`jupyterhub.hub.extraConfig`, the squid toggle if devstack uses it, the
StorageClass name, and ingress settings. Secrets (proxy token, cookie secret,
OAuth `client_secret`, XNAT `apiToken`) come from devstack's secret store via
`existingSecret`, **not** inline — see [secrets.md](secrets.md).

To install from the published OCI artifact instead of a checkout:

```sh
helm upgrade --install neurodesk oci://ghcr.io/neurodesk/charts/neurodesk \
  --version <chart-version> \
  --namespace neurodesk --create-namespace \
  -f examples/devstack-values.yaml \
  --set xnat.enabled=true
```

## GitOps / no-Helm path

If devstack's pipeline applies manifests rather than running Helm against the
cluster, render and apply (note CRD ordering for SPO/Prometheus). The offline
render cannot see devstack's cert-manager, so assert it. **`--no-hooks` is
mandatory**: `kubectl` ignores Helm hook annotations, so without it the chart's
pre-delete cleanup Job would run at install time and delete the profile and the
CVMFS PVCs.

```sh
kubectl config set-context --current --namespace neurodesk   # the release namespace
helm template neurodesk . -n neurodesk -f examples/devstack-values.yaml \
  --no-hooks --include-crds --api-versions cert-manager.io/v1/Certificate \
  --set xnat.enabled=true | kubectl apply -f -
```

Keep `-n` on `helm` only: the bundled SPO's objects are in namespace
`security-profiles-operator`, and `kubectl apply -n neurodesk` would reject
them; objects without a namespace (e.g. z2jh's) go to the context's current
namespace, set above.

An install applied this way has no automatic uninstall: remove it by hand in
the hook's order (stop user servers, delete the profile, the CVMFS probe and
PVCs, the operator's runtime objects, then the rest) — see
[install.md](install.md#helm-template--kubectl-apply-alternative).

See [install.md](install.md) for the caveats and [migration.md](migration.md)
for the full omit/keep table and rollout plan.
