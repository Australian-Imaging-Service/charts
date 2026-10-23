# XNAT integration (optional)

The chart connects JupyterHub to an **XNAT** imaging server in three independent
ways, all **off by default**:

| Part | Toggle | What users get |
| --- | --- | --- |
| XNAT upload extension | `xnat.enabled` (+ `xnat.uploadExtension.enabled`, default on) | Upload data from JupyterLab to XNAT. |
| Servers launched **from XNAT** | `xnat.jupyterhub.enabled` (under `xnat.enabled`) | XNAT's "Start Jupyter" opens a notebook with the chosen image, resources and the selected XNAT data mounted read-only. |
| AAF login | `auth.aaf.enabled` | JupyterHub login through the Australian Access Federation, with usernames that match XNAT's. |

The chart never deploys or configures XNAT itself. Under the AIS umbrella chart
(`releases/ais`) XNAT is in the same release and all the Kubernetes wiring is
done for you; see [Under the AIS umbrella](#under-the-ais-umbrella).

## Servers launched from XNAT

XNAT's JupyterHub plugin (`xnat-jupyterhub-plugin`) asks the hub, through the
hub API, to start a named server for the XNAT user (for example
`admin/<timestamp>`). When the hub spawns it, the chart's pre-spawn hook
(`files/hub/neurodesk_integrations.py`) asks XNAT for that launch:

```
GET <xnat>/xapi/jupyterhub/users/<user>/server/<name>/user-options
GET <xnat>/xapi/jupyterhub/users/<user>/server/user-options      (default server)
```

It uses an XNAT account read from a Kubernetes Secret at spawn time (by default
the AIS xnat chart's admin Secret `<release>-xnat-web-admin`). The chart grants
`get` on that Secret, which is what the hub needs when z2jh's RBAC is off; with
z2jh's defaults (`rbac.create: true`) the hub's own Role can already read every
Secret in the release namespace, including XNAT's when XNAT shares it, as under
the AIS umbrella. The options sent with the hub API call are ignored: a user can
start their own server with any options, so only XNAT's answer counts.

What the hook applies:

- **Image and command** from the XNAT compute environment. Neurodesk images
  (image name contains `neurodesk`) run as `jovyan` (1000:100); other images get
  `NB_USER=<hub user>`, `NB_UID/NB_GID` from `xnat.jupyterhub.uid/gid` and
  `JUPYTERHUB_SINGLEUSER_EXTENSION=0`.
- **Resources** from the XNAT hardware config: CPU and memory limits and
  reservations; `generic_resources` `gpu` -> `nvidia.com/gpu`, `fuse` ->
  `smarter-devices/fuse`, merged with the chart's own requests (the FUSE device
  for CVMFS stays). A GPU request needs a GPU device plugin or the NVIDIA GPU
  Operator on the cluster; the chart does not install one.
- **Placement constraints** (`key==value`) -> node selector, merged.
- **Environment** from XNAT (`XNAT_HOST`, `XNAT_USER`/`XNAT_PASS` alias token,
  `XNAT_XSI_TYPE`, `XNAT_ITEM_ID`, ...).
- **XNAT data**: each archive mount becomes a read-only `subPath` of XNAT's
  archive PVC at XNAT's target (e.g. `/data/projects/P1/experiments/S1`), and
  again under `~/xnat-data/` (e.g. `~/xnat-data/P1/experiments/S1`), because
  JupyterLab's file browser only shows the home directory. JupyterLab opens on
  that directory. Sources outside `xnat.jupyterhub.archiveMountPath` are refused.
  XNAT writes its archive `0750`/`0640` as `65534:65534`, so the pod also gets
  `xnat.jupyterhub.archiveGid` (65534) as a supplemental group.
- **Home**: the notebook's root directory is the user's home volume for every
  image. XNAT's own workspace mount (`/workspace/<user>`) is not used.

A server that XNAT did not launch (a normal hub login) gets a 404 from XNAT and
spawns with the chart defaults. If XNAT is unreachable or answers with an error,
the spawn fails (`xnat.jupyterhub.failOpen: true` spawns the defaults instead);
the request times out after `requestTimeoutSeconds`.

### One home per user

XNAT starts a new, timestamped named server for every launch and removes it when
it stops. With z2jh's default PVC name (`claim-{user_server}`) every one of those
servers got its own empty home, and KubeSpawner 7.1 (z2jh 4.4) deletes a named
server's home when the server is removed, so everything saved there was lost.
The chart therefore sets

```yaml
jupyterhub:
  singleuser:
    storage:
      dynamic:
        pvcNameTemplate: claim-{username}
```

so all of a user's servers share one home (as ais-devstack does with
`jupyter-{username}`), and KubeSpawner does not delete a shared home when a
named server is removed. Default servers keep the PVC they already had
(`claim-{username}` is the same name for them).

