---
title: "microk8s-Ubuntu"
weight: 10
---
NB: [Ansible playbooks and/or roles](https://github.com/Australian-Imaging-Service/charts/contrib/ansible/) may be helpful.

## [microk8s](https://microk8s.io/)

```bash
sudo snap install microk8s --classic
microk8s enable dns fluentd ingress metrics-server prometheus rbac registry storage

# Install and configure the kubectl client
sudo snap install kubectl --classic
# Start running more than one cluster and you will be glad you did these steps
microk8s config |sed 's/\(user\|name\): admin/\1: microk8s-admin/' >${HOME}/.kube/microk8s.config
# On Mac, use below to set up the admin user
# microk8s config |sed 's/\([user\|name]\): admin/\1: microk8s-admin/' >${HOME}/.kube/microk8s.config
cat >>${HOME}/.profile <<'EOT'
DIR="${HOME}/.kube"
if [ -d "${DIR}" ]; then
  KUBECONFIG="$(/usr/bin/find $DIR \( -name 'config' -o -name '*.config' \) \( -type f -o -type l \) -print0 | tr '\0' ':')"
  KUBECONFIG="${KUBECONFIG%:}"
  export KUBECONFIG
fi
EOT
# logout or run the above code in your current shell to set the KUBECONFIG environment variable
kubectl config use-context microk8s
```

If you have an issue with the operation of microk8s `microk8s inspect` command is you best friend.

### microk8s notes

To enable a Load Balancer microk8s comes with [metalLB](https://metallb.universe.tf/) and configures [Layer2 mode](https://metallb.universe.tf/configuration/#layer-2-configuration) settings by default. You will be asked for an IPv4 block of addresses, ensure that the address block is in the same Layer 2 as your host, unused and reserved for this pupose (you may need to alter your DHCP service). When you are ready perform the following:

```console
$ microk8s enable metallb
```

* microk8s does not support IPv6 at this time!

