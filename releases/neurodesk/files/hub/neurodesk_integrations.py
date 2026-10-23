# Neurodesk JupyterHub integrations (XNAT launch hook, AAF login).
#
# Shipped by the neurodesk chart inside ConfigMap `neurodesk-hub-integration`
# together with integration.json, mounted into the hub at
# /etc/neurodesk/integration, and executed by the jupyterhub.hub.extraConfig
# entry `10-neurodesk-integrations` (so `c` is the JupyterHub config object).
#
# Why a ConfigMap and not plain values: z2jh passes hub.config/extraConfig
# through verbatim, so values cannot carry release-dependent names such as the
# XNAT Service `<release>-xnat-web` or its archive PVC. The chart renders those
# into integration.json instead. integration.json is re-read on every spawn;
# this code runs once at hub start-up.
#
# XNAT behaviour follows the jupyterhub-xnat pre-spawn hook (as used by the AIS
# jupyterhub-xnat chart), with these changes:
#   * async, non-blocking HTTP with a timeout (a hung XNAT cannot stall the hub);
#   * XNAT credentials read from a Kubernetes Secret at spawn time, never from
#     values; by default the AIS XNAT chart's own admin Secret;
#   * the plugin's per-server path (default server: /server/user-options);
#     404 = not launched through XNAT (e.g. a direct hub login) -> chart
#     defaults; other failures fail the spawn unless failOpen is set;
#   * XNAT resource requests are MERGED into the chart's (so the FUSE device
#     request survives), and 'fuse'/'gpu' are mapped to their device names;
#   * archive mounts must lie under the archive PVC's XNAT path and become
#     subPaths relative to it; anything else is refused. A pod that gets one
#     also gets XNAT's group (archiveGid) as a supplemental group, because XNAT
#     writes the archive 0750/0640 as 65534:65534 and notebooks run as 1000;
#   * the same data also appears under <home>/xnat-data (JupyterLab's file
#     browser only shows the home), and JupyterLab opens there;
#   * no allow_privilege_escalation: Neurodesk images run without it;
#   * every image works in the user's home volume (homeMountPath), not in
#     XNAT's /workspace/<user>, which is not mounted.
import asyncio
import base64
import json
import os
import re
from urllib.parse import quote

_NDI_CONFIG = "/etc/neurodesk/integration/integration.json"
# task_template.resources keys XNAT sends, and the KubeSpawner traits they set.
# Anything else is ignored: it must never reach the pod spec.
_NDI_RESOURCES = {"cpu_limit": "cpu_limit", "cpu_reservation": "cpu_guarantee",
                  "mem_limit": "mem_limit", "mem_reservation": "mem_guarantee"}
_NDI_DEVICES = {"gpu": "nvidia.com/gpu", "fuse": "smarter-devices/fuse"}
# An extended resource (<domain>/<name>), outside the kubernetes.io domains.
_NDI_EXTENDED = re.compile(r"^(?![^/]*kubernetes\.io/)[a-z0-9]([-a-z0-9.]*[a-z0-9])?/[A-Za-z0-9]([-A-Za-z0-9_.]*[A-Za-z0-9])?$")


def _ndi_load():
    try:
        with open(_NDI_CONFIG) as f:
            return json.load(f)
    except (FileNotFoundError, ValueError):
        return {}


async def _ndi_xnat_credentials(xcfg):
    from kubernetes_asyncio import client, config

    config.load_incluster_config()
    async with client.ApiClient() as api:
        secret = await client.CoreV1Api(api).read_namespaced_secret(
            xcfg["credentialsSecret"], xcfg["namespace"])
    data = secret.data or {}
    user = base64.b64decode(data[xcfg.get("usernameKey", "username")]).decode()
    password = base64.b64decode(data[xcfg.get("passwordKey", "password")]).decode()
    return user, password


def _ndi_as_list(value):
    if isinstance(value, dict):
        return list(value.values())
    return list(value or [])


def _ndi_view_path(home, target):
    # /data/projects/P/experiments/S -> <home>/xnat-data/P/experiments/S.
    # None when the target is already inside the home.
    norm = os.path.normpath("/" + target.lstrip("/"))
    if norm == home or norm.startswith(home + "/"):
        return None
    parts = [p for p in norm.split("/") if p]
    for lead in (["data", "projects"], ["data", "xnat", "archive"], ["data", "xnat"], ["data"]):
        if parts[:len(lead)] == lead:
            parts = parts[len(lead):]
            break
    return "/".join([home, "xnat-data"] + parts)


def _ndi_add_group(spawner, gid):
    # A securityContext in extra_pod_config (the chart sets one for AppArmor)
    # REPLACES the pod securityContext KubeSpawner builds, supplemental_gids
    # included, so the group has to go where the securityContext comes from.
    pod_cfg = dict(spawner.extra_pod_config or {})
    if "securityContext" in pod_cfg:
        sc = dict(pod_cfg["securityContext"] or {})
        groups = list(sc.get("supplementalGroups") or [])
        if gid not in groups:
            sc["supplementalGroups"] = groups + [gid]
        pod_cfg["securityContext"] = sc
        spawner.extra_pod_config = pod_cfg
    else:
        gids = list(spawner.supplemental_gids or [])
        if gid not in gids:
            spawner.supplemental_gids = gids + [gid]


