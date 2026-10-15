# Values reference

Every key in `values.yaml`, grouped by component. `values.yaml` is the single
control surface: for each component it does two jobs — **whether** it deploys
(the `enabled` toggle, wired to a Chart.yaml `condition:` for remote subcharts
or to a `{{- if }}` in this chart's own templates) and **how** it deploys (the
nested config block).

The **"breaks-when-off"** column tells you what stops working — or what you must
also change — when the toggle is false.

> Secrets never belong in `values.yaml`. Placeholder/auth keys below default to
> `""` or `dummy`; supply real values via `existingSecret` / sealed-secrets /
> SOPS. See [secrets.md](secrets.md).

> The chart ships a **`values.schema.json`** that validates this chart's own
> in-house blocks, so a **mistyped toggle fails fast** at `helm template`/install
> (e.g. `cvmfs.enable` instead of `cvmfs.enabled`, or an unknown key under
> `infra`/`security`/`xnat`/`validation`) instead of silently no-op'ing. The
> subchart passthrough keys (`jupyterhub`, `cvmfs-csi`,
> `smarter-device-manager`, `security-profiles-operator`, `cert-manager`) stay
> permissive so the full upstream schemas pass through.

## Top-level

| Key | Default | Description |
| --- | --- | --- |
| `nameOverride` | `""` | Override the chart name used in labels/fullname. |
| `fullnameOverride` | `""` | Override the fully-qualified release name. |

## `global` — shared cluster handles

Names of pre-existing infrastructure the chart references but does not create.

| Key | Default | Description | Breaks-when-off / empty |
| --- | --- | --- | --- |
| `global.domain` | `""` | External hostname for the Hub ingress (e.g. `neurodesk.example.org`). Set the actual Ingress host on `jupyterhub.ingress.hosts`. | Ingress host is empty; the NOTES "Hub URL" falls back to a port-forward hint. |
| `global.storageClassName` | `""` | StorageClass for **this chart's OWN in-house PVCs** only (e.g. the Squid cache). `""` => cluster default. **Does NOT control the hub DB or singleuser home PVCs** — those belong to the z2jh subchart and Helm cannot template a subchart's values from here. Set them directly on `jupyterhub.hub.db.pvc.storageClassName` and `jupyterhub.singleuser.storage.dynamic.storageClass`. The `validation.storageClassNotBridged` guard fails the render if this is set but those z2jh keys are empty. | This chart's in-house PVCs (Squid cache) stay `Pending` if no default StorageClass exists. |
| `global.cvmfs.server` | Neurodesk Stratum-1 URLs (`@fqrn@` expanded per repo) | **Single source of truth** for the Stratum-1 mirror URL(s), `;`-separated. Lives under `global` so this chart's squid templates **and** the cvmfs-csi subchart's tpl'd ConfigMaps read the same value (Helm injects `global` into subchart scope). | n/a |
| `global.cvmfs.squidEnabled` | `false` | **Single toggle** for the in-cluster Squid HTTP cache — gates both the squid Deployment (this chart) and the cvmfs-csi proxy config (subchart). Replaces the old `cvmfs.squid.enabled` / `cvmfs-csi.squid.enabled` double-toggle. | When off, `CVMFS_HTTP_PROXY=DIRECT` (pods hit mirrors directly). |

## `infra` — referenced infrastructure

