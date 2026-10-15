# Components

This chart is an umbrella over five logical components. Each is either a remote
subchart (gated by a `Chart.yaml` `condition:`) or a set of in-house parent
templates (gated by `{{- if .Values.<toggle> }}`). This page covers, per
component: what it deploys, the source it was ported from, its toggle, its
dependencies, and the node/cluster prerequisites.

---

## JupyterHub

**Toggle:** `jupyterhub.enabled` (default `true`)
**Kind:** remote subchart — `jupyterhub` `4.4.2` from
`https://jupyterhub.github.io/helm-chart`
**Ported from:** neurocloud `charts/jupyter` + ais-devstack's JupyterHub install
scripts — both were thin wrappers over upstream Zero-to-JupyterHub (z2jh).

**Deploys:** the full z2jh stack — Hub, configurable-http-proxy (`proxy-public`),
the user scheduler, and per-user singleuser servers. The neurodesk baseline sets
the **neurodesktop** singleuser image, lands users in `/lab`, mounts `/cvmfs` and
`/dev/shm`, claims a FUSE device, applies an AppArmor profile, and culls idle
servers after 3h. Authentication ships as the `dummy` placeholder — override it
in your overlay.

The z2jh **image-pullers are off by default** (`prePuller.hook.enabled` /
`prePuller.continuous.enabled` = `false`): the hook puller otherwise blocks
`helm install` until the multi-GB neurodesktop image is pulled on every node.
Pods pull on first spawn instead; re-enable for pre-warmed nodes. **Always
install with an explicit `--namespace`** — the z2jh image-awaiter Job targets
`default` otherwise.

**Everything under `jupyterhub:` is z2jh passthrough.** Do not template across
this boundary; layer auth/ingress/secrets/overrides with `-f my-values.yaml`.

**Dependencies / prereqs:**
- A StorageClass for the hub DB PVC and per-user home PVCs — set on the **z2jh**
  keys `jupyterhub.hub.db.pvc.storageClassName` and
  `jupyterhub.singleuser.storage.dynamic.storageClass` (`global.storageClassName`
  covers only this chart's in-house PVCs and does **not** reach these).
- To reach the Hub externally: `jupyterhub.ingress.enabled` (z2jh's own Ingress;
  set `ingressClassName`/`hosts`/`tls` and a `cert-manager.io/cluster-issuer`
  annotation for TLS) + an ingress controller, or a
  `kubectl port-forward svc/proxy-public`.
- The default singleuser block assumes **CVMFS on** (`/cvmfs` volume + FUSE) and
  **AppArmor on** (`notebook` profile). If you disable those, edit the
  singleuser block in your overlay to match.

---

## CVMFS access (cvmfs-csi + smarter-device-manager + squid + probe + traceParser)

**Toggle:** `cvmfs.enabled` (default `true`)
**Ported from:** ais-devstack's `cvmfs_mount` step + squid script; neurocloud's
`mounts` ArgoCD app.

This is a cluster of pieces under a single top-level toggle:

### cvmfs-csi (remote subchart)
- **Kind:** remote subchart — `cvmfs-csi` `2.6.0` from
  `oci://registry.cern.ch/kubernetes/charts`. **Condition:** `cvmfs.enabled`.
- **Deploys:** CERN's CVMFS CSI driver and (when
  `cvmfs-csi.automountStorageClass.create=true`) the automount StorageClass that
  the `cvmfs` PVC binds to. Values live under the sibling `cvmfs-csi:` key
  (passthrough); its `extraConfigMaps` are `tpl`'d against `.Values.global.cvmfs.*`
  — Helm injects `global` into the subchart scope, so the server URL
  (`global.cvmfs.server`) and Squid proxy (`global.cvmfs.squidEnabled`) come from
  the **single source of truth** shared with this chart's own squid templates.

### smarter-device-manager (remote subchart)
- **Kind:** remote subchart — `smarter-device-manager` `0.0.10` from
  `https://smarter-project.github.io/smarter-device-manager`.
  **Condition:** `cvmfs.enabled`.
