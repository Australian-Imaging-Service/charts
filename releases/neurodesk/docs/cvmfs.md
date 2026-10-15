# CVMFS access

CVMFS (the CernVM File System) is how Neurodesk delivers its large, read-only
tool tree to notebook pods at `/cvmfs`. The chart wires up everything needed to
mount it without privileged pods. All of it sits under one top-level toggle,
**`cvmfs.enabled`** (default `true`).

## Single source of truth: `global.cvmfs`

The Stratum-1 server URL and the Squid on/off switch live under **`global.cvmfs`**
on purpose. Helm injects the `global:` block into **every** subchart's scope, so
this chart's own squid templates and the cvmfs-csi subchart's tpl'd ConfigMaps
read the **same** two values. Set them once; there is no per-subchart duplicate
and no double-toggle to keep in sync.

```yaml
global:
  cvmfs:
    server: "http://cvmfs-jetstream.neurodesk.org/cvmfs/@fqrn@;..."  # Stratum-1 URLs
    squidEnabled: false   # ONE toggle: squid Deployment (this chart) + cvmfs-csi proxy
```

`global.cvmfs.squidEnabled` is the single switch for Squid. The cvmfs-csi
ConfigMap reads it to decide `CVMFS_HTTP_PROXY`, and this chart's squid templates
read it to decide whether to render the Squid Deployment/Service. The old
`cvmfs.squid.enabled` / `cvmfs-csi.squid.enabled` double-toggle is **gone**.

## Topology

```
singleuser pod  ──/cvmfs──►  PVC "cvmfs"  ──►  StorageClass "cvmfs" (automount)
   │  requests smarter-devices/fuse                       │
   │                                                      ▼
   ▼                                            cvmfs-csi driver (CERN)
smarter-device-manager                                    │
 (advertises /dev/fuse)                                   ▼
                                      Stratum-1 mirrors (global.cvmfs.server)
                                                  ▲
                          optional Squid cache (global.cvmfs.squidEnabled)
```

## The moving parts

### 1. cvmfs-csi (remote subchart)

CERN's CSI driver mounts CVMFS repositories on demand. Values live under the
**sibling** `cvmfs-csi:` key (passthrough), not under `cvmfs:`:

```yaml
cvmfs-csi:
  automountStorageClass:
    create: true                # creates the "cvmfs" automount StorageClass
  cache:
    local:
      cvmfsQuotaLimit: 40000
      location: /cvmfs-localcache
  automountDaemonUnmountTimeout: 0   # never auto-unmount
```

The Stratum-1 server URL (`global.cvmfs.server`) and the Squid proxy setting
(`global.cvmfs.squidEnabled`) are read directly by the cvmfs-csi
`extraConfigMaps`, which are `tpl`'d by the subchart against `.Values.global.*`
(Helm injects `global` into the subchart scope). `CVMFS_HTTP_PROXY` is resolved
inline in the ConfigMap: the in-cluster Squid service when
`global.cvmfs.squidEnabled`, else `DIRECT`. The repository list
(`cvmfs.repositories`) is what this chart's PVC/automount exposes under `/cvmfs`.

### 2. smarter-device-manager (remote subchart): the FUSE device

CVMFS uses FUSE. Rather than run privileged pods, the chart exposes `/dev/fuse`
as a schedulable resource via smarter-device-manager:

```yaml
smarter-device-manager:
  nodeSelector:
    kubernetes.io/os: linux     # every Linux node (the chart default)
  config:
    - devicematch: ^fuse$
      nummaxdevices: 150
```

Singleuser pods then request it (in the z2jh block):

```yaml
jupyterhub:
  singleuser:
    extraResource:
      limits:    { smarter-devices/fuse: "1" }
      guarantees:{ smarter-devices/fuse: "1" }
```

**Where it runs.** The chart sets `nodeSelector: {kubernetes.io/os: linux}`, so
the plugin runs on every Linux node and **no node label is needed**. (With an
empty selector the upstream chart falls back to a hard-coded
`smarter-device-manager: enabled` selector; that is why earlier versions
required labelling nodes.) To limit it, add your own keys under
`smarter-device-manager.nodeSelector`: Helm merges them with the default, so a
node must match both. The plugin tolerates only the `smarter.type=edge` taint
(hard-coded upstream), so it skips nodes with other `NoSchedule` taints. A pod
that requests `smarter-devices/fuse` on a node without the plugin stays
`Pending` and CVMFS never mounts.

