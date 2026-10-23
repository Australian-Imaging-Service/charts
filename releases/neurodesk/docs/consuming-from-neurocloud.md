# Consuming this chart from neurocloud

[neurocloud](https://github.com/neurodesk/neurocloud) is an **ArgoCD
app-of-apps**: a root `Application` that points at child `Application`s, each
deploying a slice of the platform. Today the JupyterHub-centric slice is spread
across three of those children, and two of them own much more than the
notebook layer:

| neurocloud app (today) | What it owns |
| --- | --- |
| `charts/jupyter` | JupyterHub (hub, proxy, the hub DB PVC, the ingress host). |
| `mounts` | CVMFS, including the cluster-scoped CSIDriver `cvmfs.csi.cern.ch` and StorageClass `cvmfs`. |
| `security` (`charts/apps/templates/security.yml`) | The upstream Security Profiles Operator v1.0.0 install **and** `charts/security`: neurocloud's AppArmor profile, the `neurocloud-spo-apparmor` RBAC grant the operator needs, cryptnono and the DNS filter. |

There are two ways to use this chart there. They differ in who owns the
operator and the CVMFS driver.

## (a) Fresh cluster: bundled install

On a cluster **without** neurocloud's `mounts` and `security` apps, one
`Application` with the chart's defaults installs the whole slice: JupyterHub,
CVMFS (`cvmfs.enabled=true`) and the bundled SPO (`security.installOperator=true`).
neurocloud provisions cert-manager as infrastructure, so keep
`cert-manager.enabled=false` (set it `true` only if that cluster has none).

SPO and the CVMFS driver are cluster singletons. If neurocloud's `security` app
(for cryptnono and the DNS filter) or `mounts` app will also run on that
cluster, they install the same objects: use (b) instead.

## (b) Existing neurocloud: adopt alongside the owning apps

This is what
[`examples/neurocloud-values.yaml`](../examples/neurocloud-values.yaml) is for.
The chart runs **next to** the existing apps and **reuses** what they own:

- `security.installOperator=false` — no operator, CRDs or operator RBAC from
  this release; it uses the SPO that the `security` app installs (the chart
  then needs no cert-manager of its own). ArgoCD passes the cluster's API
  versions to the render, so the chart's SPO check sees the real `v1` API.
- `cvmfs.enabled=false` + `cvmfs.external=true` — no CSIDriver, StorageClass or
  device plugin from this release; the notebooks mount a `cvmfs` PVC on the
  `mounts` app's `cvmfs` StorageClass (the overlay creates that PVC in its own
  namespace via `extraManifests`).
- A distinct AppArmor profile name, `neurodesk-notebook`, in **both**
  `security.appArmor.profileName` and the singleuser
  `appArmorProfile.localhostProfile`: profiles are cluster-scoped and neurocloud
  already owns one named `notebook`.
- Its own namespace, release name and ingress host. z2jh's in-namespace names
  (`hub`, `proxy-public`, `hub-db-dir`) are fixed, so it cannot share the
  `charts/jupyter` app's namespace.

**Keep the `mounts` and `security` apps.** They own the operator, its RBAC and
CRDs, the CVMFS CSI driver and the `cvmfs` StorageClass this release depends on. Pruning
or deleting either app removes them from under the chart (and takes cryptnono
and the DNS filter with it). Never let two Applications render the same object
either: they fight over it, and pruning one deletes it for both — which is why
(b) turns the chart's own operator and CVMFS off.

### Consolidating later (plan, not rehearsed)

Moving to a single owner — the chart owning JupyterHub, the operator and CVMFS
and the old apps retired — means an explicit **ownership transfer** of the
controller, its RBAC, the CRDs and the storage-driver resources (and, for
`charts/jupyter`, the hub state) **before** any old app is pruned. That
procedure has **not been rehearsed** and is not published. Until it is, run
(b) and do not remove or prune the old apps.

## What neurocloud keeps

These stay exactly as they are — the chart consumes them by name, never installs
them:

