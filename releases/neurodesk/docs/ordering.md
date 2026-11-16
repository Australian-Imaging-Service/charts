# Install ordering & race conditions

The script-driven ais-devstack install encodes ordering **manually** with a
numbered sequence and `kubectl wait` gates:

```
1 cleanup → 2 Longhorn → 3 CVMFS → 4 monitoring →
5 Security Profiles Operator (wait ready, ensure CRDs, then apply profile CRs) →
6 JupyterHub (wait hub/proxy ready)
```

neurocloud encodes it with ArgoCD (each component is a separate Application that
ArgoCD retries until healthy, plus a few `sync-wave` / hook annotations).

This chart replaces both with **one `helm install`** and lets Helm's
deterministic ordering do the sequencing. You do **not** run steps yourself.

> Install with an explicit `--namespace`. The z2jh `image-awaiter` Job (and
> other in-subchart objects) target `default` when no namespace is given, which
> silently puts pieces of the release in the wrong namespace. Always pass
> `--namespace <ns> --create-namespace`. See [install.md](install.md).

## What Helm orders for you (no configuration needed)

### 1. CRDs install before any custom resource
Helm installs everything under a chart's `crds/` directory **before** rendering
and applying `templates/`. The vendored `security-profiles-operator` subchart
ships the `AppArmorProfile` and `SeccompProfile` CRDs in its `crds/` dir, so
they always exist before this chart's profile CRs are applied. This is the
exact "ensure CRD, then apply profile" step that
`ais-devstack/jupyterhub/8-security-setup.sh` did by hand.

When `cert-manager.enabled=true`, cert-manager's CRDs are **templates** in its
chart (`crds.enabled=true`), not a `crds/` dir. Helm applies them as
`CustomResourceDefinition` objects, which come first in its kind order (below).
Nothing in this release creates cert-manager resources at install time: the SPO
operator requests its Issuer and Certificates at runtime.

> Caveat (a Helm limitation, not specific to this chart): Helm installs `crds/`
> on first install but does **not** upgrade or delete them. To update SPO CRDs
> later, re-apply the vendored `crds/` manually. See "Upgrades" below.

### 2. Resources install in Helm's kind order
Within a release (parent **and** all subcharts are sorted together), Helm
applies resources in a fixed kind order. The parts that matter here:

```
Namespace → NetworkPolicy → ... → StorageClass → ... →
ConfigMap → Secret → ... → ServiceAccount → ClusterRole/Role →
ClusterRoleBinding/RoleBinding → ... → PersistentVolumeClaim → ... →
DaemonSet → Deployment → StatefulSet → ... → (validating/mutating webhooks)
```

So, automatically:
- The **cvmfs-csi automount `StorageClass` (named `cvmfs`) is created before the
  `cvmfs` and `cvmfs-probe` PVCs** that reference it — no Pending-forever race.
- **RBAC and ConfigMaps exist before the Deployments/DaemonSets** that use them
  (trace-parser SA before its Deployment, CVMFS config ConfigMaps before the
  cvmfs-csi nodeplugin, etc.).

## The one potential race — and why it isn't one here

A bundled admission webhook *could* block pod creation during install if it
becomes active before its backing controller is ready. The Security Profiles
Operator avoids this:

- Its `MutatingWebhookConfiguration` ships **with no rules** — the SPO
  controller populates it at runtime once it is up. Until then it intercepts
  nothing, so it cannot block the Hub/proxy pods during install.