def _ndi_apply_user_options(spawner, xcfg, options):
    task = options.get("task_template") or {}

    constraints = (task.get("placement") or {}).get("constraints") or []
    if constraints:
        selector = dict(spawner.node_selector or {})
        for c_ in constraints:
            key, _, val = c_.partition("==")
            selector[key.strip()] = val.strip()
        spawner.node_selector = selector

    resources = dict(task.get("resources") or {})
    for key, trait in _NDI_RESOURCES.items():
        if resources.get(key):
            setattr(spawner, trait, resources[key])
    devices = {}
    for key, count in dict(resources.get("generic_resources") or {}).items():
        name = _NDI_DEVICES.get(key, key)
        if not _NDI_EXTENDED.match(name) or not re.fullmatch(r"[1-9][0-9]{0,3}", str(count).strip()):
            spawner.log.warning("ignoring XNAT generic resource %r=%r (not a device count)", key, count)
            continue
        devices[name] = str(count).strip()
    if devices:
        spawner.extra_resource_guarantees = {**(spawner.extra_resource_guarantees or {}), **devices}
        spawner.extra_resource_limits = {**(spawner.extra_resource_limits or {}), **devices}
    unknown = sorted(set(resources) - set(_NDI_RESOURCES) - {"generic_resources"})
    if unknown:
        spawner.log.warning("ignoring unknown XNAT resource keys: %s", ", ".join(unknown))

    spec = task.get("container_spec") or {}
    if not spec:
        return
    image = spec.get("image", "")
    neurodesk = "neurodesk" in image
    if image:
        spawner.image = image
        spawner.image_pull_policy = "IfNotPresent"
    if spec.get("command"):
        spawner.cmd = spec["command"].split(" ")
    env = dict(spec.get("env") or {})
    # JupyterHub's own variables (API token, URLs, ...) are the hub's to set.
    hub_vars = sorted(k for k in env if str(k).startswith("JUPYTERHUB_"))
    for k in hub_vars:
        env.pop(k)
    # XNAT points the root dir at its workspace mount (/workspace/<user>), which
    # is not mounted here: the user's home volume is the workspace, for every
    # image. Without this a non-Neurodesk server dies with "No such notebook dir".
    home = os.path.normpath(xcfg.get("homeMountPath") or "/home/jovyan")
    env.update({"JUPYTERHUB_ROOT_DIR": home, "XDG_CONFIG_HOME": home})
    spawner.working_dir = home
    if neurodesk:
        env.update({
            "NB_USER": "jovyan",
            "NB_UID": "1000",
            "NB_GID": "100",
            "JUPYTERHUB_COOKIE_HOST_PREFIX_ENABLED": "0",
        })
    else:
        env.update({
            "NB_USER": spawner.user.name,
            "NB_UID": str(xcfg.get("uid", 1000)),
            "NB_GID": str(xcfg.get("gid", 100)),
            # Cookie auth is not persisted from a token in a URL-authenticated
            # request otherwise (XNAT opens the server with a token in the URL).
            "JUPYTERHUB_SINGLEUSER_EXTENSION": "0",
        })
    spawner.environment = {**(spawner.environment or {}), **env}

    prefix = xcfg.get("archiveMountPath", "/data/xnat/archive").rstrip("/") + "/"
    volumes = _ndi_as_list(spawner.volumes)
    mounts = _ndi_as_list(spawner.volume_mounts)
    added = False
    views = []
    for m in spec.get("mounts") or []:
        src, tgt = m.get("source", ""), m.get("target", "")
        if not src or not tgt or "/workspaces/" in src:
            continue  # workspaces are the user's home volume, not XNAT's
        src = os.path.normpath(src)  # no ".." past the prefix check
        if not src.startswith(prefix):
            spawner.log.warning("refusing XNAT mount outside the archive (%s): %s", prefix, src)
            continue
        sub = src[len(prefix):]
        if not any(x.get("mountPath") == tgt for x in mounts):
            mounts.append({"name": "xnat-archive", "mountPath": tgt,
                           "subPath": sub, "readOnly": bool(m.get("read_only", True))})
        # JupyterLab's file browser only shows the root dir (the home), so the
        # same data also appears under <home>/xnat-data/.
        view = _ndi_view_path(home, tgt)
        if view:
            if not any(x.get("mountPath") == view for x in mounts):
                mounts.append({"name": "xnat-archive", "mountPath": view,
                               "subPath": sub, "readOnly": True})
            views.append(view)
        added = True
    if views:
        # Open JupyterLab on the launched data (XNAT opens the server's root URL).
        rel = os.path.relpath(os.path.commonpath(views), home)
        spawner.default_url = "/lab/tree/" + quote(rel, safe="/")
    if added and not any(v.get("name") == "xnat-archive" for v in volumes):
        volumes.append({"name": "xnat-archive",
                        "persistentVolumeClaim": {"claimName": xcfg["archivePvc"], "readOnly": True}})
    if added:
        _ndi_add_group(spawner, int(xcfg.get("archiveGid", 65534)))
    spawner.volumes = volumes
    spawner.volume_mounts = mounts


