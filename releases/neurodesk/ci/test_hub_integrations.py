"""Offline tests for files/hub/neurodesk_integrations.py.

Runs the module the way the hub does (exec with a traitlets config `c`), with a
stub spawner and a local tornado HTTP server standing in for XNAT. Needs:
    pip install tornado traitlets oauthenticator
Run: python ci/test_hub_integrations.py
"""
import asyncio
import json
import logging
import os
import sys
import tempfile
import types

from tornado import web
from tornado.httpserver import HTTPServer
from tornado.netutil import bind_sockets
from traitlets.config import Config

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.join(HERE, "..", "files", "hub", "neurodesk_integrations.py")


def load(cfg):
    """exec the module with integration.json = cfg; return (namespace, c)."""
    d = tempfile.mkdtemp()
    path = os.path.join(d, "integration.json")
    with open(path, "w") as f:
        json.dump(cfg, f)
    src = open(MODULE).read().replace(
        '"/etc/neurodesk/integration/integration.json"', repr(path))
    c = Config()
    ns = {"c": c}
    exec(compile(src, MODULE, "exec"), ns)
    return ns, c


class Spawner:
    def __init__(self, user="aaf_alice", name="xnat-1"):
        self.user = types.SimpleNamespace(name=user)
        self.name = name
        self.node_selector = {"kubernetes.io/os": "linux"}
        self.extra_resource_guarantees = {"smarter-devices/fuse": "1"}
        self.extra_resource_limits = {"smarter-devices/fuse": "1"}
        self.extra_pod_config = {}
        self.environment = {}
        self.volumes = {"cvmfs": {"name": "cvmfs", "persistentVolumeClaim": {"claimName": "cvmfs"}}}
        self.volume_mounts = {"cvmfs": {"name": "cvmfs", "mountPath": "/cvmfs"}}
        self.image = "ghcr.io/neurodesk/neurodesktop:default"
        self.supplemental_gids = []
        self.default_url = "/lab"
        self.log = logging.getLogger("spawner")


OPTIONS = {"task_template": {
    "placement": {"constraints": ["node.kubernetes.io/instance-type==big"]},
    # plus fields that are NOT hardware: they must never reach the pod spec
    "resources": {"cpu_limit": 4, "mem_limit": "8G",
                  "generic_resources": {"gpu": 1, "cpu": 64, "kubernetes.io/x": 1, "example.org/fpga": "two"},
                  "hostNetwork": True, "serviceAccountName": "hub",
                  "securityContext": {"appArmorProfile": {"type": "Unconfined"}}},
    "container_spec": {
        "image": "ghcr.io/neurodesk/neurodesktop:2026-09-23",
        "env": {"XNAT_HOST": "http://ais-xnat-web", "JUPYTERHUB_ROOT_DIR": "/workspace/aaf_alice",
                "JUPYTERHUB_API_TOKEN": "not-from-xnat"},
        "mounts": [
            {"source": "/data/xnat/archive/P1/arc001/S1", "target": "/data/projects/P1/experiments/S1", "read_only": True},
            {"source": "/data/xnat/workspaces/users/alice", "target": "/workspace", "read_only": False},
            {"source": "/etc", "target": "/host-etc", "read_only": True},
            {"source": "/data/xnat/archive/../../../etc", "target": "/data/projects/escape", "read_only": True},
        ]}}}


class Handler(web.RequestHandler):
    def initialize(self, mode):
        self.mode = mode

    async def get(self, user, server):
        seen.append((user, server, self.request.headers.get("Authorization", "")))
        if self.mode == "ok":
            self.write(OPTIONS)
        elif self.mode == "plain":
            opts = json.loads(json.dumps(OPTIONS))
            opts["task_template"]["container_spec"]["image"] = "quay.io/jupyter/base-notebook:hub-5.4.3"
            self.write(opts)
        elif self.mode == "missing":
            self.set_status(404)
        elif self.mode == "hang":
            await asyncio.sleep(5)
        elif self.mode == "html":
            self.write("<!DOCTYPE html><html>login</html>")
        else:
            self.set_status(500)


