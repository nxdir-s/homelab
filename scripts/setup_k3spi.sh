#!/usr/bin/env bash

set -o errexit

kubectl taint nodes jetson gpu=true:NoSchedule
kubectl label node jetson node-role.kubernetes.io/worker=
kubectl label node jetson node-role.kubernetes.io/gpu=

kubectl label nodes k3s1 k3s2 jetson node-role.kubernetes.io/kafka=
kubectl label nodes k3s1 k3s2 k3s3 node-role.kubernetes.io/postgres=
kubectl label nodes k3s1 k3s2 k3s3 node-role.kubernetes.io/cpu=

kubectl apply -f secrets/cf-api-key.yaml
kubectl apply -f secrets/cf-email.yaml

kubectl create namespace cert-manager
kubectl create namespace longhorn-system
kubectl create namespace kafka

kubectl apply -f secrets/cf-api-key.yaml -n cert-manager

kubectl create secret generic basic-auth --from-file=secrets/auth -n longhorn-system

kubectl apply -f https://github.com/grafana/alloy-operator/releases/latest/download/collectors.grafana.com_alloy.yaml

helm install grafana grafana/k8s-monitoring --namespace grafana --create-namespace --values secrets/grafana.yaml

flux bootstrap github \
  --token-auth \
  --owner=nxdir-s \
  --repository=homelab \
  --branch=main \
  --path=clusters/k3spi \
  --personal