def _ndi_xnat_hook(previous_hook):
    async def neurodesk_xnat_pre_spawn_hook(spawner):
        if previous_hook is not None:
            result = previous_hook(spawner)
            if hasattr(result, "__await__"):
                await result
        xcfg = _ndi_load().get("xnat")
        if not xcfg:
            return
        from tornado.httpclient import AsyncHTTPClient, HTTPRequest

        # XNAT JupyterHub plugin 1.3: /server/user-options for the default
        # server, /server/<name>/user-options for a named one. (An empty name in
        # the second form, "/server//user-options", makes XNAT answer HTTP 500.)
        base = "{}/xapi/jupyterhub/users/{}/server".format(
            xcfg["url"].rstrip("/"), quote(spawner.user.name, safe=""))
        url = base + ("/" + quote(spawner.name, safe="") if spawner.name else "") + "/user-options"
        timeout = float(xcfg.get("requestTimeoutSeconds", 10))

        async def fetch():
            user, password = await _ndi_xnat_credentials(xcfg)
            return await AsyncHTTPClient().fetch(
                HTTPRequest(url, auth_username=user, auth_password=password,
                            connect_timeout=timeout, request_timeout=timeout),
                raise_error=False)

        try:
            # One deadline for the Secret read and the XNAT request together.
            resp = await asyncio.wait_for(fetch(), timeout)
            code, body = resp.code, resp.body
        except asyncio.TimeoutError:
            code, body = None, ("no answer within %gs (Secret read + XNAT request)" % timeout).encode()
        except Exception as e:  # network, DNS, Secret or RBAC problems
            code, body = None, str(e).encode()
        if code == 200:
            try:
                options = json.loads(body)
            except ValueError:
                options = None
            if isinstance(options, dict):
                _ndi_apply_user_options(spawner, xcfg, options)
                spawner.log.info("applied XNAT launch options for %s/%s", spawner.user.name, spawner.name)
                return
            # e.g. an HTML page: XNAT without its JupyterHub plugin
            code = "200 without JSON (is XNAT's JupyterHub plugin installed?)"
        if code == 404:
            spawner.log.info("no XNAT launch options for %s/%s; using chart defaults",
                          spawner.user.name, spawner.name)
            return
        msg = "XNAT user-options for {}/{} failed: {} {}".format(
            spawner.user.name, spawner.name, code, (body or b"")[:200].decode(errors="replace"))
        if xcfg.get("failOpen"):
            spawner.log.warning("%s (failOpen: spawning with chart defaults)", msg)
            return
        raise RuntimeError(msg)

    return neurodesk_xnat_pre_spawn_hook


def _ndi_setup_aaf(acfg):
    from oauthenticator.generic import GenericOAuthenticator

    prefix = acfg.get("usernamePrefix", "aaf_")

    class AAFOAuthenticator(GenericOAuthenticator):
        # XNAT's OpenID plugin names AAF users <provider>_<claim>, and its
        # JupyterHub plugin addresses the hub by that exact XNAT username. The
        # hub username must be identical or XNAT-launched servers belong to a
        # different hub user (403). So: prefix as XNAT does, and keep the case
        # (JupyterHub's default normaliser lowercases; ais-devstack drops that
        # for the same reason).
        def normalize_username(self, username):
            if prefix and not username.startswith(prefix):
                username = prefix + username
            return self.username_map.get(username, username)

    c.JupyterHub.authenticator_class = AAFOAuthenticator
    base = acfg.get("issuer", "https://central.aaf.edu.au").rstrip("/")
    c.AAFOAuthenticator.login_service = acfg.get("loginService", "AAF")
    c.AAFOAuthenticator.client_id = acfg["clientId"]
    c.AAFOAuthenticator.client_secret = os.environ.get("NEURODESK_AAF_CLIENT_SECRET", "")
    c.AAFOAuthenticator.oauth_callback_url = acfg["callbackUrl"]
    c.AAFOAuthenticator.authorize_url = base + "/providers/op/authorize"
    c.AAFOAuthenticator.token_url = base + "/providers/op/token"
    c.AAFOAuthenticator.userdata_url = base + "/providers/op/userinfo"
    c.AAFOAuthenticator.scope = acfg.get("scope", ["openid", "profile", "email"])
    c.AAFOAuthenticator.username_claim = acfg.get("usernameClaim", "sub")
    # oauthenticator >= 16 admits nobody without an allow rule.
    c.AAFOAuthenticator.allow_all = bool(acfg.get("allowAll", True))


_ndi = _ndi_load()
if _ndi.get("aaf"):
    _ndi_setup_aaf(_ndi["aaf"])
if _ndi.get("xnat"):
    # XNAT launches (timestamped) named servers.
    c.JupyterHub.allow_named_servers = True
    _prev = c.KubeSpawner.pre_spawn_hook if "pre_spawn_hook" in c.KubeSpawner else None
    c.KubeSpawner.pre_spawn_hook = _ndi_xnat_hook(_prev)