- **Deploys:** a DaemonSet that advertises `/dev/fuse` as the schedulable
  resource `smarter-devices/fuse`, which singleuser pods request so FUSE-based
  CVMFS mounts work without privileged pods.
- **Where it runs:** every Linux node (`smarter-device-manager.nodeSelector`,
  default `kubernetes.io/os: linux`); no node label is needed. It tolerates only
  the `smarter.type=edge` taint. See [cvmfs.md](cvmfs.md).

### `cvmfs` PVC + config wiring (in-house)
- The PVC (`cvmfs.pvc.name`, default `cvmfs`) on the automount StorageClass
  (`cvmfs.pvc.storageClassName`, default `cvmfs`), mounted into singleuser pods
  at `/cvmfs` with `mountPropagation: HostToContainer`.

### Squid cache (in-house)
- **Toggle:** `global.cvmfs.squidEnabled` (default `false`, **single source of
  truth**) — renders only when `cvmfs.enabled` too. **Deploys:** an in-cluster
  Squid HTTP cache + Service fronting the Stratum-1 mirrors. When on,
  `CVMFS_HTTP_PROXY` is set to the Squid service; when off, it's `DIRECT`. The
  keys under `cvmfs.squid` are deploy settings only (no `enabled` flag).

### Health probe (in-house)
- **Toggle:** `cvmfs.probe.enabled` (default `true`). **Deploys:** a per-node
  DaemonSet that checks `/cvmfs` and emits the `cvmfs_mount_healthy` gauge.
  Scraping it needs `infra.monitoring.serviceMonitors` + a Prometheus Operator.
- **Scheduling:** defaults to `cvmfs.probe.nodeSelector: {}` /
  `tolerations: []`, so it runs only where CVMFS is expected. It **no longer
  tolerates all taints** — that previously produced false-positive
  `cvmfs_mount_healthy=0` alerts on control-plane / non-CVMFS nodes. Add
  tolerations/nodeSelector to match your CVMFS node pool.

### Trace-parser (in-house, WIP)
- **Toggle:** `cvmfs.traceParser.enabled` (default **`false`**). **Deploys:** the
  CVMFS trace-parser telemetry stack (ported from devstack). **WIP / fragile:**
  it installs its runtime deps via `apt`/`pip` at container start, so a slow or
  unreachable package index crash-loops the pod. Off by default; its
  ServiceMonitor needs a Prometheus Operator. Leave it off unless actively
  developing the analytics.

**Dependencies / prereqs (whole component):** FUSE-capable Linux nodes that
the device plugin can schedule on (no node label needed); a StorageClass for
the Squid cache PVC (if enabled); a Prometheus Operator if you want
probe/trace-parser metrics.

See [cvmfs.md](cvmfs.md) for the full topology and the "run CVMFS yourself"
path.

---

## Security profiles (AppArmor/Seccomp + SPO)

**Toggle:** `security.enabled` (default `true`) gates the profile CRs;
`security.installOperator` (default `true`) gates the SPO subchart.
**Ported from:** neurocloud's `security` ArgoCD app; ais-devstack's security
step.

**Deploys:**
- **In-house:** an `AppArmorProfile` CR (`security.appArmor.profileName`,
  default `notebook`) and, when `security.seccomp.enabled`, a `SeccompProfile`
  CR (`security.seccomp.profileName`, default `log`). The AppArmor CR is
  referenced by name from the z2jh singleuser `securityContext`. The **seccomp**
  CR is **audit-only** (`defaultAction: SCMP_ACT_LOG` — logs syscalls, enforces
  nothing) and is **NOT auto-attached**: to use it you add
  `seccompProfile {type: Localhost, localhostProfile: operator/log.json}` to
  `jupyterhub.singleuser.extraPodConfig` yourself.
  Both CRs are API `security-profiles-operator.x-k8s.io/v1` and
  **cluster-scoped**, so their names are cluster-unique. They render whenever
  their toggles are on; if the cluster cannot serve them the render fails
  instead of skipping them.