The `infra:` block now contains **only `monitoring`**. (Ingress/TLS is configured
on z2jh's own `jupyterhub.ingress.*` — see the `jupyterhub` section below.)

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `infra.monitoring.serviceMonitors` | `false` | Emit ServiceMonitors/dashboards for an **existing** Prometheus Operator. | Probe/trace-parser metrics aren't scraped. Leave false unless the `monitoring.coreos.com` CRDs are present. |
| `infra.monitoring.serviceMonitorLabels` | `{}` | Label your Prometheus selects ServiceMonitors by (the release label of your kube-prometheus-stack). | Without the matching label, Prometheus ignores the ServiceMonitors. |

## `namespace` — namespace + Pod Security

The chart installs into the Helm release namespace (`-n` / `--create-namespace`).
This block optionally stamps a Namespace object and PodSecurity labels.

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `namespace.create` | `false` | Render a `Namespace` object. Use with care under `--create-namespace`. | No Namespace object is rendered (rely on `--create-namespace`). |
| `namespace.name` | `""` | Namespace name. `""` => the release namespace. | n/a — `neurodesk.namespace` falls back to `.Release.Namespace`. |
| `namespace.podSecurityLabels` | `{}` | PodSecurity labels, e.g. `{ pod-security.kubernetes.io/enforce: privileged }`. **Not `baseline` or `restricted` while `cvmfs.enabled`**: the cvmfs-csi node plugin is privileged and smarter-device-manager uses `hostNetwork`, both in the release namespace, so a stricter level rejects them. | No PodSecurity labels applied. Only effective when `namespace.create=true`. |

## `jupyterhub` — JupyterHub (z2jh passthrough)

Toggle: **`jupyterhub.enabled`** (Chart.yaml `condition: jupyterhub.enabled`).
Everything under `jupyterhub:` is the upstream **Zero-to-JupyterHub** values
tree, passed through unchanged. The defaults are the neurodesk-COMMON baseline;
layer auth/ingress/secrets with `-f my-values.yaml`. The keys below are the
shipped defaults — z2jh accepts the full z2jh schema here.

| Key | Default | Description |
| --- | --- | --- |
| `jupyterhub.enabled` | `true` | Install the JupyterHub subchart. Off => no Hub (the rest of the chart can still install). |
| `jupyterhub.singleuser.defaultUrl` | `/lab` | Land users in JupyterLab. |
| `jupyterhub.singleuser.startTimeout` | `600` | Seconds a spawn may take before it fails. The first spawn on a node pulls the ~2.6 GB image (pre-pullers are off by default). |
| `jupyterhub.singleuser.image.name` | `ghcr.io/neurodesk/neurodesktop` | The neurodesktop singleuser image. (The old path `ghcr.io/neurodesk/neurodesktop/neurodesktop` stopped receiving tags after 2026-06-09.) |
| `jupyterhub.singleuser.image.tag` | `2026-09-23@sha256:0eddaf36b1d39daacc821796e915bdcbc4ac8c507f3bd068520bafefc4f6e549` | Image tag, digest-pinned because dated tags can be re-pushed upstream. The date part is tracked by `Chart.yaml` `appVersion`. |
| `jupyterhub.singleuser.image.pullPolicy` | `IfNotPresent` | Image pull policy. |
| `jupyterhub.singleuser.extraResource.limits["smarter-devices/fuse"]` | `"1"` | FUSE device claimed from smarter-device-manager. **Tied to CVMFS** — remove in your overlay if `cvmfs.enabled=false`. |
| `jupyterhub.singleuser.extraResource.guarantees["smarter-devices/fuse"]` | `"1"` | FUSE device guarantee. Same CVMFS coupling. |
| `jupyterhub.singleuser.storage.capacity` | `50Gi` | Per-user home PVC size. |
| `jupyterhub.singleuser.storage.dynamic.storageClass` | (unset) | **The REAL knob for the per-user home PVCs** (`global.storageClassName` does NOT reach them). Unset => z2jh uses the cluster default. |
| `jupyterhub.singleuser.storage.extraVolumes` | `cvmfs` PVC + `shm-volume` (Memory `emptyDir`) | `/cvmfs` PVC mount and `/dev/shm`. The `cvmfs` volume is **tied to CVMFS**. |
| `jupyterhub.singleuser.storage.extraVolumeMounts` | `/cvmfs` (`HostToContainer`) + `/dev/shm` | Mount points for the volumes above. |
| `jupyterhub.singleuser.extraPodConfig.securityContext.fsGroup` | `100` | Restated because setting `extraPodConfig.securityContext` **replaces** z2jh's own pod securityContext (which derives `fsGroup` from `singleuser.fsGid`). Without it the home PVC stays root-owned and the notebook (uid 1000) cannot write `/home/jovyan`. |
| `jupyterhub.singleuser.extraPodConfig.securityContext.fsGroupChangePolicy` | `OnRootMismatch` | Avoids re-chowning large home volumes on every spawn. |
| `jupyterhub.singleuser.extraPodConfig.securityContext.appArmorProfile` | `Localhost` / `notebook` | Attaches the AppArmor profile **by name** — must match `security.appArmor.profileName`. See the sync caveat in [security.md](security.md). |
| `jupyterhub.proxy.service.type` | `ClusterIP` | Proxy service type (front it with your own ingress). |
| `jupyterhub.hub.consecutiveFailureLimit` | `0` | Never restart the Hub after consecutive spawn failures (z2jh's default 5 turns a slow image pull into a misleading Hub `CrashLoopBackOff`). |
| `jupyterhub.hub.config.JupyterHub.authenticator_class` | `dummy` | **Placeholder** — override with GitHub/generic-OAuth/OIDC in your overlay. Never commit client secrets. |
| `jupyterhub.hub.config.Authenticator.admin_users` | `[]` | Admin user list — set in your overlay. |
| `jupyterhub.hub.config.KubeSpawner.http_timeout` | `120` | Seconds the Hub waits for a started server to answer HTTP. |
| `jupyterhub.hub.db.pvc.storageClassName` | (unset) | **The REAL knob for the hub state DB PVC** (`global.storageClassName` does NOT reach it). Unset => cluster default StorageClass. **Never set `""`**: z2jh renders any string verbatim, and an empty `storageClassName` means "no StorageClass", so on a cluster that relies on its default class the `hub-db-dir` PVC never binds and the Hub stays `Pending`. 0.1.x shipped `""` here (fixed in 0.2.0). **Exception:** a release upgraded in place from 0.1.x whose `hub-db-dir` PVC was created with `""` must keep `""` here for the upgrade, because Kubernetes rejects changing a PVC's `storageClassName` — see [migration.md](migration.md#01x---020). |
| `jupyterhub.cull.enabled` | `true` | Cull idle singleuser servers. |
| `jupyterhub.cull.timeout` | `10800` | Idle timeout (seconds) — 3h. |
| `jupyterhub.ingress.enabled` | `false` | z2jh-managed Ingress for the Hub. **This is the Ingress/TLS control surface** (the chart adds no separate Ingress). Set `true` to expose the Hub externally. |
| `jupyterhub.ingress.ingressClassName` | `""` | IngressClass of your existing controller (e.g. `nginx`). |
| `jupyterhub.ingress.annotations` | `{}` | Ingress annotations, e.g. `cert-manager.io/cluster-issuer: <issuer>` for TLS, or `nginx.ingress.kubernetes.io/*` tuning. |
| `jupyterhub.ingress.hosts` | `[]` | Hostnames the Ingress answers on (set to your `global.domain`). |
| `jupyterhub.ingress.tls` | `[]` | TLS blocks, e.g. `[{secretName: jupyter-tls, hosts: [<domain>]}]`. |
| `jupyterhub.prePuller.hook.enabled` | `false` | z2jh **pre-install** hook image-puller. **Off by default** — it otherwise blocks `helm install` until the multi-GB neurodesktop image is pulled on every node (minutes of stall, or a rollback on slow/airgapped registries). Pods pull on first spawn instead. Re-enable for pre-warmed nodes. |
| `jupyterhub.prePuller.continuous.enabled` | `false` | z2jh continuous image-puller DaemonSet. Off by default for the same reason. |

> **Do not template across the subchart boundary.** The singleuser CVMFS volumes
> and AppArmor reference are part of this z2jh block and cannot be auto-toggled
> from `cvmfs.*` / `security.*`. Keep them in sync via your overlay — see
> [architecture.md](architecture.md) and [disabling-components.md](disabling-components.md).

> **Install with an explicit `--namespace`.** The z2jh `hook-image-awaiter` Job
> targets the `default` namespace when none is given, so always pass
> `--namespace <ns> --create-namespace` (the in-house templates also resolve the
> deploy namespace from the release namespace).

## `cvmfs` — CVMFS access (in-house)

Toggle: **`cvmfs.enabled`** (also the `condition:` for the `cvmfs-csi` and
`smarter-device-manager` subcharts).

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `cvmfs.enabled` | `true` | Install CVMFS access (subcharts + `cvmfs` PVC + wiring). | No `/cvmfs`. Also drop the `cvmfs` volume + FUSE request from `jupyterhub.singleuser` in your overlay (see [disabling-components.md](disabling-components.md)). |
| `cvmfs.repositories` | `[neurodesk.ardc.edu.au]` | Repositories exposed under `/cvmfs`. | n/a |
| `cvmfs.pvc.name` | `cvmfs` | Name of the PVC mounted into singleuser pods. Must match the `claimName` in the z2jh `extraVolumes`. | n/a |
| `cvmfs.pvc.storageClassName` | `cvmfs` | The automount StorageClass created by cvmfs-csi. | If `cvmfs-csi.automountStorageClass.create=false`, this SC won't exist. |

> The Stratum-1 server URL and the Squid on/off toggle now live under
> **`global.cvmfs.server`** / **`global.cvmfs.squidEnabled`** (single source of
> truth shared with the cvmfs-csi subchart) — see the `global` table above.

### `cvmfs.squid` — in-cluster Squid HTTP cache (deploy settings)

The **toggle** is `global.cvmfs.squidEnabled` (single source of truth); the keys
below are deploy settings only and carry **no** `enabled` flag. Squid renders
when `cvmfs.enabled` **and** `global.cvmfs.squidEnabled` are true. When on,
`CVMFS_HTTP_PROXY` is pointed at the Squid service; when off, it is `DIRECT`.

| Key | Default | Description |
| --- | --- | --- |
| `cvmfs.squid.image` | `ubuntu/squid:6.6-24.04_edge@sha256:8a3baed477e2c282ab8aa5edad442f69873246964f225c5c2ae8364b6610963c` | Squid container image (Squid 6.14 on Ubuntu 24.04, digest-pinned). |
| `cvmfs.squid.storageClassName` | `""` | Cache PVC SC. `""` => `global.storageClassName` / cluster default (via `neurodesk.storageClass`). |
| `cvmfs.squid.cacheSize` | `60Gi` | Cache PVC size. |
| `cvmfs.squid.cacheDirSizeMB` | `50000` | Squid `cache_dir` size (MB). |
| `cvmfs.squid.cacheMemMB` | `256` | In-memory cache (MB). |
| `cvmfs.squid.maxFileDescriptors` | `65536` | squid.conf `max_filedescriptors`. Without a cap squid sizes its descriptor table from the container's NOFILE limit and exits right after start-up where that limit is huge (1073741816 under kind on GitHub runners; reproduced). |
| `cvmfs.squid.maxObjectSizeMB` | `1024` | Max cacheable object size (MB). |
| `cvmfs.squid.clientCidrs` | `[10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]` | CIDRs allowed to use the proxy; must cover the pod network. Default: all private ranges (Squid is ClusterIP-only). Squid answers `403` to other clients and CVMFS silently falls back to `DIRECT`, uncached — which is what 0.1.x's k3s-only default (`10.42.0.0/16`, `10.43.0.0/16`) did on k0s and kubeadm clusters. |
| `cvmfs.squid.resources` | `requests {1Gi,200m}` / `limits {2Gi,1}` | Squid pod resources. The cache index costs ~10 MB per GB of `cache_dir` (50000 MB => ~500 MB) on top of `cacheMemMB`; an OOM loop takes the single proxy offline. Scale the memory limit with `cacheDirSizeMB`. |
| `cvmfs.squid.nodeSelector` | `{}` | Pin Squid (RWO cache volume) to suitable nodes, e.g. off autoscaled/drainable ones. |
| `cvmfs.squid.tolerations` | `[]` | Tolerations for the Squid pod. |

### `cvmfs.probe` — per-node CVMFS health probe

Renders when `cvmfs.enabled` and `cvmfs.probe.enabled`.

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `cvmfs.probe.enabled` | `true` | DaemonSet that checks `/cvmfs` per node and emits `cvmfs_mount_healthy`. | No CVMFS health metric. |
| `cvmfs.probe.image` | `python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01` | Probe image. | n/a |
| `cvmfs.probe.intervalSeconds` | `30` | Check interval. | n/a |
| `cvmfs.probe.nodeSelector` | `{}` | Schedule the probe only where CVMFS is expected. | n/a |
| `cvmfs.probe.tolerations` | `[]` | Tolerations for the probe DaemonSet. **No longer tolerates all taints** (was a blanket toleration before) — this fixes false-positive `cvmfs_mount_healthy=0` alerts on control-plane / non-CVMFS nodes. Add tolerations to match your CVMFS node pool's taints. | n/a |

> Scraping the probe metric needs `infra.monitoring.serviceMonitors=true` and a
> Prometheus Operator.

### `cvmfs.traceParser` — trace-parser telemetry (WIP)

Renders when `cvmfs.enabled` and `cvmfs.traceParser.enabled`.

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `cvmfs.traceParser.enabled` | `false` | CVMFS trace-parser telemetry stack (analytics; ported from devstack). | No trace-parser telemetry. |
| `cvmfs.traceParser.image` | `python:3.14-slim@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d` | Parser image. | n/a |
| `cvmfs.traceParser.replicas` | `1` | Parser replicas. | n/a |
| `cvmfs.traceParser.kubectlVersion` | `v1.35.9` | kubectl downloaded (sha256-verified, amd64/arm64) at container start. Keep within ±1 minor of your apiserver. | n/a |
| `cvmfs.traceParser.requestsVersion` | `2.34.2` | `requests` version pip-installed at container start. | n/a |

> Its ServiceMonitor needs a Prometheus Operator (`infra.monitoring`).

## `cvmfs-csi` — CERN cvmfs-csi subchart (passthrough)

Toggle: `cvmfs.enabled` (subchart `condition:`). Values under this **sibling**
key are passed to the CERN subchart verbatim.

| Key | Default | Description |
| --- | --- | --- |
| `cvmfs-csi.automountStorageClass.create` | `true` | Create the automount StorageClass (the `cvmfs.pvc.storageClassName`). |
| `cvmfs-csi.cache.local.cvmfsQuotaLimit` | `40000` | Local CVMFS cache quota. |
| `cvmfs-csi.cache.local.location` | `/cvmfs-localcache` | Local cache path on nodes. |
| `cvmfs-csi.automountDaemonUnmountTimeout` | `0` | Never auto-unmount idle mounts. |

> The server URL + Squid proxy wiring are templated into the cvmfs-csi
> `extraConfigMaps` by this chart's helpers at build time. Operators who disable
> CVMFS here and install cvmfs-csi standalone supply their own config under this
> key.

## `smarter-device-manager` — subchart (passthrough)

Toggle: `cvmfs.enabled` (subchart `condition:`). Exposes `/dev/fuse` to pods.

| Key | Default | Description |
| --- | --- | --- |
| `smarter-device-manager.nodeSelector` | `{kubernetes.io/os: linux}` | Nodes the FUSE device plugin runs on: every Linux node, no label needed. An empty selector makes the upstream chart fall back to a hard-coded `smarter-device-manager: enabled` selector (the label 0.1.x required). Keys you set in an overlay are **merged** with the default, so a node must match both; do not null the default key (the `null` survives into the rendered selector). The plugin tolerates only the `smarter.type=edge` taint (hard-coded upstream). |
| `smarter-device-manager.config[0].devicematch` | `^fuse$` | Match the FUSE device. |
| `smarter-device-manager.config[0].nummaxdevices` | `150` | Max FUSE allocations per node. |

> Notebooks request `smarter-devices/fuse`, so they can only be scheduled on
> nodes where the plugin runs. See [cvmfs.md](cvmfs.md).

## `security` — security profiles (in-house + SPO subchart)

Toggle: **`security.enabled`** gates the in-house profile CRs;
**`security.installOperator`** is the `condition:` for the SPO subchart.

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `security.enabled` | `true` | Render the AppArmor/Seccomp profile CRs. | No profile CRs; the singleuser AppArmor reference points at a non-existent profile (spawn may fail). Does **not** remove the operator: that is `installOperator`. |
| `security.installOperator` | `true` | Bundle + install the Security Profiles Operator: upstream `1.0.0`, vendored. It always runs in namespace `security-profiles-operator`. Needs cert-manager (pre-installed, or `cert-manager.enabled=true`; guard 5c). Set false only when the cluster already runs **SPO ≥ 1.0.0** (SPO 0.x, including the neurodesk fork, is not compatible). | The cluster must serve the SPO `v1` API, or the render fails (guard 5b). Nothing loads the profiles onto nodes unless that SPO runs. See [security.md](security.md). |
| `security.assumeCrdsPresent` | `false` | **Only consulted when `installOperator=false`.** Skips the API discovery check (guard 5b) when rendering offline (plain `helm template`), asserting SPO ≥ 1.0.0 is installed. Equivalent: `--api-versions security-profiles-operator.x-k8s.io/v1/AppArmorProfile`. It does not change what renders. | n/a |
| `security.appArmor.enabled` | `true` | Render the AppArmorProfile CR (API `v1`, cluster-scoped) whenever `security.enabled`. | No AppArmor profile. |
| `security.appArmor.profileName` | `notebook` | CR name and kernel profile name — **must match** `jupyterhub.singleuser.extraPodConfig…appArmorProfile.localhostProfile`. **Cluster-unique**: a second release on the same cluster must pick another name in both places. | Mismatch => pods reference a missing profile. |
| `security.seccomp.enabled` | `false` | Render the SeccompProfile CR. **Audit-only**: even when enabled the profile is `defaultAction: SCMP_ACT_LOG` (logs syscalls, enforces nothing) **and is NOT auto-attached** to the singleuser pod. To use it, add `seccompProfile {type: Localhost, localhostProfile: operator/log.json}` to `jupyterhub.singleuser.extraPodConfig` yourself. | No seccomp profile CR. |
| `security.seccomp.profileName` | `log` | Seccomp profile name (feeds the `operator/<name>.json` path you attach manually; no namespace segment, the CR is cluster-scoped). Cluster-unique. | n/a |

### `security-profiles-operator` — SPO subchart (passthrough)

Toggle: `security.installOperator` (subchart `condition:`). Upstream
kubernetes-sigs SPO `1.0.0`, vendored at `vendor/security-profiles-operator` with
the local patches listed in its `PROVENANCE.txt`; values passed through
verbatim. The keys below are the ones this chart sets; any other upstream key is
accepted.

| Key | Default | Description |
| --- | --- | --- |
| `security-profiles-operator.spoImage.registry` | `registry.k8s.io` | Operator image registry. |
| `security-profiles-operator.spoImage.repository` | `security-profiles-operator/security-profiles-operator` | Operator image repository. |
| `security-profiles-operator.spoImage.tag` | `v1.0.0` | Pinned release tag (upstream's chart defaults to a moving staging `latest`; `registry.k8s.io` promoted tags are immutable). |
| `security-profiles-operator.replicaCount` | `1` | Operator replicas (upstream default 3, leader-elected). Raise for operator HA. |
| `security-profiles-operator.podSecurityContext` | `{seccompProfile: {type: RuntimeDefault}}` | Operator pod securityContext (upstream sets none). |
| `security-profiles-operator.enableAppArmor` | `true` | **Must stay true** or the spod daemon won't load the AppArmorProfile CR and the kubelet rejects every notebook (profile not found). |
| `security-profiles-operator.enableSelinux` | `false` | SELinux profile support (unused here). |
| `security-profiles-operator.enableLogEnricher` | `false` | Log enricher (unused here). |
| `security-profiles-operator.operatorNamespace.create` | `true` | Create namespace `security-profiles-operator` (PSA `enforce: privileged`, kept on uninstall). Set false when that namespace is managed outside this release. The operator runs there either way. |

## `cert-manager` — cert-manager subchart (passthrough)

Toggle: **`cert-manager.enabled`** (Chart.yaml `condition:`), remote subchart
`cert-manager` `v1.21.2` from `oci://quay.io/jetstack/charts`. SPO needs
cert-manager; this installs it **with this release**, for a cluster that has
none. Values under this key are passed to the cert-manager chart verbatim.

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `cert-manager.enabled` | `false` | Install cert-manager in this release (into the release namespace). The release then owns it. **Only on a cluster with NO cert-manager**: it is a cluster singleton, and the chart never adopts an existing install. | With `security.installOperator=true` the cluster must already serve `cert-manager.io/v1` `Certificate`, or the render fails (guard 5c). |
| `cert-manager.crds.enabled` | `true` | Install the cert-manager CRDs with the chart. | n/a |
| `cert-manager.crds.keep` | `true` | Keep the cert-manager CRDs (and so every Certificate in the cluster) on `helm uninstall`. | n/a |

## `jupyterGlue` — JupyterHub glue (in-house)

These provision the **cluster-side** objects (RBAC + ConfigMaps). The
spawner-side wiring lives in the `jupyterhub.hub.extraConfig` overlay.

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `jupyterGlue.homeResize.enabled` | `false` | Auto-grow nearly-full home PVCs (reads Prometheus; spawner logic ships in the neurocloud overlay). | No auto-resize. |
| `jupyterGlue.homeResize.rbac` | `true` | Grant the Hub the RBAC to patch PVCs. | The Hub can't resize PVCs even if the spawner logic runs. |
| `jupyterGlue.fluentbit.enabled` | `false` | Fluent-bit logging sidecar ConfigMap mounted into singleuser pods. | No log-forwarding ConfigMap. |
| `jupyterGlue.sharedTeaching.enabled` | `false` | Shared teaching directories (instructor RWX PVCs) + RBAC. | No shared-teaching objects. |
| `jupyterGlue.sharedTeaching.storageClassName` | `""` | RWX StorageClass for teaching PVCs (must pre-exist). | If empty/absent, teaching PVCs stay `Pending`. |
| `jupyterGlue.sharedGroupStorage.enabled` | `false` | Per-group shared RWX storage reconciled by the Hub at spawn. | No per-group storage. |
| `jupyterGlue.sharedGroupStorage.rbac` | `true` | Grant the Hub the RBAC to reconcile group PVCs. | The Hub can't create/patch group PVCs. |

## `xnat` — optional XNAT integration (in-house)

Toggle: **`xnat.enabled`**. The chart never deploys or configures XNAT itself;
under the AIS umbrella XNAT is in the same release. See [xnat.md](xnat.md).

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `xnat.enabled` | `false` | Provision the in-cluster XNAT integration objects. | No XNAT extension ConfigMap / NetworkPolicy. |
| `xnat.server.host` | `""` | In-cluster host of XNAT. `""` = `<release>-xnat-web`, the AIS xnat chart's Service in the same release. | n/a |
| `xnat.server.namespace` | `""` | XNAT's namespace when it is not the release namespace (NetworkPolicies then allow that namespace). `""` = same namespace: policies select `xnat.server.podLabels` on `xnat.server.port`. | n/a |
| `xnat.server.podLabels` | `app.kubernetes.io/name: xnat-web` | Labels of XNAT's pods (same-namespace NetworkPolicies). | n/a |
| `xnat.server.port` | `8080` | XNAT's container port (same-namespace NetworkPolicies). | n/a |
| `xnat.jupyterhub.enabled` | `false` | Servers launched from XNAT: pre-spawn hook, Role on the credentials Secret, hub<->XNAT NetworkPolicy, named servers on. Only takes effect with `xnat.enabled`. | XNAT-launched servers get the chart defaults, no XNAT data. |
| `xnat.jupyterhub.url` | `""` | XNAT base URL for the hook. `""` = `http://<xnat.server.host>`. | n/a |
| `xnat.jupyterhub.credentialsSecret` | `""` | Secret with the XNAT account the hook uses (`usernameKey`/`passwordKey`, default `username`/`password`). `""` = `<release>-xnat-web-admin`. | Spawns fail (or use defaults with `failOpen`). |
| `xnat.jupyterhub.archivePvc` | `""` | PVC with XNAT's archive, in the release namespace. `""` = `<release>-xnat-web-archive`. | No XNAT data in notebooks. |
| `xnat.jupyterhub.archiveMountPath` | `/data/xnat/archive` | XNAT's path of that PVC; launch mounts under it become read-only subPaths, others are refused. | n/a |
| `xnat.jupyterhub.archiveGid` | `65534` | Supplemental group for pods with XNAT data (XNAT writes its archive 0750/0640 as 65534:65534). | Data mounted but unreadable. |
| `xnat.jupyterhub.uid` / `gid` | `1000` / `100` | `NB_UID`/`NB_GID` for non-Neurodesk XNAT images. | n/a |
| `xnat.jupyterhub.requestTimeoutSeconds` | `10` | Timeout of the call to XNAT at spawn. | n/a |
| `xnat.jupyterhub.failOpen` | `false` | XNAT unreachable or erroring: `false` fails the spawn, `true` spawns the chart defaults. A 404 always spawns the defaults. | n/a |
| `xnat.uploadExtension.enabled` | `true` | Install the JupyterLab XNAT-upload extension ConfigMap. | No upload extension. (Only relevant when `xnat.enabled`.) |
| `xnat.uploadExtension.installerImage` | *(removed in 0.2.0)* | Setting it fails the render: in 0.1.x it reached no manifest. Set `jupyterhub.hub.extraEnv.XNAT_EXT_INSTALLER_IMAGE` instead (Python minor must match the neurodesktop image's, 3.13). | n/a |

## `auth` — login presets

| Key | Default | Description |
| --- | --- | --- |
| `auth.aaf.enabled` | `false` | AAF OpenID Connect login (sets `JupyterHub.authenticator_class`). Client secret: Secret `neurodesk-aaf`, key `client-secret`. |
| `auth.aaf.clientId` | `""` | AAF client id (required when enabled). |
| `auth.aaf.callbackUrl` | `""` | `https://<hub host>/hub/oauth_callback`, including `hub.baseUrl` (required when enabled). |
| `auth.aaf.usernamePrefix` | `aaf_` | Prefix of hub usernames. |
| `auth.aaf.usernameClaim` | `sub` | OIDC claim after the prefix. Prefix + claim must equal the XNAT username (see [xnat.md](xnat.md#aaf-login)). |
| `auth.aaf.allowAll` | `true` | Any AAF user may log in. `false`: only users you allow (e.g. `jupyterhub.hub.config.AAFOAuthenticator.allowed_users`); oauthenticator admits nobody without an allow rule. |
| `auth.aaf.issuer` | `https://central.aaf.edu.au` | AAF base URL (`https://central.test.aaf.edu.au` for the test federation). |

## `validation` — render-time consistency guards

`templates/validate.yaml` fails the render (with `fail`) when a parent toggle and
the z2jh singleuser block disagree — the desync plain Helm cannot prevent
automatically — or when the cluster lacks what the security profiles need.
**Every flag defaults to `false`, which means the guard is ACTIVE.** Set a flag
to `true` only to **deliberately bypass** that one check. See
[disabling-components.md](disabling-components.md). (`helm lint` reports a
failing guard only as `[INFO] Fail: …`; `helm template` / `install` / `upgrade`
enforce it.)

| Key | Default | Guard (active when `false`) |
| --- | --- | --- |
| `validation.storageClassNotBridged` | `false` | Fails if `global.storageClassName` is set but the z2jh hub-DB / home StorageClass keys (`jupyterhub.hub.db.pvc.storageClassName`, `jupyterhub.singleuser.storage.dynamic.storageClass`) are empty — catching the "I set the SC but my PVCs landed on the default" mistake. |
| `validation.fuseResourceWhenCvmfsOff` | `false` | Fails if `cvmfs.enabled=false` but singleuser still requests `smarter-devices/fuse`. |
| `validation.cvmfsVolumeWhenCvmfsOff` | `false` | Fails if `cvmfs.enabled=false` but singleuser still mounts the `cvmfs` PVC. |
| `validation.apparmorAttachWithoutProfile` | `false` | Fails if the pod pins an AppArmor profile but `security.appArmor` is off. |
| `validation.apparmorNameMismatch` | `false` | Fails if the pod's `localhostProfile` != `security.appArmor.profileName`. |
| `validation.certManagerMissing` | `false` | Fails if `security.installOperator=true`, `cert-manager.enabled=false` and the cluster does not serve `cert-manager.io/v1` `Certificate` (guard 5c). Offline, assert it with `--api-versions cert-manager.io/v1/Certificate` instead of bypassing. |
| `validation.apparmorNoCrdProvider` | *(removed)* | **No effect since 0.2.0.** Its guard was removed: the profile CRs now always render when enabled, and guard 5b checks for SPO instead. Still accepted so existing overlays validate. |

Four guards have **no** bypass flag: 5a (the cluster serves only the legacy
pre-1.0 SPO API while `installOperator=true`; see
[migration.md](migration.md#01x---020)), 5b (`installOperator=false` but the
cluster does not serve the SPO `v1` kinds; assert with `--api-versions` or
`security.assumeCrdsPresent=true` when rendering offline), 6 (the removed
`xnat.uploadExtension.installerImage` key is set) and 7 (`auth.aaf.enabled`
without `clientId` and `callbackUrl`). See
[security.md](security.md#how-the-chart-checks-for-spo).

## `uninstallCleanup` — pre-delete cleanup hook

A `pre-delete` hook Job (`templates/uninstall-cleanup-hook.yaml`) that makes
`helm uninstall` clean. Before Helm deletes anything it removes, while the
bundled SPO daemon and cvmfs-csi driver still run, this release's profiles, its
CVMFS probe and PVCs, and the objects the operator created at runtime. A
read-only check Job runs first and refuses while any user server exists **in
the release namespace** (not a cluster-wide check); the uninstall then stops
before changing anything.
Renders when `enabled` and the release owns a profile, manages CVMFS or bundles
the operator; the deletion steps render only for what the release bundles, so
with an external operator and external CVMFS the hook is precondition-only. It covers
`helm uninstall` only (not a `helm upgrade` that turns the operator or CVMFS
off), and a raw `helm template | kubectl apply` install must be rendered with
`--no-hooks`. See [install.md](install.md#teardown--uninstall).

| Key | Default | Description | Breaks-when-off |
| --- | --- | --- | --- |
| `uninstallCleanup.enabled` | `true` | Render the hook. | `helm uninstall` hangs and strands the AppArmorProfile (`Terminating`), the `cvmfs-probe` pod and PVC, and the operator's runtime webhook Deployment, Services, cert-manager objects and `spo-validating-webhook-configuration`. Nothing stops an uninstall while notebooks run. (`helm uninstall --no-hooks` has the same effect for one uninstall.) |
| `uninstallCleanup.image` | `registry.k8s.io/kubectl:v1.35.9@sha256:436cbaa8…` | kubectl image for every step (digest-pinned; minor matching the tested clusters). | n/a |
| `uninstallCleanup.timeoutSeconds` | `120` | Wait per step; it only matters when a step fails or hangs. `helm uninstall --timeout` (default 5m) covers the **whole** hook Job, so pass a larger `--timeout` if a step is expected to be slow. | n/a |
| `uninstallCleanup.resources` | `requests {10m, 32Mi}` / `limits {memory 128Mi}` | Resources per step container. | n/a |

## `extraManifests` — escape hatch

| Key | Default | Description |
| --- | --- | --- |
| `extraManifests` | `[]` | Arbitrary user-supplied manifests rendered as-is (string items are run through `tpl`). Keeps ad-hoc resources inside the Helm release instead of out-of-band `kubectl apply`. |
