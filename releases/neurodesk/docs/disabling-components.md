# Disabling components (the Helm map-merge gotchas)

Every component is independently toggleable from `values.yaml`. But because the
neurodesk **singleuser** block is part of the z2jh subchart, turning CVMFS or
security **off** is not just a single `enabled: false` — you must also undo the
opinionated defaults that live in `jupyterhub.singleuser`. Plain Helm cannot do
this for you across the subchart boundary (see [architecture.md](architecture.md)).

Two Helm merge rules make this easy to get wrong:

- **Maps merge.** Overriding a map key with `{}` does **not** remove inherited
  keys — they stay merged in. To delete inherited defaults, null the **whole
  submap / object** with explicit `null` (e.g.
  `extraResource: { limits: null, guarantees: null }`, or
  `appArmorProfile: null`).
  **Do NOT null just the leaf** (`extraResource.limits.smarter-devices/fuse:
  null`): across the subchart boundary that `null` **survives** into the hub
  config as an invalid `null` quantity and **breaks the spawn** — it does not
  remove the entry. Nulling the whole submap renders a clean `extraResource: {}`.
- **Lists replace.** Overriding a list **replaces** the whole list — it does not
  merge by index/name. Restating a list drops everything you omit (which is how
  you remove an item — but also how you accidentally drop one), so **restate
  exactly what you keep**.

The chart guards against forgetting these with the render-time
`validation.*` checks (see [values.md](values.md)); they `fail` the render with an
actionable message rather than producing a silently-broken install.

> **Worked example:** [`ci/ct-values-minimal.yaml`](../ci/ct-values-minimal.yaml)
> turns CVMFS **and** security off the right way (it is part of the CI matrix, so
> it always renders). Copy it as your starting point.

## Turning CVMFS off (`cvmfs.enabled=false`)

This switches off the `cvmfs-csi` / `smarter-device-manager` subcharts and the
in-house PVC/squid/probe/trace-parser templates. You must **also** edit the z2jh
singleuser block in your overlay:

```yaml
cvmfs:
  enabled: false

jupyterhub:
  singleuser:
    # Null the WHOLE submap (renders a clean `extraResource: {}`). Nulling just
    # the leaf (`smarter-devices/fuse: null`) does NOT work: across the subchart
    # boundary that null survives into the hub config as an invalid `null`
    # quantity and breaks the spawn.
    extraResource:
      limits: null
      guarantees: null
    storage:
      # Lists REPLACE — restate everything you still want, minus the cvmfs entry.
      # Forgetting to restate a volume drops it.
      extraVolumes:
        - name: shm-volume
          emptyDir:
            medium: Memory
      extraVolumeMounts:
        - name: shm-volume
          mountPath: /dev/shm
```

Relevant guards (active by default; both would fail the render if you forget):
`validation.fuseResourceWhenCvmfsOff`, `validation.cvmfsVolumeWhenCvmfsOff`.

This is the "I don't want CVMFS at all" case. If instead you want to **keep
CVMFS but run it yourself**, use the dedicated mode below — don't null anything.

## Bring your own CVMFS (`cvmfs.external: true`) — first-class

This is the headline use of the toggles: **you manage CVMFS, the chart does
everything else and consumes your CVMFS exactly as it would its own.**

```yaml
cvmfs:
  enabled: false     # don't install the chart's CVMFS machinery
  external: true     # an external CVMFS provides /cvmfs + FUSE; keep the wiring
```

That's it — no null gymnastics and no `validation.*` bypass flags. The chart
installs **no** CVMFS objects (cvmfs-csi, smarter-device-manager, the `cvmfs`
PVC, squid, probe, trace-parser), but the singleuser pod **keeps** its `/cvmfs`
mount and `smarter-devices/fuse` request, and the cvmfs-off guards stand down
(because in `external` mode that wiring is intentional).

Your cluster must already provide, in the release namespace, what the chart's
CVMFS did:

1. a **PVC named `cvmfs`** mounting `/cvmfs` (or restate the `extraVolumes` list
   with your own claimName);
2. the **`smarter-devices/fuse`** extended resource — your own
   `smarter-device-manager` (or equivalent device plugin) running on the
   notebook nodes. (Installed from the upstream chart with no `nodeSelector`,
   smarter-device-manager runs only on nodes labelled
   `smarter-device-manager=enabled`.);