- **ArgoCD** itself (the app-of-apps engine).
- **Longhorn** (StorageClass — hub DB + home PVCs via the z2jh keys
  `jupyterhub.hub.db.pvc.storageClassName` /
  `jupyterhub.singleuser.storage.dynamic.storageClass`; `global.storageClassName`
  covers only this chart's own in-house PVCs).
- **Monitoring** — the full kube-prometheus-stack (consumed via
  `infra.monitoring.*`; this chart only emits ServiceMonitors when asked).
- **`config/` + SOPS** — the secrets pipeline (the chart references secrets via
  `existingSecret`; see [secrets.md](secrets.md)).
- In (b), the **`mounts`** and **`security`** apps, as above. cryptnono and the
  DNS filter are part of the `security` app (`charts/security`) and are *not*
  bundled into this chart.

## Sample ArgoCD `Application` (adoption, (b))

ArgoCD **ignores `spec.source` when `spec.sources` is present**
([multiple sources](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)),
so the chart and the values repository are **both** entries in `spec.sources`;
there is no `spec.source`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: neurodesk
  namespace: argocd
spec:
  project: default
  sources:
    # 1. The chart. Its value file comes from source 2 via the `$values` ref.
    - repoURL: ghcr.io/neurodesk/charts
      chart: neurodesk
      targetRevision: 0.3.0           # pin the chart version
      helm:
        releaseName: neurodesk
        valueFiles:
          - $values/overlays/neurocloud-values.yaml   # must exist at source 2's revision
        values: |
          # Per-deployment host only; everything else is in the overlay.
          # Use a host the existing charts/jupyter app does not serve.
          global:
            domain: neurodesk.example.org
          jupyterhub:
            ingress:
              hosts: [neurodesk.example.org]
              tls:
                - secretName: jupyter-tls
                  hosts: [neurodesk.example.org]
          # jupyterhub auth (GitHub), proxy.secretToken, hub.cookieSecret and
          # OAuth client_secret come from SOPS/sealed-secrets, NOT inline here.
    # 2. The values repository (no manifests of its own; referenced as $values).
    - repoURL: https://github.com/neurodesk/neurocloud
      targetRevision: main            # pin a tag or commit for production
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: neurodesk              # NOT the charts/jupyter app's namespace
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

**This sample is runnable only once `overlays/neurocloud-values.yaml` exists in
the values repository at the revision source 2 points to.** Create it there
first (start from
[`examples/neurocloud-values.yaml`](../examples/neurocloud-values.yaml)); until
then the render fails on the missing value file. `prune: true` only affects
objects this Application renders — which in (b) excludes the operator and the
CVMFS driver.

Notes:
- ArgoCD renders the chart with `helm template` but, unlike a raw
  `kubectl apply`, handles Helm hook annotations itself. The chart's pre-delete
  cleanup Job (see [install.md](install.md#teardown--uninstall)) renders in both
  cases: in (b) it is precondition-only (it refuses while user servers run in
  the release namespace, and deletes nothing itself, since this release owns a
  profile but no operator or CVMFS driver); in (a) it also removes what the
  release bundles. It is honoured as a `PreDelete` hook, run when the
  Application is deleted, on Argo CD versions that map `helm.sh/hook:
  pre-delete` to it; older versions do not apply the Job at all, so deleting the
  Application neither checks for running servers nor removes what the hook
  would have. Verify against your Argo CD version.
- For a fresh bundled install (a), `ServerSideApply` + the right sync waves help
  the SPO CRDs land before the AppArmor/Seccomp CRs.
- The overlay sets `infra.monitoring.serviceMonitors=true`; match its
  `serviceMonitorLabels` to what your kube-prometheus-stack selects on.
- Keep secrets out of `values:` — reference SOPS/sealed secrets via
  `existingSecret` in your overlay.
- **PIN z2jh's auto-generated secrets.** Because ArgoCD renders with
  `helm template` (no live cluster state), z2jh regenerates
  `proxy.secretToken`, `hub.cookieSecret`, `CryptKeeper.keys` and
  `services.*.apiToken` on **every** sync — rotating them breaks hub↔proxy auth
  and login cookies on each reconcile. Pin them via `existingSecret` / committed
  values. See the warning in [secrets.md](secrets.md).

See [migration.md](migration.md) for the rollout plan and
[security.md](security.md) for the SPO details.
