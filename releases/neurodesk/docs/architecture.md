# Architecture

## What this chart is

`neurodesk` is a single Helm chart that packages the JupyterHub-centric
application layer that the two Neurodesk deployments previously each built by
hand:

- **ais-devstack** stood it up with a set of numbered, script-driven steps
  (install JupyterHub, mount CVMFS, apply security, run squid, wire XNAT).
- **neurocloud** stood it up as several ArgoCD `Application`s in an
  app-of-apps (`charts/jupyter`, a `mounts` app, a `security` app, …).

Both encode the *same* JupyterHub + CVMFS + security stack with deployment-
specific overlays on top. This chart factors that shared stack into one
installable, versioned artifact so the two repos diverge only in their
overlay values — not in the mechanics.

It is published as an OCI artifact:

```
ghcr.io/neurodesk/charts/neurodesk
```

## The umbrella model

The chart is an **umbrella**: it combines two kinds of building block under one
release.

### 1. Remote subcharts (dependencies)

Declared in `Chart.yaml` under `dependencies:`, pulled into `charts/` by
`helm dependency build` (which honors the committed `Chart.lock`; see
[install.md](install.md)). Each carries a `condition:` so it is only installed
when its toggle is true:

| Subchart | Version | Repository | `condition:` |
| --- | --- | --- | --- |
| `jupyterhub` | `4.4.2` | `https://jupyterhub.github.io/helm-chart` | `jupyterhub.enabled` |
| `cvmfs-csi` | `2.6.0` | `oci://registry.cern.ch/kubernetes/charts` | `cvmfs.enabled` |
| `smarter-device-manager` | `0.0.10` | `https://smarter-project.github.io/smarter-device-manager` | `cvmfs.enabled` |
| `security-profiles-operator` | `1.0.0` | `file://vendor/security-profiles-operator` (upstream kubernetes-sigs v1.0.0, vendored with local patches) | `security.installOperator` |
| `cert-manager` | `v1.21.2` | `oci://quay.io/jetstack/charts` | `cert-manager.enabled` (default `false`) |

A subchart's values live under the **top-level key matching its name** — e.g.
`cvmfs-csi:` and `smarter-device-manager:` are sibling keys to `cvmfs:`, not
nested inside it. Everything under each of those keys is passed through to the
subchart unchanged (z2jh values under `jupyterhub:`, CERN cvmfs-csi values
under `cvmfs-csi:`, and so on).

SPO is vendored rather than pulled from upstream's OCI chart because it needs
local patches to run inside this release (see
`vendor/security-profiles-operator/PROVENANCE.txt` and
[security.md](security.md)). One consequence: SPO objects always live in
namespace `security-profiles-operator`, not the release namespace.

### 2. Parent (in-house) templates

The chart's own templates in `templates/` render the glue Kubernetes objects
that aren't a third-party chart: the `cvmfs` PVC and CVMFS config wiring, the
Squid Deployment, the probe DaemonSet, the trace-parser, the AppArmor/Seccomp
profile CRs, the jupyter-glue RBAC/ConfigMaps, the XNAT extension ConfigMap and
NetworkPolicy, plus the namespace and the `extraManifests` escape hatch.

Every in-house template is **gated by its own toggle** with
`{{- if .Values.<toggle> }} … {{- end }}` so a switched-off component renders
nothing. Parent-chart templates see the *full* `.Values` tree (including the
subchart keys), so they can read e.g. `.Values.global.cvmfs.squidEnabled` while
the subchart blocks remain untouched.

Standard labels are applied to every in-house object via
`{{- include "neurodesk.labels" . | nindent 4 }}`, and the deploy namespace is
always `{{ include "neurodesk.namespace" . }}` (never a hardcoded name). The
AppArmor/Seccomp profile CRs are cluster-scoped and carry no namespace.

## In scope vs out of scope

The dividing line is **application vs infrastructure**. The chart installs the
application stack; it *references* infrastructure that the cluster already runs.

