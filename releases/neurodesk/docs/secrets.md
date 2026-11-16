# Secrets

**Never put secrets in `values.yaml`.** Values are committed to git, rendered
into ArgoCD diffs, and packaged into the OCI artifact — none of which should
contain credentials. The chart's defaults reflect this: every auth/credential
field defaults to `""` or a placeholder (`dummy` authenticator), and real values
are supplied out of band.

> ## ⚠️ GitOps / `helm template` rotation footgun — PIN your z2jh secrets
>
> z2jh **auto-generates** several secrets when you don't supply them:
> `proxy.secretToken`, `hub.cookieSecret`, the `CryptKeeper` keys, and
> `services.*.apiToken`. With a normal `helm install`/`upgrade` it persists them
> in the release. But under **GitOps/ArgoCD** or any
> **`helm template` / `helm diff` / `--dry-run`** run **without live cluster
> state**, there's nothing to read the previous values from, so they are
> **regenerated on every render**. Each sync then ships *different* secrets:
> hub↔proxy shared-token auth breaks (proxy 403s) and every user's login cookie
> is invalidated (forced re-login) on **each** reconcile.
>
> **Fix:** PIN them — supply each via `existingSecret` (or committed/sealed
> values) so the rendered output is stable across syncs. Do this for **any**
> GitOps or render-then-apply pipeline, not just production.

## How to supply secrets

Pick whichever your deployment already uses:

| Mechanism | Use it when | How |
| --- | --- | --- |
| **`existingSecret`** | z2jh and most subcharts support referencing a pre-created `Secret`. | Create the `Secret` (kubectl / your secrets pipeline), then point the chart at it by name. |
| **sealed-secrets** | You want encrypted secrets committed to git. | Seal the `Secret` with `kubeseal`; the controller decrypts it in-cluster. neurocloud uses this pattern. |
| **SOPS** | GitOps with age/KMS-encrypted files. | Decrypt at render/apply time; reference the resulting `Secret`. neurocloud keeps its `config/` + SOPS. |

You can also inject a pre-made `Secret` through the chart's `extraManifests`
escape hatch (e.g. a sealed/SOPS-managed object), keeping it inside the Helm
release — but **do not** inline plaintext secret material there either.

## Exactly which secrets each deployment needs

### JupyterHub (z2jh) — always

| Secret | Where it goes | Notes |
| --- | --- | --- |
| **`proxy.secretToken`** | z2jh `proxy.secretToken` | Shared token between Hub and configurable-http-proxy. Generate with `openssl rand -hex 32`. Use `existingSecret`, not a values literal. |
| **`hub.cookieSecret`** (`hub.config.JupyterHub.cookie_secret`) | z2jh hub | Signs login cookies. Generate with `openssl rand -hex 32`. |
| **`CryptKeeper` keys** (`hub.config.CryptKeeper.keys`) | z2jh hub | Encrypts auth state at rest. Auto-generated if unset. |
| **`services.*.apiToken`** | z2jh hub services (cull, etc.) | Per-service API tokens. Auto-generated if unset. |

z2jh can auto-generate all of these on first install if you don't pin them — but
under GitOps / `helm template` they **rotate on every render** and break
hub↔proxy auth and login cookies (see the warning at the top). For
reproducible/GitOps installs provide them via a pre-created `Secret` and
`existingSecret`.

### OAuth authentication — when you replace the `dummy` authenticator

| Secret | Where it goes | Notes |
| --- | --- | --- |
| **OAuth `client_secret`** | z2jh `hub.config.<Authenticator>.client_secret` (GitHub / generic OAuth / OIDC) | The matching `client_id` is *not* secret and may live in values; the `client_secret` must come from an `existingSecret`. |

The shipped default is `authenticator_class: dummy` with no secret — override in
your overlay (the neurocloud overlay uses GitHub; devstack its own).

### XNAT integration — only when `xnat.enabled=true`

| Secret | Where it lives | Notes |
| --- | --- | --- |
| **XNAT service `apiToken`** | referenced by the notebook integration | Token the upload extension authenticates to XNAT with. Supply via `existingSecret`. |
| **XNAT `CryptKeeper` keys** | the XNAT **server** (ais-devstack), not this chart | Server-side encryption keys. Stay in ais-devstack's secret store. |
| **XNAT admin / DB passwords** | the XNAT server (ais-devstack) | Server-side; never in this chart's values. |

## Placeholders you will see in `values.yaml`

These are intentionally blank/placeholder and must be overridden — they are
**not** working defaults:

- `jupyterhub.hub.config.JupyterHub.authenticator_class: dummy` — placeholder
  authenticator.
- `jupyterhub.ingress.annotations` `cert-manager.io/cluster-issuer: ""` — set to
  your cert-manager ClusterIssuer (not a secret, but required for TLS), alongside
  `jupyterhub.ingress.tls`.
- `xnat.server.host` / `xnat.server.namespace: ""` — set when enabling XNAT.

## Rule of thumb

If a field would let someone authenticate, decrypt, or impersonate, it does
**not** belong in `values.yaml`. Reference it from a `Secret` you manage with
`existingSecret` / sealed-secrets / SOPS. The chart never copies or templates
secret material across components.