What this supports, and what it does not:

- **ReadWriteOnce homes** (the usual block storage): one server per user at a
  time, or several on the same node. The chart does not force a user's servers
  onto one node; a second server scheduled on another node cannot attach the
  home and fails to start (the first server and the data are unaffected).
- **ReadWriteMany homes**: several servers per user on any nodes.
- **Do not change the template back** on an install that has used the shared
  home without `KubeSpawner.delete_pvc: false` first; see
  [migration.md](migration.md#one-home-per-user).

### Changing the integration settings

The hub reads these settings only when it starts. After a `helm upgrade` or
`helm rollback` that changes them (or the chart's hub code), the chart's hook
restarts the hub and waits for it; nothing to do by hand. Restart the hub
yourself (`kubectl rollout restart deployment/hub`) when hooks do not run:
`--no-hooks`, manifests applied from `helm template`, or a rollback to a chart
older than 0.3.0.

## Under the AIS umbrella

`releases/ais` installs XNAT and this chart in one release and sets:

- `neurodesk.xnat.enabled` and `neurodesk.xnat.jupyterhub.enabled`: the hub
  finds XNAT's Service `<release>-xnat-web`, archive PVC
  `<release>-xnat-web-archive` and admin Secret `<release>-xnat-web-admin` by
  itself, and a NetworkPolicy lets XNAT's pods reach the hub API and the hub and
  notebooks reach XNAT;
- a hub service `xnat` with the role XNAT's plugin needs;
- XNAT plugins `container-service` and `xnat-jupyterhub-plugin` activated;
- an XNAT volume `workspaces` at `/data/xnat/workspaces` (RWX, 10Gi). The plugin
  writes each launch's options there before it asks the hub for a server, and
  the XNAT container's root filesystem is read-only, so without this volume every
  launch fails with `Read-only file system` in XNAT's
  `xnat-jupyterhub-plugin.log`.

What is left is XNAT's own configuration, done once as an XNAT administrator
(Administer > Plugin Settings > JupyterHub, or the REST calls shown):

1. **JupyterHub connection** (`PUT /xapi/jupyterhub/preferences`):
   - `jupyterHubApiUrl`: `http://hub:8081/hub/api` (add `hub.baseUrl` if you
     set one, e.g. `http://hub:8081/jupyter/hub/api`). From outside the release
     namespace use `http://proxy-public.<namespace>.svc.cluster.local/<baseUrl>/hub/api`.
   - `jupyterHubHostUrl`: the hub's public URL, the one browsers open.
   - `jupyterHubToken`: the `xnat` service token, generated by z2jh into Secret
     `hub`. Pipe it, do not print it:
     `kubectl -n <ns> get secret hub -o jsonpath='{.data.hub\.services\.xnat\.apiToken}' | base64 -d`
   - Path translation: the same path on both sides (`/data/xnat/archive`,
     `/data/xnat/workspaces`), i.e. no translation. The hook expects XNAT's own
     paths.
   Check: `GET /xapi/jupyterhub/version` returns the hub version.
2. **Compute environment** (`POST /xapi/compute/environments`): type
   `JUPYTERHUB`, the image (e.g. `ghcr.io/neurodesk/neurodesktop:<tag>`), enabled
   for the site or the projects that should see it.
3. **Hardware** (`POST /xapi/compute/hardware`): CPU/memory limits and
   reservations, optional generic resources (`gpu`).
4. Optional: XNAT's alias-token lifetime (`aliasTokenTimeout` in site config)
   limits how long `XNAT_USER`/`XNAT_PASS` in a notebook stay valid (XNAT
   default 2 days).

Then open a project, subject or session in XNAT and use **Start Jupyter**.

`xnat-web.volumes` in the xnat chart need a `ReadWriteMany` StorageClass by
default (archive, prearchive, workspaces). On a single node you can set their
`accessMode` to `ReadWriteOnce`.

## XNAT elsewhere (standalone chart)

When XNAT is not in the same release:

```yaml
xnat:
  enabled: true
  server:
    host: xnat-web.ais-xnat.svc.cluster.local   # in-cluster host of XNAT
    namespace: ais-xnat                          # XNAT's namespace
  jupyterhub:
    enabled: true
    credentialsSecret: xnat-hub-account          # you create it: username/password
    archivePvc: xnat-archive                     # in THIS namespace
jupyterhub:
  hub:
    services:
      xnat: {}
    loadRoles:
      xnat-role:
        scopes: [admin:servers, admin:users, admin:groups, tokens, list:services,
                 read:hub, access:servers, access:services, proxy]
        services: [xnat]
```

- The archive PVC must be in the hub's namespace (a pod cannot mount a PVC from
  another namespace): bind a PVC here to the same storage as XNAT's archive, for
  example a static NFS PersistentVolume.
- XNAT in another namespace reaches the hub through `proxy-public` (z2jh's hub
  NetworkPolicy only admits pods labelled `hub.jupyter.org/network-access-hub`);
  set `jupyterHubApiUrl` accordingly.

## AAF login

```yaml
auth:
  aaf:
    enabled: true
    clientId: <AAF client id>
    callbackUrl: https://<hub host>/hub/oauth_callback   # include hub.baseUrl
```

Create the client secret yourself: Secret `neurodesk-aaf`, key `client-secret`,
in the release namespace. Endpoints are `https://central.aaf.edu.au/providers/op/*`
(`auth.aaf.issuer: https://central.test.aaf.edu.au` for the AAF test federation).
Scopes: `openid profile email`. Any AAF user may log in (`allowAll: true`); set
`allowAll: false` and list users in
`jupyterhub.hub.config.AAFOAuthenticator.allowed_users` to restrict it.

The hub username is `<usernamePrefix><usernameClaim>`, `aaf_<sub>` by default,
case kept. It must equal the username XNAT's OpenID plugin gives the same person,
because XNAT starts servers for its own username: a different hub name makes a
second hub user and the XNAT-launched server answers 403. If your XNAT names
users differently (another provider id, or a patched username such as an email
prefix), set `usernamePrefix`/`usernameClaim` to match.

## Upload extension

`xnat.enabled` ships the JupyterLab XNAT-upload extension (ConfigMap
`xnat-upload-extension`) and a singleuser NetworkPolicy that allows egress to
XNAT. The extension's dependencies are installed by an init container whose
image is set on the spawner: `jupyterhub.hub.extraEnv.XNAT_EXT_INSTALLER_IMAGE`
(its Python minor must match the notebook image's; see
`examples/devstack-values.yaml`).

## Secrets

Never put XNAT passwords, service tokens or OIDC client secrets in values. The
hub reads XNAT's account from a Secret, z2jh generates the `xnat` service token
into Secret `hub`, and the AAF client secret comes from Secret `neurodesk-aaf`.
See [secrets.md](secrets.md).

## ais-devstack

`examples/devstack-values.yaml` is the ais-devstack overlay. It predates the
built-in integration and still carries its own XNAT hooks
(`jupyterhub.hub.extraConfig` 00-03) with `xnat.jupyterhub.enabled` off; do not
enable both. See [consuming-from-devstack.md](consuming-from-devstack.md).