### 3. The `cvmfs` PVC (in-house)

The chart creates the PVC that singleuser pods mount at `/cvmfs`:

```yaml
cvmfs:
  pvc:
    name: cvmfs
    storageClassName: cvmfs     # the automount SC created by cvmfs-csi
```

It is mounted with `mountPropagation: HostToContainer` so new repositories
appearing under `/cvmfs` are visible in the container. The `claimName` in the
z2jh `singleuser.storage.extraVolumes` must equal `cvmfs.pvc.name`.

> **List-replace warning — restate the `cvmfs` volume.** Helm **replaces** list
> values; it does not merge them. If your overlay sets
> `jupyterhub.singleuser.storage.extraVolumes` / `extraVolumeMounts` for any
> reason, you must **restate the `cvmfs` volume** (and its `/cvmfs` mount) — omit
> it and you silently drop `/cvmfs`, even with `cvmfs.enabled=true`. The same
> applies to `extraVolumeMounts`. (Maps merge; lists replace.)

### 4. Squid cache (in-house)

An **optional** in-cluster Squid HTTP cache fronting the Stratum-1 mirrors.
**Toggle:** `global.cvmfs.squidEnabled` (the single source of truth, default
`false`). When on — and `cvmfs.enabled` is true — this chart renders the Squid
Deployment/Service, and the cvmfs-csi ConfigMap points `CVMFS_HTTP_PROXY` at it.
The keys under `cvmfs.squid` are **deploy settings only** (image, cache sizing,
resources); they no longer carry an `enabled` flag.

```yaml
global:
  cvmfs:
    squidEnabled: true          # the ONLY squid toggle

cvmfs:
  squid:                        # deploy settings only — no `enabled` here
    image: ubuntu/squid:6.6-24.04_edge@sha256:8a3baed477e2c282ab8aa5edad442f69873246964f225c5c2ae8364b6610963c
    storageClassName: ""        # "" => global.storageClassName / cluster default
    cacheSize: 60Gi
    cacheDirSizeMB: 50000
    cacheMemMB: 256
    maxFileDescriptors: 65536   # squid max_filedescriptors; see values.md
    maxObjectSizeMB: 1024
    clientCidrs: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16]   # all private ranges
    resources:                  # cache index ~10 MB per GB of cache_dir, on top of cacheMemMB
      requests: { memory: 1Gi, cpu: 200m }
      limits:   { memory: 2Gi, cpu: "1" }
    nodeSelector: {}            # pin squid (RWO cache volume) off autoscaled/drainable nodes
    tolerations: []
```

When **on**, `CVMFS_HTTP_PROXY` becomes
`http://cvmfs-squid.<namespace>.svc.cluster.local:3128;DIRECT` (squid first,
DIRECT only if squid fails; `|` would load-balance and silently bypass squid).
When **off**,
it's `DIRECT` (pods hit the mirrors directly). Enable Squid to cut egress and
speed up cold mounts on busy clusters; the cache PVC uses `neurodesk.storageClass`
(explicit `squid.storageClassName`, else `global.storageClassName`, else cluster
default).

`cvmfs.squid.clientCidrs` must cover your pod network. Squid answers `403` to
any other client, and CVMFS then silently falls back to `DIRECT` — it works,
but uncached. The default is all private ranges (`10.0.0.0/8`,
`172.16.0.0/12`, `192.168.0.0/16`); Squid is a ClusterIP Service only. Chart
0.1.x defaulted to the k3s ranges (`10.42.0.0/16`, `10.43.0.0/16`), which made
Squid refuse pods on k0s and kubeadm clusters, for example.

### 5. Health probe (in-house)

A per-node DaemonSet (`cvmfs.probe.enabled`, default `true`) that checks
`/cvmfs` and emits a `cvmfs_mount_healthy` gauge:

```yaml
cvmfs:
  probe:
    enabled: true
    image: python:3.14-alpine@sha256:9e9fde4d32eedce0b661d9ab91e826b62dddf28e928c230ec55f1866cac66b01
    intervalSeconds: 30
    nodeSelector: {}      # schedule the probe only where CVMFS is expected
    tolerations: []       # NO longer tolerates all taints (see below)
```

Detection-only. To scrape the metric, set `infra.monitoring.serviceMonitors=true`
and have a Prometheus Operator present.

