"""Home PVC deletion policy, checked against KubeSpawner itself.

The chart shares one home per user (pvcNameTemplate claim-{username}) because
XNAT starts a new named server per launch and removes it when it stops; with a
per-server template KubeSpawner deletes that server's home on removal. This
runs KubeSpawner's own load_state/delete_forever (the version in z2jh 4.4.2) on
a stub spawner with the Kubernetes delete call recorded, not sent, and pins:

  1. the chart's template shares the home;
  2. removing a named server never deletes a shared home;
  3. a named server from before the switch keeps its remembered per-server
     PVC (it is still that server's home, and is not deleted either);
  4. the hazard docs/migration.md warns about: switching back to a
     {user_server} template deletes the SHARED home of a named server created
     while it was shared, unless delete_pvc is false.

Needs: pip install jupyterhub-kubespawner==7.1.0 pyyaml
Run: python ci/test_home_pvc_policy.py
"""
import asyncio
import logging
import os
import sys
import types

import yaml
from kubespawner import KubeSpawner

HERE = os.path.dirname(os.path.abspath(__file__))
VALUES = os.path.join(HERE, "..", "values.yaml")


def stub(template, remembered, delete_pvc=True, name="xnat-20260928"):
    deleted = []

    async def delete_request(pvc_name, timeout):
        deleted.append(pvc_name)
        return True

    sp = types.SimpleNamespace(
        user=types.SimpleNamespace(name="alice"), name=name,
        pvc_name_template=template, pvc_name=template.replace("{username}", "alice"),
        remember_pvc_name=True, delete_pvc=delete_pvc,
        k8s_api_request_timeout=3, k8s_api_request_retry_timeout=30,
        _make_delete_pvc_request=delete_request, log=logging.getLogger("kubespawner"))
    KubeSpawner.load_state(sp, {"pvc_name": remembered})
    return sp, deleted


async def main():
    failures = []

    def check(label, cond):
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            failures.append(label)

    template = yaml.safe_load(open(VALUES))["jupyterhub"]["singleuser"]["storage"]["dynamic"]["pvcNameTemplate"]
    check("chart template shares the home (%s)" % template,
          template == "claim-{username}" and "{user_server}" not in template)

    sp, deleted = stub(template, "claim-alice")
    await KubeSpawner.delete_forever(sp)
    check("removing a named server keeps the shared home", deleted == [])

    sp, deleted = stub(template, "claim-alice--analysis", name="analysis")
    check("pre-switch named server still mounts its own PVC", sp.pvc_name == "claim-alice--analysis")
    await KubeSpawner.delete_forever(sp)
    check("...and removing it does not delete that PVC", deleted == [])

    sp, deleted = stub("claim-{user_server}", "claim-alice")
    await KubeSpawner.delete_forever(sp)
    check("HAZARD pinned: switching back to {user_server} deletes the shared home", deleted == ["claim-alice"])

    sp, deleted = stub("claim-{user_server}", "claim-alice", delete_pvc=False)
    await KubeSpawner.delete_forever(sp)
    check("delete_pvc=false before switching back prevents it", deleted == [])

    print("\n%d failure(s)" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
