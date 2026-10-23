"""Rendered wiring between this chart and z2jh's hub, for every way z2jh
lets you name things:

- the XNAT-credentials RoleBinding names the ServiceAccount the hub Deployment
  actually runs as;
- the hub-reload hook patches the hub Deployment that actually exists, and its
  fingerprint changes whenever what the hub reads at start-up changes.

Needs helm on PATH and PyYAML. Run: python ci/test_hub_render.py
"""
import json
import subprocess
import sys

import yaml

BASE = ["--api-versions", "cert-manager.io/v1/Certificate",
        "--set", "xnat.enabled=true", "--set", "xnat.jupyterhub.enabled=true"]
CASES = {
    "defaults": [],
    "serviceAccount.create=false": ["--set", "jupyterhub.hub.serviceAccount.create=false"],
    "serviceAccount.name": ["--set", "jupyterhub.hub.serviceAccount.name=my-hub-sa"],
    "create=false + name": ["--set", "jupyterhub.hub.serviceAccount.create=false",
                            "--set", "jupyterhub.hub.serviceAccount.name=shared-sa"],
    "fullnameOverride=null": ["--set", "jupyterhub.fullnameOverride=null"],
    "fullnameOverride=nd": ["--set", "jupyterhub.fullnameOverride=nd"],
}


def render(extra, release="rel"):
    out = subprocess.run(["helm", "template", release, ".", "-n", "ns"] + BASE + extra,
                         check=True, capture_output=True, text=True).stdout
    return [d for d in yaml.safe_load_all(out) if d]


def reload_patch(docs):
    job = [d for d in docs if d["kind"] == "Job" and d["metadata"]["name"].endswith("-hub-reload")][0]
    args = job["spec"]["template"]["spec"]["initContainers"][0]["args"]
    target = args[args.index("deployment") + 1]
    stamp = json.loads(args[args.index("-p") + 1])["spec"]["template"]["metadata"]["annotations"]
    return target, stamp["neurodesk.org/hub-integration"]


AAF = ["--set", "auth.aaf.enabled=true", "--set", "auth.aaf.callbackUrl=https://h/hub/oauth_callback"]


def main():
    failures = 0
    for name, extra in CASES.items():
        docs = render(extra)
        hub = [d for d in docs if d["kind"] == "Deployment"
               and d["spec"]["template"]["metadata"]["labels"].get("component") == "hub"]
        rb = [d for d in docs if d["kind"] == "RoleBinding"
              and d["metadata"]["name"].endswith("-xnat-credentials")]
        sas = {d["metadata"]["name"] for d in docs if d["kind"] == "ServiceAccount"}
        actual = hub[0]["spec"]["template"]["spec"].get("serviceAccountName") or "default"
        bound = rb[0]["subjects"][0]["name"]
        ok = actual == bound
        failures += not ok
        print("%s %-28s hub runs as %-16s binding -> %-16s (SA objects: %s)" % (
            "PASS" if ok else "FAIL", name, actual, bound, sorted(sas)))
        target, _ = reload_patch(docs)
        ok = target == hub[0]["metadata"]["name"]
        failures += not ok
        print("%s %-28s reload hook patches %s (hub Deployment %s)" % (
            "PASS" if ok else "FAIL", name, target, hub[0]["metadata"]["name"]))

    # The fingerprint must change with every setting the hub reads at start-up.
    variants = {
        "integrations off": ["--set", "xnat.jupyterhub.enabled=false"],
        "xnat on": [],
        "xnat timeout 20": ["--set", "xnat.jupyterhub.requestTimeoutSeconds=20"],
        "+aaf client a": AAF + ["--set", "auth.aaf.clientId=a"],
        "+aaf client b": AAF + ["--set", "auth.aaf.clientId=b"],
    }
    stamps = {k: reload_patch(render(v))[1] for k, v in variants.items()}
    ok = stamps["integrations off"] == "none" and len(set(stamps.values())) == len(stamps)
    failures += not ok
    print("%s reload fingerprint differs for every setting change: %s" % ("PASS" if ok else "FAIL", stamps))
    ok = reload_patch(render([]))[1] == stamps["xnat on"]
    failures += not ok
    print("%s reload fingerprint is stable for unchanged settings" % ("PASS" if ok else "FAIL"))

    # The reload must also run on rollback, and every hook object with it.
    docs = render([])
    events = {d["kind"]: d["metadata"]["annotations"]["helm.sh/hook"] for d in docs
              if d["metadata"]["name"].endswith("-hub-reload")}
    ok = len(events) == 4 and all(set(v.split(",")) == {"post-upgrade", "post-rollback"} for v in events.values())
    failures += not ok
    print("%s reload hook objects run on post-upgrade and post-rollback: %s" % ("PASS" if ok else "FAIL", events))
    print("\n%d failure(s)" % failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