> **Scheduling — no longer tolerates all taints.** The probe DaemonSet defaults
> to `nodeSelector: {}` / `tolerations: []`, so it lands **only** on schedulable
> nodes where CVMFS is actually expected. This fixes false-positive
> `cvmfs_mount_healthy=0` alerts that used to fire from control-plane / non-CVMFS
> nodes (where `/cvmfs` is never mounted). If your CVMFS node pool carries a
> taint, add a matching toleration (and/or a `nodeSelector`) here so the probe
> runs there.

### 6. Trace-parser (in-house, WIP)

The CVMFS trace-parser telemetry stack (ported from devstack), off by default:

```yaml
cvmfs:
  traceParser:
    enabled: false
    image: python:3.14-slim@sha256:51dafde81dbdb6ebde285137a295cf18a47ca95234fe388a343719cb97305b3d
    replicas: 1
    kubectlVersion: v1.35.9       # +/-1 minor of your apiserver
    requestsVersion: "2.34.2"
```

Analytics on CVMFS access traces. **WIP and off by default**: it installs its
runtime dependencies via `apt`/`pip` at container start, which is fragile (a
slow or unreachable upstream package index leaves the pod crash-looping). Its
ServiceMonitor needs a Prometheus Operator. Leave it off unless you are actively
working on the trace analytics.

## Server / repositories

```yaml
global:
  cvmfs:
    server: "http://cvmfs-jetstream.neurodesk.org/cvmfs/@fqrn@;http://s1fnal-cvmfs.openhtc.io/cvmfs/@fqrn@;..."

cvmfs:
  repositories:
    - neurodesk.ardc.edu.au
```

`global.cvmfs.server` is a `;`-separated list of Stratum-1 mirrors; `@fqrn@` is
expanded per-repository by CVMFS. `cvmfs.repositories` is what gets exposed under
`/cvmfs`. (`server` lives under `global` so the cvmfs-csi subchart reads the same
value — see the single-source-of-truth section above.)

## Running CVMFS yourself

There are two distinct cases — pick the right one:

### A. Bring your own CVMFS — keep notebooks mounting `/cvmfs` (recommended)

If you run CVMFS yourself but want the notebooks to consume it exactly as they
would the chart's, use the **first-class `external` mode** — not a manual
disable:

```yaml
cvmfs:
  enabled: false   # don't install the chart's CVMFS machinery
  external: true   # external CVMFS provides /cvmfs + FUSE; keep the wiring
```

No null-editing, no bypass flags. The chart drops all its CVMFS objects but the
notebook keeps `/cvmfs` + the FUSE request. Your cluster must provide a PVC named
`cvmfs`, the `smarter-devices/fuse` resource (your own device plugin + node
label), and the automount StorageClass. Full walkthrough +
[`examples/external-cvmfs-values.yaml`](../examples/external-cvmfs-values.yaml)
in [disabling-components.md](disabling-components.md#bring-your-own-cvmfs-cvmfsexternal-true--first-class).

### B. No CVMFS at all (`cvmfs.enabled=false`, default `external=false`)

If you want notebooks with **no** `/cvmfs` mount, disable the component and
remove the singleuser wiring. You must adjust the z2jh singleuser block in your
overlay, because Helm cannot do it for you across the subchart boundary:

- Drop the FUSE resource by nulling the **whole submap**:
  `extraResource: { limits: null, guarantees: null }` (renders a clean
  `extraResource: {}`). Setting them to `{}` does **not** remove them — Helm
  **map-merges** the singleuser block. **Do NOT null just the leaf**
  (`extraResource.limits.smarter-devices/fuse: null`): across the subchart
  boundary that `null` survives into the hub config as an invalid `null` quantity
  and breaks the spawn. (Unless your own FUSE mechanism still uses
  smarter-device-manager, in which case keep the request.)
- Restate `jupyterhub.singleuser.storage.extraVolumes` / `extraVolumeMounts`
  **without** the `cvmfs` entry. Lists **replace** (they don't merge), so
  restating them drops what you omit — that is exactly how you remove `/cvmfs`,
  but it also means you must re-list `shm-volume` and anything else you still
  want.

Then supply your own cvmfs-csi config under the `cvmfs-csi:` key (or install it
standalone) and provide a PVC named to match whatever your singleuser block
mounts. The render-time guards `validation.fuseResourceWhenCvmfsOff` /
`validation.cvmfsVolumeWhenCvmfsOff` fail fast if you forget either edit (see
[disabling-components.md](disabling-components.md)). See
[architecture.md](architecture.md) for why this manual sync is necessary.