| In scope (installed by this chart) | Out of scope (consumed by name) |
| --- | --- |
| JupyterHub (z2jh subchart) | StorageClass — Longhorn / NFS (hub DB + home PVCs on the z2jh keys `jupyterhub.hub.db.pvc.storageClassName` / `jupyterhub.singleuser.storage.dynamic.storageClass`; `global.storageClassName` only for this chart's own in-house PVCs) |
| CVMFS access: cvmfs-csi, smarter-device-manager, `cvmfs` PVC, Squid, probe, trace-parser | Ingress controller (`jupyterhub.ingress.ingressClassName`) |
| Security profiles: AppArmor/Seccomp CRs + (bundled) SPO, in its own `security-profiles-operator` namespace | cert-manager Issuer (`cert-manager.io/cluster-issuer` annotation under `jupyterhub.ingress.annotations`) |
| cert-manager — **optional, off by default** (`cert-manager.enabled`), for a cluster that has none | cert-manager itself when the cluster already runs it (SPO uses it) |
| JupyterHub glue: home-resize, fluent-bit, shared storage RBAC/ConfigMaps | Prometheus Operator / kube-prometheus-stack (`infra.monitoring.*`) |
| Optional XNAT *notebook-side* integration (extension ConfigMap, NetworkPolicy) | ArgoCD (lives in neurocloud) |
| The release namespace + optional PodSecurity labels | nfs-server (lives in ais-devstack) |
| `extraManifests` escape hatch | The XNAT **server** + its server-side jars (stay in ais-devstack) |
| | cryptnono / DNSFilter (stay in neurocloud) |

Excluding infrastructure is deliberate: both deployments already provision
Longhorn, ArgoCD, cert-manager, the full Prometheus stack and (devstack) an
nfs-server through their own mechanisms. This chart consumes those by name so
it can be installed onto an existing cluster without colliding with them.

cert-manager is the one exception, and only as an opt-in: the bundled SPO
cannot work without it, so `cert-manager.enabled=true` lets a single release
install everything on a bare cluster. It stays off by default because
cert-manager is a cluster singleton and the chart never adopts an existing
install.

## Component map

```
neurodesk (umbrella release)
│
├── jupyterhub.enabled ──────────► [subchart] jupyterhub (z2jh)
│                                     singleuser: neurodesktop image, /cvmfs,
│                                     FUSE device, /dev/shm, AppArmor attach
│
├── cvmfs.enabled ─────────────┬─► [subchart] cvmfs-csi (CERN)
│                              ├─► [subchart] smarter-device-manager (/dev/fuse)
│                              └─► [in-house] cvmfs PVC + CVMFS config wiring
│     ├── global.cvmfs.squidEnabled ► [in-house] Squid cache Deployment + Service
│     ├── cvmfs.probe.enabled ────► [in-house] CVMFS health-probe DaemonSet
│     └── cvmfs.traceParser.enabled ► [in-house] trace-parser telemetry stack
│
├── security.enabled ──────────┬─► [in-house] AppArmorProfile / SeccompProfile CRs
│     └── security.installOperator ► [subchart] security-profiles-operator
│                                     (vendored upstream 1.0.0; runs in
│                                      namespace security-profiles-operator)
│
├── cert-manager.enabled ──────────► [subchart] cert-manager (optional, off;
│                                     SPO's certificate provider)
│
├── jupyterGlue.* ─────────────────► [in-house] RBAC + ConfigMaps
│     (homeResize, fluentbit, sharedTeaching, sharedGroupStorage)
│
├── xnat.enabled ──────────────────► [in-house] XNAT extension ConfigMap + NetworkPolicy
│
├── namespace.create ───────────────► [in-house] Namespace (+ PodSecurity labels)
└── extraManifests[] ───────────────► [in-house] verbatim user manifests
```

## The Helm limitation this chart works around

**Plain Helm cannot template a subchart's values from a sibling toggle at
render time.** Values are merged and handed to each subchart *before* template
rendering; there is no supported way to make, say, the z2jh
`jupyterhub.singleuser` block depend on `security.appArmor.profileName` or
`cvmfs.enabled` during `helm template`. A parent chart can read the whole
`.Values` tree, but it cannot mutate a child's input from another child's flag.

Two places this bites the neurodesk stack:

1. **CVMFS volumes / FUSE device on singleuser pods.** The
   `jupyterhub.singleuser.extraVolumes`, `extraVolumeMounts`, and
   `extraResource.limits["smarter-devices/fuse"]` that mount `/cvmfs` and claim
   the FUSE device are part of the z2jh values block — they cannot be
   auto-toggled by `cvmfs.enabled`.
2. **Security profile attachment.** The
   `jupyterhub.singleuser.extraPodConfig.securityContext.appArmorProfile`
   (and any seccomp profile) references a profile **by name**. That reference
   lives in the z2jh block and cannot be auto-synced from
   `security.appArmor.profileName` / `security.seccomp.profileName`.
3. **StorageClass for the hub DB / home PVCs.** `global.storageClassName` covers
   only this chart's **own** in-house PVCs (e.g. the Squid cache); it cannot be
   templated into the z2jh subchart's PVCs. The hub state DB and singleuser home
   PVCs take their StorageClass from the z2jh keys
   `jupyterhub.hub.db.pvc.storageClassName` and
   `jupyterhub.singleuser.storage.dynamic.storageClass`, which you set directly.
   The `validation.storageClassNotBridged` guard **fails the render** if
   `global.storageClassName` is set but those z2jh keys are left empty — the
   common "I set the storage class but my PVCs still landed on the default SC"
   mistake.

### How the chart works around it

- **Opinionated defaults.** `values.yaml` ships the common baseline already
  wired together: the neurodesktop singleuser image, the `/cvmfs` volume + mount
  with `mountPropagation: HostToContainer`, the `smarter-devices/fuse` resource
  request, `/dev/shm`, and an AppArmor `appArmorProfile` of type `Localhost`
  pointing at the `notebook` profile. Out of the box, "CVMFS on + AppArmor on"
  matches the singleuser block, so the default install is internally
  consistent.

- **Overlays.** Each deployment supplies a `-f <overlay>.yaml` that layers its
  auth, ingress, secrets and any *deviations* from the defaults. If you turn a
  component **off**, you adjust the matching z2jh block in your overlay — e.g.
  disabling CVMFS means removing the `/cvmfs` volume + FUSE request from
  `jupyterhub.singleuser`, and changing the AppArmor profile name means updating
  both `security.appArmor.profileName` and the singleuser `appArmorProfile`
  reference together. The `values.yaml` comments call out exactly which blocks
  must be kept in sync; see [security.md](security.md) and [cvmfs.md](cvmfs.md).

This "consistent defaults + explicit overlay sync" pattern is the chart's
answer to the limitation: it makes the common case zero-config and the
divergent cases an explicit, documented two-line edit rather than a silent
mismatch.

## Helper templates

In-house templates rely on a small set of helpers in `templates/_helpers.tpl`:

| Helper | Purpose |
| --- | --- |
| `neurodesk.name` | Chart name, overridable via `nameOverride`. |
| `neurodesk.fullname` | Fully-qualified release name, overridable via `fullnameOverride`. |
| `neurodesk.chart` | `name-version` chart label value. |
| `neurodesk.namespace` | Deploy namespace: `namespace.name` or the release namespace. |
| `neurodesk.labels` | Standard label set (chart, name, instance, version, managed-by, `part-of: neurodesk`). |
| `neurodesk.selectorLabels` | The `app.kubernetes.io/name` + `instance` selector subset. |
| `neurodesk.storageClass` | Effective StorageClass: explicit arg, else `global.storageClassName`, else `""` (cluster default). Usage: `include "neurodesk.storageClass" (list . $explicitSC)`. |
| `neurodesk.cvmfsHttpProxy` | `CVMFS_HTTP_PROXY` value: the in-cluster Squid service when `global.cvmfs.squidEnabled`, else `DIRECT`. |