3. the **automount StorageClass** your `cvmfs` PVC binds to.

Set those up correctly and the rest of the chart works unchanged. A ready
overlay is in [`examples/external-cvmfs-values.yaml`](../examples/external-cvmfs-values.yaml).
Guard: setting `cvmfs.external=true` while `cvmfs.enabled=true` fails the render
(you'd be installing the chart's CVMFS *and* declaring an external one).

The same "run it yourself" pattern already exists for **security** — set
`security.installOperator=false` to consume a Security Profiles Operator ≥ 1.0.0
the cluster already runs (see [below](#running-on-a-cluster-that-already-has-spo)
and [security.md](security.md)).

## Turning AppArmor / security off

```yaml
security:
  enabled: false           # (or appArmor.enabled: false)
  installOperator: false   # also drop the operator (and its cert-manager need)

jupyterhub:
  singleuser:
    extraPodConfig:
      securityContext:
        appArmorProfile: null   # explicit null — remove the attachment
```

`security.enabled=false` removes only the profile CRs. The SPO subchart is gated
on `security.installOperator` alone, so without `installOperator: false` the
operator is still installed and the render still requires cert-manager.

Leaving the `appArmorProfile` attached while the profile CR isn't rendered makes
pods reference a missing profile. The guard
`validation.apparmorAttachWithoutProfile` catches this;
`validation.apparmorNameMismatch` catches a `localhostProfile` that doesn't equal
`security.appArmor.profileName`. (Seccomp is **not** attached by default, so there
is nothing to null-delete for it unless you added a `seccompProfile` block.)

**Install it yourself separately.** For hardening without this chart's CRs, run
SPO (or load the AppArmor/Seccomp profiles onto nodes) out of band and attach
them via the singleuser `securityContext`. See the manual node-load fallback in
[security.md](security.md).

## Running on a cluster that already has SPO

If the cluster already runs the Security Profiles Operator (or you can't install a
second cluster-scoped operator), keep the profile CRs but skip the operator:

```yaml
security:
  installOperator: false
  assumeCrdsPresent: true   # only needed to render offline (plain `helm template`)
  appArmor:
    profileName: neurodesk-notebook   # profiles are cluster-scoped: pick an unused name
jupyterhub:
  singleuser:
    extraPodConfig:
      securityContext:
        appArmorProfile:
          localhostProfile: neurodesk-notebook   # must equal security.appArmor.profileName
```

That SPO must be **≥ 1.0.0** (API `security-profiles-operator.x-k8s.io/v1`); SPO
0.x, including the neurodesk fork, is not compatible. The profile CRs always
render. On `helm install`/`upgrade` (and Argo CD / Flux) the chart checks that
the cluster serves the `v1` kinds and fails with instructions if not;
`assumeCrdsPresent: true` skips that check for offline renders, asserting the
operator is there. The profile name only has to change if another release (or
the cluster's own SPO setup) already owns `notebook`.
[`examples/neurocloud-values.yaml`](../examples/neurocloud-values.yaml) is a
worked example.

## Turning XNAT off (`xnat.enabled=false`) — the default

XNAT is **off by default**, so this is the no-op baseline. The extension
ConfigMap and the egress NetworkPolicy are in-house templates gated on
`xnat.enabled` — with it off they don't render, and there are **no** inherited
`singleuser` keys to clean up (the XNAT spawner wiring lives in a separate
overlay, `examples/devstack`, that you only add when enabling XNAT). The external
XNAT **server** is never deployed by this chart regardless. See
[xnat.md](xnat.md).

## Turning JupyterHub off (`jupyterhub.enabled=false`)

This drops the entire z2jh subchart (hub, proxy, and the whole `singleuser`
block). Because the `singleuser` block disappears with it, the validation guards
have nothing to inspect and there are **no** overlay clean-ups to do. You would
do this to **bring your own JupyterHub** while still using this chart for CVMFS /
security / glue — in which case your external Hub's singleuser pods must
themselves request `smarter-devices/fuse`, mount the `cvmfs` PVC, and attach the
AppArmor profile this chart still creates; the chart no longer wires any of that
across the (now absent) subchart boundary.

## Bypassing a guard

Each `validation.*` flag defaults to `false` (guard **active**). Set one to `true`
only to deliberately bypass that single check — for example when you intentionally
keep the FUSE device for a non-CVMFS reason. See [values.md](values.md) for the
full list.
