#!/usr/bin/env bash
PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

semver="$1"
chart_yml=(
 ./Chart.yaml
 ./charts/xnat-web/Chart.yaml
)

for f in "${chart_yml[@]}"; do
	sed -i "s/^version: .*$/version: ${semver}/" "${f}"
done
