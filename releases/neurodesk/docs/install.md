# Installation

This chart installs the Neurodesk **application** stack onto a cluster that
already runs the required **infrastructure**. It does not install Longhorn,
ingress controllers, ArgoCD, the Prometheus stack, or nfs-server — those are
consumed by name. cert-manager is consumed by name too, unless you opt in to
installing it with the release (`cert-manager.enabled=true`, for a cluster that
has none).

## Prerequisites

| Prerequisite | Why | How it's referenced |
| --- | --- | --- |
| **Kubernetes ≥ 1.30** | `Chart.yaml` sets `kubeVersion: ">=1.30.0-0"`: the default singleuser AppArmor attachment uses the **native** `securityContext.appArmorProfile` field (added in k8s 1.30 as beta, on by default; GA in 1.31; silently ignored, so unenforced, on older clusters). z2jh 4.4 needs ≥1.28 — this is the stricter bound. | `helm install` aborts on clusters below 1.30. |
| A **StorageClass** | Hub DB PVC + per-user home PVCs (RWO) + this chart's in-house PVCs (Squid cache). | The hub DB / home PVCs are set on the **z2jh** keys `jupyterhub.hub.db.pvc.storageClassName` and `jupyterhub.singleuser.storage.dynamic.storageClass` (`global.storageClassName` covers only this chart's in-house PVCs and does **not** reach them). Unset => cluster default. Do not set the hub DB key to `""`: that means "no StorageClass" and the hub DB PVC never binds (see [values.md](values.md); the one exception is an in-place upgrade from 0.1.x). |
| **Untainted Linux nodes for notebooks** (when `cvmfs.enabled=true`) | The FUSE device plugin (smarter-device-manager) must run where notebooks run, or `smarter-devices/fuse` is advertised nowhere and **every** spawn stays `Pending`. It runs on every Linux node by default; no node label is needed. | `smarter-device-manager.nodeSelector` (default `kubernetes.io/os: linux`). It tolerates only the `smarter.type=edge` taint. |
| **Security Profiles Operator** | Loads AppArmor/Seccomp profiles onto nodes. Bundled (upstream 1.0.0) & ON by default; runs in namespace `security-profiles-operator`. | `security.installOperator` — set `false` only if SPO ≥ 1.0.0 is already installed. |
| **cert-manager** (required when `security.installOperator=true`) | SPO's webhook and metrics certificates and its CRD conversion CA. | Either already running in the cluster, or installed by this release with `cert-manager.enabled=true` (only on a cluster with **no** cert-manager). The render fails if neither holds. |
| **Prometheus Operator CRDs** | Needed before any ServiceMonitor renders. | `infra.monitoring.serviceMonitors` / `cvmfs.traceParser.enabled`. Leave monitoring off unless `monitoring.coreos.com` CRDs exist. |
| **Ingress controller** (optional) | External access to the Hub. | `jupyterhub.ingress.enabled` + `jupyterhub.ingress.ingressClassName` (z2jh's own Ingress — this chart adds no separate one). |
| **cert-manager Issuer** (optional) | TLS for the Hub ingress. | `cert-manager.io/cluster-issuer` under `jupyterhub.ingress.annotations`, plus `jupyterhub.ingress.tls`. |
| **External XNAT server** (optional) | Target for the XNAT upload extension. | `xnat.server.host` / `xnat.server.namespace`. |

### The FUSE device plugin (no node label needed)

With `cvmfs.enabled=true` the chart runs smarter-device-manager, which
advertises `smarter-devices/fuse`, on **every Linux node**
(`smarter-device-manager.nodeSelector: {kubernetes.io/os: linux}`). Earlier
versions left the selector empty, and the upstream chart then falls back to a
hard-coded `smarter-device-manager: enabled` selector, which is why nodes had to
be labelled by hand. That label is no longer needed.

To limit the plugin to some nodes, set `smarter-device-manager.nodeSelector` in
your overlay. Helm **merges** it with the default, so your keys are added to
`kubernetes.io/os: linux` and a node must match both. Do not null the default
key: across the subchart boundary the `null` survives into the rendered
selector. The plugin tolerates only the `smarter.type=edge` taint (hard-coded
upstream), so it does not run on nodes with other `NoSchedule` taints; a
notebook scheduled there stays `Pending`.

### Security Profiles Operator

SPO (upstream kubernetes-sigs 1.0.0, vendored) is **bundled and installed by
default** (`security.installOperator=true`). It always runs in namespace
**`security-profiles-operator`** — upstream 1.0.0 hard-codes that namespace —
whatever release namespace you install into. The release creates that
namespace (PSA `enforce: privileged`, kept on uninstall); the app itself stays
in the release namespace.

If your cluster already runs **SPO ≥ 1.0.0**, set
`security.installOperator=false` so the chart won't install a second operator
and only renders its profile CRs. The render then checks that the cluster
serves the SPO `v1` API. SPO 0.x — including the neurodesk fork that chart
0.1.x bundled — is **not** compatible. SPO is a cluster singleton, and the
profile CRs are cluster-scoped, so on a shared cluster a second SPO collides and
a second release needs its own profile name — see the shared-cluster warning in
[security.md](security.md). If you run with **no** SPO at all, you must load the
profiles onto nodes yourself (same page).

Upgrading a 0.1.x release that bundled the fork is **not** an in-place upgrade —
see [migration.md](migration.md#01x---020).

### cert-manager

The bundled SPO needs cert-manager. With `security.installOperator=true`:

- **The cluster already runs cert-manager** — install as usual. Keep
  `cert-manager.enabled=false`.
- **The cluster has none** — add `--set cert-manager.enabled=true` and this
  release installs cert-manager `v1.21.2` (into the release namespace; its CRDs
  are kept on uninstall). This release then owns cert-manager.

Never enable it on a cluster that already has cert-manager: it is a cluster
singleton and the chart never adopts an existing install. If neither holds, the
render fails with instructions (guard `certManagerMissing`).

### Prometheus CRDs

`ServiceMonitor` objects only render when you opt in, and they require the
`monitoring.coreos.com` CRDs to already exist. Keep
`infra.monitoring.serviceMonitors=false` (and `cvmfs.traceParser.enabled=false`)
on clusters without a Prometheus Operator, or the apply will fail on unknown
kinds.

## 1. Pull subchart dependencies (from a source checkout)

`Chart.lock` is **committed**, so the pinned subchart versions are fixed. To
fetch the locked tarballs into `charts/`, first add the two HTTP repos the lock
references, then run `helm dependency build` (which honors `Chart.lock` rather
than re-resolving):

```sh
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
helm repo add smarter-device-manager https://smarter-project.github.io/smarter-device-manager
helm dependency build          # downloads the LOCKED versions into charts/
```

(`cvmfs-csi` and `cert-manager` come from OCI registries and
`security-profiles-operator` is vendored under `vendor/`, so none of them needs
a `helm repo add`.)

Use `helm dependency build` — **not** `helm dependency update` — for a normal
install: `build` respects the committed lock, while `update` re-resolves the
dependency ranges and rewrites `Chart.lock`. Only run `helm dependency update`
when you intentionally want to bump a subchart.

Installing from the published OCI artifact
(`ghcr.io/neurodesk/charts/neurodesk`) ships the dependencies already packaged,
so this step is only needed when installing from a source checkout.

> The chart ships a **`values.schema.json`** that validates its own in-house
> blocks, so a **mistyped toggle fails fast** at `helm template`/install — e.g.
> `cvmfs.enable` instead of `cvmfs.enabled`, or an unknown key under
> `infra`/`security`/`xnat`/`validation` — instead of silently no-op'ing. The
> subchart passthrough keys stay permissive. See [values.md](values.md).

## 2. Install

**`--namespace` is REQUIRED** (not just good hygiene). Without it the z2jh
`image-awaiter` Job and other subchart objects target the `default` namespace,
splitting the release across namespaces. Always pass an explicit
`--namespace`:

```sh
helm install neurodesk . \
  --namespace neurodesk --create-namespace \
  -f my-values.yaml
```

…where `my-values.yaml` is your overlay (auth, ingress host, secrets, and any
component toggles). The chart installs into the **release namespace**; the
in-house templates resolve it via `neurodesk.namespace`
(`namespace.name` or `.Release.Namespace`). The bundled SPO is the exception:
it runs in namespace `security-profiles-operator`.

That command is right for a cluster that **already runs cert-manager**. The
other two starting points:

```sh
# Standalone: a cluster with NO cert-manager. One release installs everything,
# cert-manager included.
helm install neurodesk . \
  --namespace neurodesk --create-namespace \
  --set cert-manager.enabled=true \
  -f my-values.yaml

# External SPO: the cluster already runs Security Profiles Operator >= 1.0.0.
# No operator and no cert-manager from this release. Use a profile name no
# other release uses, in BOTH places (profiles are cluster-scoped).
helm install neurodesk . \
  --namespace neurodesk --create-namespace \
  --set security.installOperator=false \
  --set security.appArmor.profileName=neurodesk-notebook \
  --set jupyterhub.singleuser.extraPodConfig.securityContext.appArmorProfile.localhostProfile=neurodesk-notebook \
  -f my-values.yaml
```

> The singleuser image is **not** pre-pulled. z2jh's hook image-puller is
> disabled by default (it would block this `helm install` until the multi-GB
> `neurodesktop` image lands on every node), so install returns promptly and each
> node pulls the image lazily on its first spawn. See
> [ordering.md](ordering.md#the-z2jh-image-pre-puller-is-disabled-by-default).

A minimal overlay:

```yaml
global:
  domain: neurodesk.example.org
  # global.storageClassName only covers this chart's OWN in-house PVCs (Squid
  # cache). It does NOT reach the hub DB or singleuser home PVCs — those are z2jh
  # subchart PVCs and must be set on the z2jh keys below. (Setting this while the
  # z2jh keys are empty trips the `validation.storageClassNotBridged` guard.)
  storageClassName: longhorn

jupyterhub:
  # Ingress/TLS is z2jh's own — the chart adds no separate Ingress object.
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod   # TLS via cert-manager
    hosts: [neurodesk.example.org]                        # = global.domain
    tls:
      - secretName: jupyter-tls
        hosts: [neurodesk.example.org]
  hub:
    config:
      GitHubOAuthenticator:
        client_id: "..."          # client_secret via existingSecret, NOT here
      JupyterHub:
        authenticator_class: github
      Authenticator:
        admin_users: [your-admin]
    # The REAL hub DB StorageClass knob (global.storageClassName does NOT reach it).
    db:
      pvc:
        storageClassName: longhorn
  singleuser:
    storage:
      # The REAL per-user home StorageClass knob (likewise not bridged from global).
      dynamic:
        storageClass: longhorn
  proxy:
    # proxy.secretToken + hub.cookieSecret via existingSecret — see secrets.md
```

(For worked `jupyterhub.ingress` examples see
[`examples/neurocloud-values.yaml`](../examples/neurocloud-values.yaml) and
[`examples/devstack-values.yaml`](../examples/devstack-values.yaml).)

Installing from the OCI registry instead of a checkout:

```sh
helm install neurodesk oci://ghcr.io/neurodesk/charts/neurodesk \
  --version <chart-version> \
  --namespace neurodesk --create-namespace \
  -f my-values.yaml
```

## 3. Verify

```sh
kubectl -n neurodesk get pods
# Hub URL (jupyterhub.ingress.enabled=true):   https://<global.domain>
# Hub URL (ingress off):  kubectl -n neurodesk port-forward svc/proxy-public 8080:80
```

The chart's `NOTES.txt` prints a per-release summary of which components are ON
and the outstanding cluster prerequisites.

## Per-component enable / disable

Every component is independently toggleable. Turn one on or off to run it
yourself separately:

```sh
--set jupyterhub.enabled=false        # bring your own JupyterHub
--set cvmfs.enabled=false             # run cvmfs-csi / mounts yourself
--set global.cvmfs.squidEnabled=true  # add the in-cluster Squid cache (single toggle)
--set cvmfs.probe.enabled=false       # drop the health probe
--set cvmfs.traceParser.enabled=true  # enable trace-parser telemetry
--set security.enabled=false          # no AppArmor/Seccomp CRs (the operator is installOperator)
--set security.installOperator=false  # cluster already runs SPO >= 1.0.0
--set cert-manager.enabled=true       # install cert-manager too (cluster has none)
--set xnat.enabled=true               # add XNAT notebook integration
--set jupyterGlue.fluentbit.enabled=true
```

### Disabling a component correctly (the merge gotchas)

Flipping the top-level toggle off is **not enough** — you must also strip the
matching pieces out of the z2jh `jupyterhub.singleuser` block in your overlay,
because plain Helm cannot mutate a subchart's values from a sibling toggle. Two
Helm merge behaviors make this a footgun:

- **Maps MERGE.** Setting a sub-block to `{}` does **not** remove inherited keys.
  To drop inherited defaults, null the **whole submap** — e.g.
  `extraResource: { limits: null, guarantees: null }` (renders a clean
  `extraResource: {}`) or null a whole object like
  `extraPodConfig.securityContext.appArmorProfile: null`. **Do NOT null just the
  leaf** (`extraResource.limits.smarter-devices/fuse: null`): across the subchart
  boundary that `null` survives into the hub config as an invalid `null` quantity
  and breaks the spawn. See [disabling-components.md](disabling-components.md).
- **Lists REPLACE.** Restating `storage.extraVolumes` replaces the whole list, so
  whatever you omit is dropped (handy for removing the `cvmfs` volume — but note
  the inverse: forgetting to restate the `cvmfs` volume when you meant to keep it
  silently removes `/cvmfs`).

The chart ships **render-time validation guards** (`validation.*`, see below)
that **fail the render** with an actionable message when a toggle and the
singleuser block disagree — so a forgotten null-delete or list-restate is a loud
error at `helm template`/install, not a silently-stranded spawn.

**Worked example — turning CVMFS off the right way** lives in
[`ci/ct-values-minimal.yaml`](../ci/ct-values-minimal.yaml): with
`cvmfs.enabled=false` (and `security.enabled=false` +
`security.installOperator=false`) it nulls the whole
`extraResource.limits` / `extraResource.guarantees` **submaps** (clean
`extraResource: {}` — not a leaf null), restates `extraVolumes`/`extraVolumeMounts`
to just `/dev/shm` (dropping the `cvmfs` volume), and nulls the whole
`appArmorProfile` attachment. Use it as the canonical template. For the full
per-component cookbook (cvmfs / security / xnat / jupyterhub), see
[disabling-components.md](disabling-components.md).

### Validation guards (fail-fast on inconsistent toggles)

The `validation.*` keys (all default `false` = guard **active**) back
`templates/validate.yaml`. Each aborts the render when a parent toggle and the
`jupyterhub.singleuser` block disagree:

| Key | Fires when |
| --- | --- |
| `storageClassNotBridged` | `global.storageClassName` is set but the z2jh hub-DB / home StorageClass keys (`jupyterhub.hub.db.pvc.storageClassName`, `jupyterhub.singleuser.storage.dynamic.storageClass`) are empty. |
| `fuseResourceWhenCvmfsOff` | `cvmfs.enabled=false` but singleuser still requests `smarter-devices/fuse`. |
| `cvmfsVolumeWhenCvmfsOff` | `cvmfs.enabled=false` but singleuser still mounts the `cvmfs` PVC. |
| `apparmorAttachWithoutProfile` | pod pins an AppArmor profile but `security.appArmor` is off (no CR backs it). |
| `apparmorNameMismatch` | pod's `localhostProfile` != `security.appArmor.profileName`. |
| `certManagerMissing` | `security.installOperator=true`, `cert-manager.enabled=false`, and the cluster does not serve `cert-manager.io/v1` `Certificate`. |
| `apparmorNoCrdProvider` | *No effect since 0.2.0* (guard removed; kept so old overlays validate). |

Set a single key to `true` only to deliberately bypass that one check (e.g. you
supply FUSE from a different device plugin).

Three more guards have no bypass key: the cluster serves only the legacy pre-1.0
SPO API while `installOperator=true` (a 0.1.x release — see
[migration.md](migration.md#01x---020)); `installOperator=false` but the cluster
does not serve the SPO `v1` kinds; and the removed
`xnat.uploadExtension.installerImage` key is set. Details in
[security.md](security.md#how-the-chart-checks-for-spo).

> `helm lint` reports a failing guard only as `[INFO] Fail: …` and still passes;
> `helm template`, `helm install` and `helm upgrade` enforce it.

## The `extraManifests` escape hatch

Need an extra resource (a Secret reference, a Service, a one-off CR) inside the
release? Add it to `extraManifests` instead of `kubectl apply`-ing out of band,
so it lives and dies with the Helm release. List items may be plain objects or
template strings (run through `tpl`):

```yaml
extraManifests:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: extra-config
    data:
      key: value
  - |
    apiVersion: v1
    kind: Secret
    metadata:
      name: my-ref
      namespace: {{ include "neurodesk.namespace" . }}
    type: Opaque
```

## `helm template | kubectl apply` alternative

If you cannot run Tiller-less Helm against the cluster (e.g. a GitOps pipeline
that only applies manifests), render the chart and apply the output:

```sh
helm dependency build          # honors the committed Chart.lock (see step 1)
kubectl config set-context --current --namespace neurodesk   # the release namespace (must exist)
helm template neurodesk . \
  --namespace neurodesk \
  --no-hooks \
  --include-crds \
  --api-versions cert-manager.io/v1/Certificate \
  -f my-values.yaml \
  | kubectl apply -f -
```

Caveats:
- **`-n` goes on `helm` only, never on `kubectl apply`.** The bundled SPO's
  objects carry `namespace: security-profiles-operator`, and an explicit
  `kubectl apply -n neurodesk` rejects every object whose namespace differs, so
  the operator is never created. Many other objects (all of z2jh's, for
  example) carry no namespace at all and land in the kube context's **current**
  namespace, which therefore must be the release namespace (the `set-context`
  line above).
- **`--no-hooks` is mandatory whenever the output is applied.** `kubectl`
  ignores Helm hook annotations, so without it the pre-delete
  [cleanup Job](#1-the-pre-delete-cleanup-hook-uninstallcleanup-default-on) is
  applied at **install** time and immediately deletes the profile and the CVMFS
  PVCs and stops the operator. (`helm template` without `--no-hooks` is fine
  only for inspecting output.)
- **No automatic uninstall.** A raw-applied install has no uninstall lifecycle.
  To remove it, do by hand what the hook does, in its order: stop every user
  server; delete this release's AppArmorProfile/SeccompProfile and wait until
  they are gone while `spod` still runs; delete the CVMFS consumers (the
  `cvmfs-probe` DaemonSet, then the `cvmfs` and `cvmfs-probe` PVCs) while the
  cvmfs-csi node plugin still runs; with the bundled operator, scale it to 0 and
  delete its runtime objects; only then delete the rest.
  `templates/uninstall-cleanup-hook.yaml` lists every step and object name. Or
  install with Helm instead.
- `--namespace` is required so `neurodesk.namespace` resolves correctly (there
  is no `.Release.Namespace` injection without it).
- **Assert the cluster's APIs.** An offline render cannot see the cluster, so
  the SPO guards need to be told what it runs. With **default** values the
  render fails until you do. Pick one:
  - the cluster runs cert-manager: `--api-versions cert-manager.io/v1/Certificate`
    (as above);
  - it has none: `--set cert-manager.enabled=true` instead;
  - external SPO (`security.installOperator=false`):
    `--api-versions security-profiles-operator.x-k8s.io/v1/AppArmorProfile`
    (plus `/SeccompProfile` if seccomp is on), or
    `security.assumeCrdsPresent=true`.

  Argo CD and Flux pass the live cluster's API versions, so they need none of
  these.
- `--include-crds`: without it `helm template` omits the SPO CRDs (the vendored
  chart's `crds/` dir).
- **z2jh secrets rotate on every render** under `helm template` /
  `--dry-run` / GitOps without live cluster state — `proxy.secretToken`,
  `hub.cookieSecret`, `CryptKeeper.keys` and `services.*.apiToken` get freshly
  regenerated each sync and break hub↔proxy auth and login cookies. **Pin them**
  via `existingSecret` / committed values. See [secrets.md](secrets.md).
- CRD ordering: the SPO CRDs must exist before the AppArmor/Seccomp CRs apply,
  and the Prometheus CRDs before any ServiceMonitor. With `helm install`, Helm
  orders these for you; with raw `kubectl apply` you may need two passes or to
  pre-install the operators.
- A GitOps **devstack** consumes the chart this way — see
  [consuming-from-devstack.md](consuming-from-devstack.md). **Argo CD** (how
  **neurocloud** consumes it, see
  [consuming-from-neurocloud.md](consuming-from-neurocloud.md)) also renders
  with `helm template` but handles hooks itself: Argo CD versions that map
  `helm.sh/hook: pre-delete` to their `PreDelete` hook run the cleanup Job when
  the Application is deleted; older versions do not apply the Job at all, so
  deleting the Application strands what the hook would have removed. Verify
  against your Argo CD version.

## Teardown / uninstall

1. **Stop every user server** and keep new logins out. The uninstall refuses
   to start while any exists in the release namespace (see below). If this
   release bundles the operator, first remove every other release or workload
   that uses it (see "What the hook does not cover").
2. **Back up hub state** if you may reinstall: `helm uninstall` deletes the
   `hub-db-dir` PVC (section 2).
3. Uninstall **with `helm uninstall`**:

```sh
helm uninstall neurodesk --namespace neurodesk
```

Do **not** tear down by deleting the release namespace. The bundled operator,
its `SecurityProfilesOperatorDaemon` and `spod` live in namespace
`security-profiles-operator`, so they survive, while the Helm release record
(stored in the release namespace) is deleted with it: the operator is left
running with nothing tracking it, and none of the cleanup below happens.

### 1. The pre-delete cleanup hook (`uninstallCleanup`, default on)

`helm uninstall` deletes every release object in one pass, but two bundled
controllers must outlive the objects they manage. Without help the uninstall
hangs and strands:

- the `AppArmorProfile` (and `SeccompProfile`), `Terminating` forever on its
  per-node finalizer, because the SPO node daemon (`spod`) is deleted in the
  same pass;
- the `cvmfs-probe` pod and PVC, because the cvmfs-csi node plugin is removed
  first and the volume can no longer be unmounted;
- the operator's **runtime** objects (created by the operator, not by Helm): the
  webhook Deployment and its Services, the cert-manager Issuer, Certificates and
  Secrets in namespace `security-profiles-operator`, and the cluster-scoped
  `ValidatingWebhookConfiguration` `spo-validating-webhook-configuration`
  (`failurePolicy: Fail`, so it keeps rejecting the requests it matches once
  nothing serves it).

So the release ships **pre-delete hooks** that run before Helm deletes
anything, in two stages: a read-only **check** Job (`<fullname>-pre-delete-check`,
e.g. `neurodesk-pre-delete-check`), then the **cleanup** Job
(`<fullname>-pre-delete`) and its RBAC, which remove exactly those objects, by
name, while their controllers still run. Helm then deletes the rest.

**The check refuses while any user server exists** (pods labelled
`component=singleuser-server` in the release namespace). Deleting the profile
unloads it from the kernel, and a notebook still confined by it could no
longer start any process. The check Job then fails **before anything is
deleted**: Helm stops at the first failed hook, so the cleanup Job and its
delete permissions are never created. The uninstall stops, and the release is
left in Helm status `uninstalling` (`helm upgrade` then refuses it). Two ways
on, both verified on a test cluster:

```sh
kubectl -n neurodesk get jobs | grep pre-delete                               # the failed hook Job
kubectl -n neurodesk logs job/neurodesk-pre-delete-check --all-containers     # why it refused
# (the failed Job is kept for these logs; nothing with delete rights is left behind)

# a) still want it gone: stop every server, then simply run the uninstall again
helm uninstall neurodesk -n neurodesk

# b) keep using it: roll back to the revision `helm history` shows as `uninstalling`
#    (the latest one - for a release never upgraded that is revision 1)
helm history neurodesk -n neurodesk
helm rollback neurodesk <revision-marked-uninstalling> -n neurodesk
```

`helm uninstall --no-hooks` skips the hook and accepts the
stranding above; `uninstallCleanup.enabled=false` removes it (keys in
[values.md](values.md#uninstallcleanup--pre-delete-cleanup-hook)).

The hook renders when `uninstallCleanup.enabled` **and** the release owns a
profile, manages CVMFS (`cvmfs.enabled=true`) or bundles the operator
(`security.installOperator=true`). The deletion steps render only for what the
release bundles. So with an external operator **and** external CVMFS (e.g. the
neurocloud adoption overlay) the hook is **precondition-only** — just
`require-no-user-servers` plus its ServiceAccount, Role and RoleBinding —
because Helm still deletes this release's profile and the external operator
unloads it: the uninstall refuses while user servers run there too.

**What the hook does not cover:**

- **Only `helm uninstall`.** A `helm upgrade` that turns the bundled operator or
  CVMFS off (`security.installOperator` or `cvmfs.enabled` from `true` to
  `false`) removes the operator or the CSI driver in one pass, with the same
  stranding. Treat such a switch as uninstall + reinstall, or first remove what
  depends on them: this release's profiles while `spod` still runs; user
  servers, the `cvmfs-probe` DaemonSet and the CVMFS PVCs while the node plugin
  still runs.
- **Only this release's user servers.** The precondition checks pods labelled
  `component=singleuser-server` in this release's namespace; it is **not** a
  global check for consumers. A release with `installOperator=true` owns a
  cluster singleton: every other release using that operator
  (`installOperator=false`) and any other workload using SPO profiles must be
  removed or moved first. **Uninstall the operator-owning release last.**

### 2. PVCs the release created ARE deleted — back up hub state first

The **`hub-db-dir`** PVC (z2jh hub state: user list, server records), the
**`cvmfs`** and **`cvmfs-probe`** PVCs and, when Squid is on, the
**`cvmfs-squid-cache`** PVC are release objects (no
`helm.sh/resource-policy: keep`), so the uninstall **deletes** them. What
happens to the data then depends on the StorageClass reclaim policy:

- **`Delete`-policy SCs destroy the volume** with the PVC — deleting
  `hub-db-dir` **destroys hub state**.
- **`Retain`-policy SCs keep the PV** (and its backing volume) after the PVC is
  gone; delete those by hand to reclaim storage.

### 3. What remains after a clean uninstall (by design)

| Left behind | Why | Remove it |
| --- | --- | --- |
| Per-user **`claim-*`** home PVCs | Created by KubeSpawner at spawn time, not by Helm (z2jh keeps homes). | By hand, once the user data is no longer needed. |
| The **8 SPO CRDs** | Shipped in the vendored chart's `crds/`, which Helm never upgrades or deletes. | Only for a full SPO teardown (below). |
| The **6 cert-manager CRDs** (when `cert-manager.enabled=true`) | `cert-manager.crds.keep=true`, so Certificates elsewhere in the cluster survive. | Only if nothing else in the cluster uses cert-manager. |
| Namespace **`security-profiles-operator`** — empty | `helm.sh/resource-policy: keep`; the hook has emptied it. | `kubectl delete namespace security-profiles-operator` |
| Secret **`<release>-cert-manager-webhook-ca`** in the release namespace (when `cert-manager.enabled=true`) | Created at runtime by cert-manager's webhook; upstream cert-manager behaviour. | `kubectl -n <namespace> delete secret <release>-cert-manager-webhook-ca` |
| cvmfs-csi **autofs mounts under `/var/cvmfs`** on the nodes | Upstream cvmfs-csi behaviour when its node plugin is removed. | Cleared on node reboot. |
| PVs of deleted PVCs on `Retain` StorageClasses | Reclaim policy (section 2). | By hand. |
| Leader-election **Leases** (in the release namespace, `security-profiles-operator` and, with bundled cert-manager, `kube-system`) | Created at runtime by the controllers; nothing owns them. | Harmless; `kubectl -n <ns> delete lease <name>` if wanted. |
| SPO's own AppArmor profiles **`spo-apparmor`** and **`bpfrecorder-apparmor`** on each node (loaded, and in `/etc/apparmor.d`), plus `/var/lib/security-profiles-operator`, `/var/lib/kubelet/seccomp` and `/var/lib/cvmfs.csi.cern.ch` | Written by spod and cvmfs-csi on the host; upstream behaviour. | Harmless; remove from the hosts only for a full node clean-up. |

**Reinstalling after an uninstall** (both seen on a test cluster):

- The kept cert-manager CRDs still carry the old release's Helm ownership. A
  reinstall with the **same release name and namespace** adopts them; a
  different name or namespace is refused (`... exists and cannot be imported into
  the current release`). Reinstall with the same release name and namespace
  (the tested path), or delete the 6 cert-manager CRDs first if nothing else in
  the cluster uses cert-manager. Installing cert-manager as a separate Helm
  release does not get around this: it meets the same retained ownership.
- The kept `security-profiles-operator` namespace is likewise adopted only by the
  same release. If it exists but is not owned by this release (for example it
  was created by `--create-namespace` when the release itself lived there),
  set `security-profiles-operator.operatorNamespace.create=false`.

```sh
kubectl -n neurodesk get pvc                       # what is left: the claim-* homes
kubectl -n neurodesk delete pvc claim-<user> ...    # user homes, once no longer needed
kubectl get pv | grep Released                      # Retain-policy volumes left behind
```

**Full SPO teardown** — only when **no** other release or SPO on the cluster
uses the CRDs: deleting a CRD deletes every profile of that kind cluster-wide,
including other releases'. Never do this as a step of an upgrade (see
[migration.md](migration.md)).

The same step clears the CRDs a **0.1.x** release left behind after it was
uninstalled: they serve only the fork's legacy API, so a fresh 0.2.0 install is
refused until they are gone. The fork's 8 CRDs have the same names as the
vendored ones, so the command below removes them too — under the same
condition: no other SPO user on the cluster.

```sh
kubectl get crd | grep security-profiles-operator.x-k8s.io
kubectl delete -f vendor/security-profiles-operator/crds/   # full SPO teardown only
```

### 4. An external SPO's webhooks (when `installOperator=false`)

With `security.installOperator=false` the chart **never owned** the SPO
webhooks (they belong to the pre-existing/external SPO). The uninstall leaves
them in place — which is correct (that SPO is shared), so do **not** delete them
as part of tearing down this release. (When `installOperator=true`, the bundled
SPO's `spo-mutating-webhook-configuration` is a release object and its runtime
validating webhook is removed by the hook.)