- **Vendored subchart:** upstream kubernetes-sigs `security-profiles-operator`
  `1.0.0` from `vendor/security-profiles-operator`, with local patches recorded
  in its `PROVENANCE.txt` (bundled, ON by default). Provides the
  AppArmorProfile/SeccompProfile CRDs (shipped in its `crds/` dir, so Helm
  installs them before the profile CRs), the operator, its webhook and the node
  DaemonSet (`spod`) that loads the profiles onto nodes. **Condition:**
  `security.installOperator`. It **always runs in namespace
  `security-profiles-operator`** (upstream 1.0.0 hard-codes it), which the
  release creates and keeps on uninstall. Image pinned to
  `registry.k8s.io/security-profiles-operator/security-profiles-operator:v1.0.0`,
  one replica.
- **Optional subchart:** `cert-manager` `v1.21.2` from
  `oci://quay.io/jetstack/charts`. **Condition:** `cert-manager.enabled`
  (default **`false`**). Only for a cluster with no cert-manager.

**Dependencies / prereqs:**
- The bundled SPO needs **cert-manager**: already running in the cluster, or
  installed by this release with `cert-manager.enabled=true`. The render fails
  if neither holds.
- With `installOperator=false` the cluster must already run **SPO ≥ 1.0.0**
  (SPO 0.x, including the neurodesk fork, is not compatible); the render checks
  for its `v1` API (`assumeCrdsPresent=true` skips that check for offline
  renders).
- The singleuser `appArmorProfile.localhostProfile` must match
  `security.appArmor.profileName` (sync caveat).
- With no SPO at all, the profiles must be loaded onto nodes manually — see the
  fallback in [security.md](security.md).

---

## JupyterHub glue (jupyter-glue)

**Toggle:** per-feature under `jupyterGlue.*` (all default `false`).
**Ported from:** neurocloud Hub overlays (home auto-resize, fluent-bit, shared
teaching/group storage).

**Deploys (cluster-side objects only — RBAC + ConfigMaps):**
- `jupyterGlue.homeResize` — RBAC for the Hub to patch nearly-full home PVCs.
  The spawner logic that triggers it ships in the neurocloud overlay; this only
  grants RBAC (`homeResize.rbac`).
- `jupyterGlue.fluentbit` — a fluent-bit logging sidecar ConfigMap mounted into
  singleuser pods.
- `jupyterGlue.sharedTeaching` — RBAC + optional instructor RWX PVCs. Needs a
  pre-existing RWX StorageClass (`sharedTeaching.storageClassName`).
- `jupyterGlue.sharedGroupStorage` — RBAC for the Hub to reconcile per-group RWX
  storage at spawn.

**Dependencies / prereqs:** the *spawner-side* wiring lives in the
`jupyterhub.hub.extraConfig` overlay (see `examples/`). Shared storage needs an
RWX StorageClass; home-resize needs Prometheus.

---

## XNAT integration (optional)

**Toggle:** `xnat.enabled` (default `false`).
**Ported from:** ais-devstack's XNAT-upload extension wiring.

**Deploys (notebook-side only):**
- The JupyterLab XNAT-upload extension ConfigMap (when
  `xnat.uploadExtension.enabled`), installed via an init-container whose
  image the spawner takes from `jupyterhub.hub.extraEnv.XNAT_EXT_INSTALLER_IMAGE`.
- A NetworkPolicy allowing singleuser egress to the XNAT server namespace
  (`xnat.server.namespace`), targeting `xnat.server.host`.

**Not deployed here:** the XNAT **server** itself and its server-side plugins/jars
— those remain in ais-devstack. This component only wires the notebook side to
an external XNAT.

**Dependencies / prereqs:** an external/in-cluster XNAT server reachable at
`xnat.server.host`; pair with the XNAT JupyterHub overlay
(`examples/devstack`). See [xnat.md](xnat.md).