seen = []


class Bad(web.RequestHandler):
    # real XNAT answers the malformed empty-name path with HTTP 500
    def get(self, user):
        bad.append(user)
        self.set_status(500)


bad = []


async def serve(mode):
    socks = bind_sockets(0, "127.0.0.1")
    app = web.Application([
        (r"/xapi/jupyterhub/users/([^/]+)/server/([^/]+)/user-options", Handler, {"mode": mode}),
        (r"/xapi/jupyterhub/users/([^/]+)/server()/user-options", Handler, {"mode": mode}),
        (r"/xapi/jupyterhub/users/([^/]+)/server//user-options", Bad),
    ])
    srv = HTTPServer(app)
    srv.add_sockets(socks)
    return srv, socks[0].getsockname()[1]


def xcfg(port, **kw):
    base = {"url": "http://127.0.0.1:%d" % port, "namespace": "ns", "credentialsSecret": "s",
            "archivePvc": "ais-xnat-web-archive", "archiveMountPath": "/data/xnat/archive",
            "uid": 1000, "gid": 100, "requestTimeoutSeconds": 1, "failOpen": False}
    base.update(kw)
    return base


async def run_hook(ns, c, sp):
    async def creds(_):
        return ("svc", "pw")
    ns["_ndi_xnat_credentials"] = creds
    return await c.KubeSpawner.pre_spawn_hook(sp)


