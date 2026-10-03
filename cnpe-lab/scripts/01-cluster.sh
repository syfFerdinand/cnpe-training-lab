#!/usr/bin/env bash
set -euo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
sed "s#__LAB_DIR__#$LAB_DIR#g" "$LAB_DIR/kind/kind-config.yaml" > /tmp/cnpe-kind.yaml
# KIND_NODE_IMAGE=kindest/node:v1.35.0 ./scripts/01-cluster.sh  (pour coller à la version de l'examen)
kind create cluster --config /tmp/cnpe-kind.yaml ${KIND_NODE_IMAGE:+--image "$KIND_NODE_IMAGE"}
kubectl config use-context kind-cnpe

echo ">> audit logging"
"$LAB_DIR/scripts/patch-apiserver-audit.sh"

echo ">> metrics-server (nécessaire pour HPA / kubectl top)"
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s
echo "Cluster prêt. Suite : ./scripts/02-install-platform.sh"
