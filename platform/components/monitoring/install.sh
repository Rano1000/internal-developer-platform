#!/usr/bin/env bash
set -euo pipefail

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts

helm repo update prometheus-community

kubectl apply \
  --context kind-internal-developer-platform \
  -f platform/components/monitoring/namespace.yaml

kubectl get secret monitoring-grafana-admin \
  --namespace monitoring \
  --context kind-internal-developer-platform

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --version 92.2.0 \
  --namespace monitoring \
  --kube-context kind-internal-developer-platform \
  --values platform/components/monitoring/values.yaml \
  --wait \
  --timeout 15m