async def main():
    failures = []

    def check(name, cond):
        print(("PASS " if cond else "FAIL ") + name)
        if not cond:
            failures.append(name)

    # 1. success path
    srv, port = await serve("ok")
    ns, c = load({"xnat": xcfg(port)})
    check("named servers enabled", c.JupyterHub.allow_named_servers is True)
    sp = Spawner()
    await run_hook(ns, c, sp)
    check("request uses user and server name", seen and seen[-1][:2] == ("aaf_alice", "xnat-1"))
    check("basic auth sent", seen and seen[-1][2].startswith("Basic "))
    check("image applied", sp.image.endswith(":2026-09-23"))
    check("node selector merged", sp.node_selector == {"kubernetes.io/os": "linux", "node.kubernetes.io/instance-type": "big"})
    check("fuse kept + gpu mapped", sp.extra_resource_limits == {"smarter-devices/fuse": "1", "nvidia.com/gpu": "1"})
    check("non-device generic resources ignored", set(sp.extra_resource_guarantees) == {"smarter-devices/fuse", "nvidia.com/gpu"})
    check("unknown resource keys never reach the pod spec", sp.extra_pod_config == {})
    check("XNAT cannot set JupyterHub's own variables", "JUPYTERHUB_API_TOKEN" not in sp.environment)
    check("cpu/mem applied", sp.cpu_limit == 4 and sp.mem_limit == "8G")
    mounts = sp.volume_mounts
    arch = [m for m in mounts if m["name"] == "xnat-archive"]
    check("archive mounted as relative subPath, and again under the JupyterLab root", arch == [
        {"name": "xnat-archive", "mountPath": "/data/projects/P1/experiments/S1", "subPath": "P1/arc001/S1", "readOnly": True},
        {"name": "xnat-archive", "mountPath": "/home/jovyan/xnat-data/P1/experiments/S1", "subPath": "P1/arc001/S1", "readOnly": True}])
    check("JupyterLab opens on the launched data", sp.default_url == "/lab/tree/xnat-data/P1/experiments/S1")
    check("workspace, outside-archive and '..' mounts refused", not any(m["mountPath"] in ("/workspace", "/host-etc", "/data/projects/escape") for m in mounts) and not any(".." in m.get("subPath", "") for m in mounts))
    check("existing cvmfs mount kept", any(m["name"] == "cvmfs" for m in mounts))
    check("archive volume added once", [v["name"] for v in sp.volumes].count("xnat-archive") == 1)
    check("XNAT group added for archive reads", sp.supplemental_gids == [65534])
    check("neurodesk env", sp.environment.get("NB_USER") == "jovyan" and sp.environment.get("XNAT_HOST") == "http://ais-xnat-web")
    check("no privilege escalation set", not hasattr(sp, "allow_privilege_escalation"))
    check("root dir is the home mount, not XNAT's workspace", sp.environment.get("JUPYTERHUB_ROOT_DIR") == "/home/jovyan" and sp.working_dir == "/home/jovyan")
    await run_hook(ns, c, sp)  # respawn: no duplicates
    check("respawn does not duplicate mounts", [m["name"] for m in sp.volume_mounts].count("xnat-archive") == 2)
    check("respawn does not duplicate the group", sp.supplemental_gids == [65534])
    srv.stop()

    # 1b. non-Neurodesk image: XNAT user name, hub extension off, home as root dir
    srv, port = await serve("plain")
    ns, c = load({"xnat": xcfg(port, homeMountPath="/home/work")})
    sp = Spawner()
    await run_hook(ns, c, sp)
    env = sp.environment
    check("non-Neurodesk image applied", sp.image == "quay.io/jupyter/base-notebook:hub-5.4.3")
    check("non-Neurodesk env", env.get("NB_USER") == "aaf_alice" and env.get("NB_UID") == "1000" and env.get("JUPYTERHUB_SINGLEUSER_EXTENSION") == "0")
    check("non-Neurodesk root dir = homeMountPath", env.get("JUPYTERHUB_ROOT_DIR") == "/home/work" and env.get("XDG_CONFIG_HOME") == "/home/work" and sp.working_dir == "/home/work")
    srv.stop()

    # 2. 404 -> chart defaults
    srv, port = await serve("missing")
    ns, c = load({"xnat": xcfg(port)})
    sp = Spawner(name="xnat-2")
    await run_hook(ns, c, sp)
    check("404 keeps chart defaults", sp.image.endswith(":default") and sp.supplemental_gids == [])
    srv.stop()

    # 2a. chart securityContext in extra_pod_config: group merged there, since it
    # replaces the pod securityContext (and with it supplemental_gids)
    srv, port = await serve("ok")
    ns, c = load({"xnat": xcfg(port)})
    sp = Spawner()
    chart_sc = {"fsGroup": 100, "appArmorProfile": {"type": "Localhost", "localhostProfile": "notebook"}}
    sp.extra_pod_config = {"securityContext": chart_sc}
    await run_hook(ns, c, sp)
    sc = sp.extra_pod_config["securityContext"]
    check("group merged into extraPodConfig securityContext", sc.get("supplementalGroups") == [65534] and sc.get("fsGroup") == 100 and "appArmorProfile" in sc)
    check("chart securityContext dict not mutated", "supplementalGroups" not in chart_sc)
    await run_hook(ns, c, sp)
    check("respawn keeps one group", sp.extra_pod_config["securityContext"]["supplementalGroups"] == [65534])
    srv.stop()

    # 2b. default server uses /server/user-options (never /server//user-options)
    srv, port = await serve("missing")
    ns, c = load({"xnat": xcfg(port)})
    before = len(seen)
    sp = Spawner(name="")
    await run_hook(ns, c, sp)
    check("default server: /server/user-options, 404 -> defaults", len(seen) == before + 1 and seen[-1][1] == "" and not bad and sp.image.endswith(":default"))
    srv.stop()
    srv, port = await serve("ok")
    ns, c = load({"xnat": xcfg(port)})
    sp = Spawner(name="")
    await run_hook(ns, c, sp)
    check("default server launched by XNAT gets XNAT options", sp.image.endswith(":2026-09-23") and not bad)
    srv.stop()

    # 3. 500 -> fail closed; failOpen -> defaults
    srv, port = await serve("error")
    ns, c = load({"xnat": xcfg(port)})
    try:
        await run_hook(ns, c, Spawner())
        check("500 fails the spawn", False)
    except RuntimeError:
        check("500 fails the spawn", True)
    ns, c = load({"xnat": xcfg(port, failOpen=True)})
    sp = Spawner()
    await run_hook(ns, c, sp)
    check("500 with failOpen spawns defaults", sp.image.endswith(":default"))
    srv.stop()

    # 3b. 200 but not JSON (XNAT without the plugin) -> clear failure
    srv, port = await serve("html")
    ns, c = load({"xnat": xcfg(port)})
    try:
        await run_hook(ns, c, Spawner())
        check("200 HTML fails with a clear message", False)
    except RuntimeError as e:
        check("200 HTML fails with a clear message", "plugin installed" in str(e))
    srv.stop()

    # 4. hung XNAT -> timeout, not a stall
    srv, port = await serve("hang")
    ns, c = load({"xnat": xcfg(port)})
    t = asyncio.get_event_loop().time()
    try:
        await run_hook(ns, c, Spawner())
        check("hung XNAT times out", False)
    except RuntimeError:
        check("hung XNAT times out (<3s)", asyncio.get_event_loop().time() - t < 3)
    srv.stop()

    # 4b. a hanging Secret read is inside the same deadline
    srv, port = await serve("ok")
    ns, c = load({"xnat": xcfg(port)})

    async def slow_creds(_):
        await asyncio.sleep(5)
    ns["_ndi_xnat_credentials"] = slow_creds
    t = asyncio.get_event_loop().time()
    try:
        await c.KubeSpawner.pre_spawn_hook(Spawner())
        check("hung Secret read times out", False)
    except RuntimeError as e:
        check("hung Secret read times out (<3s)", asyncio.get_event_loop().time() - t < 3 and "no answer" in str(e))
    srv.stop()

    # 5. chaining with an existing hook
    calls = []
    d = tempfile.mkdtemp()
    path = os.path.join(d, "integration.json")
    srv, port = await serve("missing")
    with open(path, "w") as f:
        json.dump({"xnat": xcfg(port)}, f)
    src = open(MODULE).read().replace('"/etc/neurodesk/integration/integration.json"', repr(path))
    c = Config()
    c.KubeSpawner.pre_spawn_hook = lambda s: calls.append(s.name)
    ns = {"c": c}
    exec(compile(src, MODULE, "exec"), ns)
    await run_hook(ns, c, Spawner())
    check("previous pre_spawn_hook still runs", calls == ["xnat-1"])
    srv.stop()

    # 6. nothing configured -> no hook, no named-server change
    ns, c = load({})
    check("no config: no hook installed", "pre_spawn_hook" not in c.KubeSpawner)

    # 7. AAF preset
    try:
        import oauthenticator  # noqa: F401
        os.environ["NEURODESK_AAF_CLIENT_SECRET"] = "x"
        ns, c = load({"aaf": {"clientId": "cid", "callbackUrl": "https://hub.example/hub/oauth_callback"}})
        cls = c.JupyterHub.authenticator_class
        check("AAF authenticator class set", getattr(cls, "__name__", "") == "AAFOAuthenticator")
        check("AAF endpoints", c.AAFOAuthenticator.authorize_url == "https://central.aaf.edu.au/providers/op/authorize")
        check("AAF logins allowed by default", c.AAFOAuthenticator.allow_all is True)
        auth = cls(config=c)
        check("AAF username prefixed, case kept (must equal XNAT's)", auth.normalize_username("Abc123") == "aaf_Abc123")
        check("AAF username not double-prefixed", auth.normalize_username("aaf_abc") == "aaf_abc")
    except ImportError:
        print("SKIP AAF (oauthenticator not installed)")

    print("\n%d failure(s)" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
