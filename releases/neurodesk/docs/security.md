# Security profiles

The chart hardens singleuser notebook pods with **AppArmor** and (optionally)
**Seccomp** profiles, delivered through the **Security Profiles Operator (SPO)**.
It is **on by default** (`security.enabled=true`, `security.installOperator=true`).
The bundled SPO needs **cert-manager** — see [cert-manager](#cert-manager-required-by-spo).

> **Requires Kubernetes ≥ 1.30.** The default singleuser AppArmor attachment uses
> the **native** `securityContext.appArmorProfile` field (beta, on by default, in
> k8s 1.30; GA in 1.31)
> (`Chart.yaml` sets `kubeVersion: ">=1.30.0-0"`). On older clusters that field is
> **silently ignored** — the profile is loaded but **not enforced** on the pod —
> so the bound is enforced at install time. (The pre-1.30
> `container.apparmor.security.beta.kubernetes.io/<container>` annotation is **not**
> used.)

## What gets deployed

| Object | Toggle | Kind |
| --- | --- | --- |
| Security Profiles Operator | `security.installOperator` (default `true`) | vendored subchart: upstream kubernetes-sigs `security-profiles-operator` `1.0.0` from `vendor/security-profiles-operator`, with local patches. Runs in namespace **`security-profiles-operator`**. |
| cert-manager | `cert-manager.enabled` (default **`false`**) | optional remote subchart `cert-manager` `v1.21.2` from `oci://quay.io/jetstack/charts`. Only for a cluster that has no cert-manager. |
| `AppArmorProfile` CR | `security.enabled` + `security.appArmor.enabled` | in-house template; API `security-profiles-operator.x-k8s.io/v1`, **cluster-scoped** |
| `SeccompProfile` CR | `security.enabled` + `security.seccomp.enabled` | in-house template; API `security-profiles-operator.x-k8s.io/v1`, **cluster-scoped** |

The profile CRs are referenced **by name** from the z2jh singleuser pod
`securityContext`. SPO's node DaemonSet (`spod`) is what actually loads the
profiles onto each node so the kernel can enforce them.

The profile CRs render **whenever** their toggles are on. If nothing can serve
them (no SPO, or an incompatible one), the render **fails** with instructions
(see [How the chart checks for SPO](#how-the-chart-checks-for-spo)); it never
skips them silently.

## SPO bundling and the `installOperator` toggle

SPO ships **bundled** with the chart as a conditional subchart:

```yaml
# Chart.yaml
- name: security-profiles-operator
  version: "1.0.0"
  repository: "file://vendor/security-profiles-operator"   # upstream v1.0.0, vendored + patched
  condition: security.installOperator
```

It is upstream **kubernetes-sigs SPO v1.0.0**, **vendored** under
`vendor/security-profiles-operator` because it needs local patches to work
inside this chart's release at all. `PROVENANCE.txt` in that directory records
the source archive, its sha256, the re-vendor procedure and every patch:

- **Fixed runtime namespace.** Upstream 1.0.0 hard-codes the namespace
  `security-profiles-operator` in its CRD conversion webhooks and in the
  cert-manager CA-injection annotations (including those the operator writes at
  runtime). So the operator, its webhook and `spod` **always** run in namespace
  `security-profiles-operator`, whatever namespace this release uses. The app
  itself stays in the release namespace.
- **Release ownership.** Every SPO object is owned by this release, so
  `helm upgrade` / `helm uninstall` of this release manage them.
- **Namespace creation.** The release creates `security-profiles-operator` with
  `pod-security.kubernetes.io/enforce: privileged` (`spod` is privileged) and
  `helm.sh/resource-policy: keep`, so it survives `helm uninstall`. Set
  `security-profiles-operator.operatorNamespace.create=false` when that
  namespace is managed outside this release.
- **Operator AppArmor RBAC.** Upstream 1.0.0 omits `apparmorprofiles` from the
  operator's ClusterRole, so AppArmor profiles never reconcile. The vendored
  chart adds ClusterRole/ClusterRoleBinding `security-profiles-operator-apparmor`
  (`templates/apparmor-rbac.yaml` inside the vendored chart).

`helm dependency build` packages it into `charts/`. Its CRDs ship from the
vendored chart's `crds/` dir. The chart overrides three upstream defaults under
the `security-profiles-operator:` values block:

- **Image** pinned to
  `registry.k8s.io/security-profiles-operator/security-profiles-operator:v1.0.0`
  (upstream defaults to a moving staging `latest` tag; `registry.k8s.io`
  promoted tags are immutable).
- **`replicaCount: 1`** (upstream: 3, leader-elected). Raise it for operator HA.
- **`podSecurityContext.seccompProfile.type: RuntimeDefault`** on the operator
  pod (upstream sets none).

`enableAppArmor: true` must stay on, or `spod` never loads the AppArmor profile
and the kubelet rejects every notebook (profile not found).

- **`installOperator: true` (default)** — the chart installs SPO (its CRDs,
  operator, webhook and node DaemonSet) and the profile CRs. Needs cert-manager.
- **`installOperator: false`** — the chart does **not** install SPO. The cluster
  must already run **SPO ≥ 1.0.0** (API `security-profiles-operator.x-k8s.io/v1`).
  SPO 0.x — including the neurodesk fork bundled by chart 0.1.x and AIS
  devstack's `0.10.1-dev` — is **not** compatible. cert-manager is then not
  this chart's concern.

### cert-manager (required by SPO)

SPO 1.0.0 gets its webhook and metrics certificates, and the CA bundle of its
CRD conversion webhooks, from **cert-manager**: the operator creates its Issuer
and Certificates in the `security-profiles-operator` namespace at runtime. So
with `installOperator=true`, one of these must hold:

- **The cluster already runs cert-manager** (most clusters). Leave
  `cert-manager.enabled=false`.
- **The cluster has no cert-manager.** Set `cert-manager.enabled=true` and this
  release installs cert-manager `v1.21.2` (into the release namespace, CRDs
  kept on uninstall via `crds.keep=true`). The release then owns cert-manager's
  lifecycle.

cert-manager is a cluster singleton (CRDs, webhooks), so never enable it on a
cluster that already has one: the chart **never adopts** an existing
cert-manager. The render fails when neither holds (guard 5c below).

### How the chart checks for SPO

All checks use API discovery (`.Capabilities.APIVersions`), which
`helm install/upgrade`, Argo CD and Flux fill from the live cluster. A plain
offline `helm template` sees only the built-in APIs, so there you assert what
the cluster has with `--api-versions` (or the named setting).

| Guard (`templates/validate.yaml`) | Fails when | Offline assertion / bypass |
| --- | --- | --- |
| 5a | `installOperator=true` and the cluster serves only the **legacy** SPO API (`v1alpha1` AppArmorProfile, no `v1`) — i.e. SPO < 1.0.0, such as the fork a 0.1.x release bundled. See [migration.md](migration.md#01x---020). | none: no bypass, and it needs a live cluster to fire |
| 5b | `installOperator=false` and the cluster does not serve the `v1` `AppArmorProfile` (or `SeccompProfile`, when seccomp is on). | `--api-versions security-profiles-operator.x-k8s.io/v1/AppArmorProfile` (and `/SeccompProfile`), or `security.assumeCrdsPresent=true` |
| 5c | `installOperator=true`, `cert-manager.enabled=false`, and the cluster does not serve `cert-manager.io/v1` `Certificate`. | `--api-versions cert-manager.io/v1/Certificate`; bypass `validation.certManagerMissing=true` |

**`security.assumeCrdsPresent`** now means only "skip the API discovery check
when rendering offline" (guard 5b). It asserts that SPO ≥ 1.0.0 is installed; it
is equivalent to `--api-versions security-profiles-operator.x-k8s.io/v1/AppArmorProfile`
(plus `/SeccompProfile` when seccomp is on).
It no longer decides whether the profile CRs render.

Because of 5c, an offline `helm template` with **default** values fails. Pick
the variant that matches the target cluster (these only print the manifests;
to **apply** rendered output, add `--no-hooks` — see
[install.md](install.md#helm-template--kubectl-apply-alternative)):

```sh
# cluster with no cert-manager (standalone: the release installs it)
helm template neurodesk . -n neurodesk --set cert-manager.enabled=true
# cluster that already runs cert-manager
helm template neurodesk . -n neurodesk --api-versions cert-manager.io/v1/Certificate
```

> `helm lint` reports these `fail` calls only as `[INFO] Fail: …` and still
> passes; only `helm template` / `helm install` / `helm upgrade` enforce them.

### Shared-cluster COLLISION warning

SPO is a **cluster singleton**: its CRDs, ClusterRoles, webhook configurations
and runtime namespace have fixed, un-prefixed names. Consequences on a shared
cluster:

- If the cluster **already runs SPO**, installing with `installOperator=true`
  fails on the colliding objects (and on guard 5a, if that SPO is < 1.0.0).
- A **second release** of this chart with `installOperator=true` collides with
  the first release's SPO the same way.

In both cases set **`installOperator=false`** so this release reuses the
existing SPO ≥ 1.0.0 and only renders its profile CRs.

**Profile names are cluster-unique too** (the CRs are cluster-scoped). A second
release must pick a name other than `notebook` in **both**
`security.appArmor.profileName` and the singleuser
`appArmorProfile.localhostProfile` (guard `apparmorNameMismatch` enforces that
they match). Likewise `security.seccomp.profileName` if seccomp is on.
[`examples/neurocloud-values.yaml`](../examples/neurocloud-values.yaml) is a
worked example.

## AppArmor / Seccomp CRs

| Value | Default | Notes |
| --- | --- | --- |
| `security.appArmor.enabled` | `true` | Render the `AppArmorProfile` CR (when `security.enabled`). |
| `security.appArmor.profileName` | `notebook` | CR name = kernel profile name the singleuser pod references. Cluster-unique. |
| `security.seccomp.enabled` | `false` | Render the `SeccompProfile` CR (when `security.enabled`). |
| `security.seccomp.profileName` | `log` | Seccomp profile name. Cluster-unique. |

AppArmor is the default-on profile for notebook pods and **is** auto-attached to
the singleuser pod (via `jupyterhub.singleuser.extraPodConfig`, default
`localhostProfile: notebook`).

### What the AppArmor profile allows

The profile (`templates/security/apparmor-profile.yaml`) is written only with
SPO's **structured** `spec.abstract` fields, in `mode: Enforce`. It is the
profile neurocloud runs on upstream SPO 1.0.0:

- **Filesystem:** read/write on `"/"` and `"/**"` (`"/"` is explicit because
  `/**` does not match the root directory itself, which rootless Apptainer opens
  when entering its mount namespace).
- **Execution:** `/**` with `ix` (inherit), so binaries launched from a
  notebook — including inside Apptainer containers — stay under this profile;
  libraries `/**` `mr`.
- **Capabilities:** `sys_rawio`, which makes SPO's generator emit
  `mount, remount, umount,` (needed by unprivileged Apptainer and CVMFS FUSE),
  plus a list reproducing the old blanket `capability,` rule. Effective
  capabilities stay bounded by the unprivileged pod's own capability set.
- **Network:** TCP, UDP and raw sockets.
- **No ptrace between notebook processes.** SPO's structured API has no ptrace
  field, so the profile has no ptrace rule and AppArmor denies tracing.
  Inside a notebook, `PTRACE_TRACEME` and `PTRACE_ATTACH` fail with `EACCES`,
  `gdb` cannot run programs (`ptrace: Permission denied`), and the node's kernel
  log shows `apparmor="DENIED" operation="ptrace" profile="notebook"
  requested_mask="trace" peer="notebook"`. Tracers such as `strace`, `ltrace`
  and `py-spy` (not in the image) would fail the same way. The `sys_ptrace`
  entry in the capability list does not change this. neurocloud runs this same
  profile.

Upstream SPO also injects hardening denies for `/proc/*`, `/proc/sys`,
`/proc/{mem,kmem,kcore,sysrq-trigger}` and efivars; those leave
`/proc/<pid>/{uid_map,gid_map,setgroups}` writable, so unprivileged Apptainer
user-namespace setup still works.

**Dropped from the 0.1.x profile:** the neurodesk fork allowed raw rules in
`spec.abstract.extra`, which upstream SPO does not have (strict field validation
rejects it). Two rules used that field and are gone:

- `ptrace peer=notebook,` — the 0.1.x profile allowed notebook processes to
  trace each other; 0.2.0 does not (above), so debuggers and tracers no longer
  work in notebooks.
- The **crypto-miner exec denylist**
  (`deny /**{m,M}iner* x, …`): the structured API has allow lists only, so it
  cannot express deny rules (and name globs were bypassed by renaming a binary
  anyway). If you need miner protection, deploy a runtime detector such as
  cryptnono alongside the chart; the chart does not ship one.

### Seccomp is audit-only AND not auto-attached

Two things to know before relying on seccomp:

1. **Audit-only.** Even with `security.seccomp.enabled=true`, the shipped `log`
   profile has `defaultAction: SCMP_ACT_LOG` — it **logs** syscalls and
   **enforces nothing**. It's a profiling/observability tool, not a sandbox.
2. **Not auto-attached.** Unlike AppArmor, enabling the CR does **not** wire the
   profile onto the singleuser pod. To actually attach it you must add the
   `seccompProfile` block to your overlay yourself:

   ```yaml
   jupyterhub:
     singleuser:
       extraPodConfig:
         securityContext:
           seccompProfile:
             type: Localhost
             localhostProfile: operator/log.json   # operator/<security.seccomp.profileName>.json
   ```

   The `operator/<profileName>.json` path (no namespace segment: `SeccompProfile`
   is cluster-scoped) is where SPO writes the profile
   under the kubelet seccomp root. Enable and attach once you've validated the
   audit logs don't show syscalls your neuroimaging tooling needs (before
   eventually switching the profile to an enforcing action).

## Manual node-load fallback (no SPO at all)

If you deliberately run without any SPO, the profile CRs cannot exist (there is
no CRD to back them), but the kernel still needs the profile loaded on every
node. Keep the pod attachment, turn the CRs off, and load the profile yourself:

```yaml
security:
  enabled: true
  installOperator: false
  appArmor:
    enabled: false        # no AppArmorProfile CR (nothing could serve it)
  seccomp:
    enabled: false
validation:
  apparmorAttachWithoutProfile: true   # the attachment is deliberate: you load the profile
```

1. **AppArmor** — place the profile under `/etc/apparmor.d/` on each node and
   load it:
   ```sh
   # on each node (or via a privileged DaemonSet / node bootstrap)
   apparmor_parser -r -W /etc/apparmor.d/notebook
   ```
   The singleuser pod references it as a *localhost* profile named `notebook`
   (its `appArmorProfile.localhostProfile`), so the on-disk profile name must
   match.
2. **Seccomp** — place the JSON profile under the kubelet's seccomp root
   (`/var/lib/kubelet/seccomp/`) on each node and reference it by relative path.

Because this is exactly the node bookkeeping SPO automates, prefer leaving
`installOperator=true` (or pointing at an existing SPO ≥ 1.0.0) unless you have
a strong reason. The manual route must be re-applied whenever nodes are
recreated.

## The singleuser `securityContext` sync caveat (important)

This is the one piece Helm **cannot** wire for you. The profile **attachment**
lives in the z2jh values block:

```yaml
jupyterhub:
  singleuser:
    extraPodConfig:
      securityContext:
        fsGroup: 100                   # restated: this block replaces z2jh's own pod securityContext
        fsGroupChangePolicy: OnRootMismatch
        appArmorProfile:
          type: Localhost
          localhostProfile: notebook   # <-- must equal security.appArmor.profileName
```

Plain Helm cannot mutate a subchart's values from a sibling toggle at render
time (values are merged and handed to the subchart **before** templates render).
So the `localhostProfile: notebook` reference above is **not** auto-synced from
`security.appArmor.profileName`. You must keep them equal yourself:

- **Default install:** already consistent — both say `notebook`, AppArmor on.
- **Changing the profile name** (for example a second release on the same
  cluster): update **both** `security.appArmor.profileName` **and** the
  singleuser `appArmorProfile.localhostProfile` in your overlay.
- **Adding seccomp on pods:** enable `security.seccomp.enabled`, and *also* add
  the seccomp `localhostProfile: operator/log.json` reference to the
  singleuser `securityContext` yourself — it is **not** auto-attached (see
  "Seccomp is audit-only AND not auto-attached" above).
- **Disabling security entirely:** set `security.enabled=false` **and**
  `security.installOperator=false` (the SPO subchart is gated on
  `installOperator` alone, so `security.enabled=false` by itself still installs
  the operator and still requires cert-manager), **and** null-delete the
  `appArmorProfile` block from the singleuser `securityContext` in your overlay
  (`appArmorProfile: null` — `{}` won't remove an inherited map key) — otherwise
  pods reference a profile that no longer exists and may fail to spawn. (The
  `apparmorAttachWithoutProfile` guard catches this.) See the step-by-step in
  [disabling-components.md](disabling-components.md).

This "opinionated, internally-consistent defaults + explicit overlay sync for
deviations" is the chart-wide pattern for the subchart-boundary limitation; see
[architecture.md](architecture.md).

## Uninstalling

**Stop every user server first.** Deleting a profile unloads it from the
kernel, and a notebook still confined by it can no longer start any process.
With the bundled operator, the `uninstallCleanup` pre-delete hook enforces this
for **this release's namespace** (it refuses while a user server exists there,
before deleting anything), then removes the profiles while `spod` still runs —
otherwise they stay `Terminating` on their per-node finalizers — and removes
the operator's runtime objects, including `spo-validating-webhook-configuration`.
With an external operator the hook leaves the profiles to Helm (the external
operator unloads them), but still runs its no-user-servers check whenever the
release owns a profile. If CVMFS is not managed by the release either, that
check is all it runs; with `cvmfs.enabled=true` it also removes the CVMFS
probe and PVCs.

Limits of the hook (details in [install.md](install.md#teardown--uninstall)):

- It covers **`helm uninstall` only**. A `helm upgrade` from
  `installOperator=true` to `false` removes the operator in one pass and strands
  the profiles and runtime objects the same way: treat it as uninstall +
  reinstall, or delete this release's profiles first while `spod` still runs.
- Its pod check is **not global**. The operator is a cluster singleton, so a
  release with `installOperator=true` serves every other release that set
  `installOperator=false`, and any other workload using SPO profiles. Remove or
  move those first, and **uninstall the operator-owning release last**.
- It does not run for a raw `helm template | kubectl apply` install, which must
  be rendered with `--no-hooks` and removed by hand.

## No secrets here

Security profiles carry no secrets. For the secrets the rest of the stack needs
(z2jh proxy token / cookie secret, OAuth client secret, XNAT credentials), see
[secrets.md](secrets.md).
