# monai-label AIS chart

```bash
helm upgrade monai-label ./monai-label -i -n monai --create-namespace
```

## Applications

Adding MONAI Label applications can be accomplished in several ways.
1. Add the applications directly within a purpose build container.
2. Mount a pre-configured volume containing the MONAI Label applications via the `volumes` and
   `volumeMounts` settings. Ensure the `volumeMounts.mountPath` is under the configured `appDir` path.

## Datasets

## Studies
