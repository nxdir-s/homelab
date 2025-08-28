#!/usr/bin/env bash

set -o errexit

k taint nodes jetson gpu=true:NoSchedule
k label node jetson node-role.kubernetes.io/worker=
k label node jetson node-role.kubernetes.io/gpu=

k label nodes k3s1 k3s2 jetson node-role.kubernetes.io/kafka=
k label nodes k3s1 k3s2 k3s3 node-role.kubernetes.io/postgres=
k label nodes k3s1 k3s2 k3s3 node-role.kubernetes.io/cpu=

k apply -f secrets/cf-api-key.yaml
k apply -f secrets/cf-email.yaml

k create namespace cert-manager
k create namespace longhorn-system
k create namespace kafka

k apply -f secrets/cf-api-key.yaml -n cert-manager

k create secret generic basic-auth --from-file=secrets/auth -n longhorn-system

k apply -f https://github.com/grafana/alloy-operator/releases/latest/download/collectors.grafana.com_alloy.yaml
helm install grafana grafana/k8s-monitoring --namespace grafana --create-namespace --values secrets/grafana.yaml

flux bootstrap github \
  --token-auth \
  --owner=nxdir-s \
  --repository=homelab \
  --branch=main \
  --path=clusters/k3spi \
  --personal