- SPO 1.0.0 gets its webhook and metrics certificates, and the CA bundle of its
  CRD conversion webhooks, from **cert-manager**. The operator creates its
  Issuer and Certificates in namespace `security-profiles-operator` at runtime,
  once it is up, so cert-manager only has to be running by then: either already
  in the cluster, or installed by this same release (`cert-manager.enabled=true`).
  The render refuses to proceed when neither is true (guard 5c, see
  [security.md](security.md#how-the-chart-checks-for-spo)).
- SPO's binding webhook is **opt-in per namespace** (label-gated), so it does
  not interfere with unrelated workloads.

The `AppArmorProfile` / `SeccompProfile` CRs are applied with the release and
reconciled by SPO once its node DaemonSet (`spod`) is ready. Applying a CR
before the controller is ready is safe — it is simply stored and picked up on
reconcile (the same end state the devstack `kubectl wait` produced, without the
manual wait).

## Runtime (spawn-time) dependencies — not install ordering

These are needed before a **user spawns a notebook**, not at chart install:

- The `cvmfs` PVC and CVMFS CSI nodeplugin must be healthy before a singleuser
  pod mounts `/cvmfs`. Both ship in this chart; by the time anyone spawns, they
  are up.
- `smarter-devices/fuse` must be allocatable on the node the notebook lands
  on — requires the `smarter-device-manager` DaemonSet (shipped) to run there.

### The FUSE device plugin must run where notebooks run

No node label is needed: the chart runs the `smarter-device-manager` DaemonSet
on every Linux node (`smarter-device-manager.nodeSelector:
{kubernetes.io/os: linux}`). Chart 0.1.x left the selector empty, so the
upstream chart's hard-coded `smarter-device-manager: enabled` selector applied
and nodes had to be labelled by hand.

It can still miss nodes: it tolerates only the `smarter.type=edge` taint, and a
`nodeSelector` you add in your overlay narrows it further (your keys are merged
with the default). A notebook scheduled on a node without the plugin stays
`Pending` (no node can satisfy its `smarter-devices/fuse: "1"` request).
Nothing in the install errors — it only shows at spawn time.

## The z2jh image pre-puller is disabled by default

z2jh ships a **hook image-puller** (`prePuller.hook.enabled`) — a pre-install
Job + DaemonSet that pre-pulls the singleuser image onto every node and, via the
`image-awaiter` Job, **blocks `helm install` from returning** until the pull
completes on all nodes. For Neurodesk's multi-GB `neurodesktop` image that means
minutes of install stall (or an outright rollback on slow / airgapped
registries). This chart therefore disables **both** the hook puller and the
continuous puller by default:

```yaml
jupyterhub:
  prePuller:
    hook:       { enabled: false }
    continuous: { enabled: false }
```

So install returns promptly and each node pulls the image lazily on the **first**
spawn there (that one spawn is slow; later ones on the same node are fast).
Re-enable the puller if you want pre-warmed nodes and can tolerate the longer
install.

## Operator prerequisites the chart cannot order (cluster-level)

The chart consumes these by name; create them before (or alongside) install:

| Prereq | Why | How |
| --- | --- | --- |
| A default/named **StorageClass** | hub DB + home PVCs (z2jh) + this chart's in-house PVCs | cluster default, or set the z2jh keys `jupyterhub.hub.db.pvc.storageClassName` / `jupyterhub.singleuser.storage.dynamic.storageClass` for the hub DB / home PVCs (`global.storageClassName` only covers this chart's own in-house PVCs) |
| Notebook nodes the FUSE device plugin can run on | FUSE device allocation (no plugin on a node => spawns there stay Pending) | nothing by default: it runs on every untainted Linux node (`smarter-device-manager.nodeSelector`, default `kubernetes.io/os: linux`); no node label needed |
| **Prometheus Operator CRDs** (`monitoring.coreos.com`) | only if `infra.monitoring.serviceMonitors=true` or trace-parser/probe ServiceMonitors | install kube-prometheus-stack (out of scope) |
| **cert-manager** | if `security.installOperator=true` (the default) | already running in the cluster, or set `cert-manager.enabled=true` to install it with the release (only on a cluster with none). See [security.md](security.md#cert-manager-required-by-spo) |
| Existing **SPO ≥ 1.0.0** + its CRDs | only if `security.installOperator=false` | the cluster already runs SPO ≥ 1.0.0 (API `v1`; SPO 0.x is not compatible). The render checks for it; for an offline render assert it with `security.assumeCrdsPresent=true` (see [security.md](security.md)) |

## Upgrades

- `helm upgrade` re-applies templates in the same kind order.
- Helm will **not** upgrade/delete the SPO CRDs (Helm CRD limitation). If a
  future re-vendored SPO bumps its CRDs, re-apply
  `vendor/security-profiles-operator/crds/` manually before upgrading.
- **Upgrading from chart 0.1.x is different.** A 0.1.x release that bundled
  the neurodesk SPO fork cannot be upgraded in place (guard 5a stops
  `helm upgrade` before Helm changes anything). See
  [migration.md](migration.md#01x---020).
- The CVMFS server URL and the Squid on/off toggle are now a **single source of
  truth** under `global.cvmfs.server` / `global.cvmfs.squidEnabled` — read by
  both this chart's templates and the cvmfs-csi subchart's ConfigMaps, so there
  is nothing to keep mirrored across upgrades (see [cvmfs.md](cvmfs.md)).

## When consumed via ArgoCD (neurocloud)

ArgoCD renders the chart with `--include-crds` and applies CRDs in its own
CRD-first phase, then reconciles the rest, retrying until healthy — so the same
ordering holds. It also passes the destination cluster's API versions to the
render, so the SPO/cert-manager guards see what the cluster actually serves. If you want stricter sequencing you can add
`argocd.argoproj.io/sync-wave` annotations via `extraManifests` or a values
overlay, but it is not required for a correct install.
