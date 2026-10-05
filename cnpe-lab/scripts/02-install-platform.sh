#!/usr/bin/env bash
# Installe les briques "plateforme" (correctement). Les pannes sont injectées ensuite par 03-load-lab.sh.
# Désactivation : SKIP_ISTIO=1 SKIP_PROMETHEUS=1 SKIP_TEKTON=1 SKIP_ARGOCD=1 SKIP_ROLLOUTS=1 SKIP_KYVERNO=1 SKIP_GITEA=1
set -euo pipefail
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"

helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
helm repo add gitea-charts https://dl.gitea.com/charts/ >/dev/null
helm repo update >/dev/null

if [ -z "${SKIP_KYVERNO:-}" ]; then
  echo ">> Kyverno"
  helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace \
    --set admissionController.replicas=1 --set backgroundController.replicas=1 \
    --set cleanupController.replicas=1 --set reportsController.replicas=1 --wait --timeout 5m
fi

if [ -z "${SKIP_GITEA:-}" ]; then
  echo ">> Gitea (serveur Git interne pour les tâches GitOps)"
  helm upgrade --install gitea gitea-charts/gitea -n gitea --create-namespace \
    -f "$LAB_DIR/scripts/values/gitea.yaml" --wait --timeout 8m
fi

if [ -z "${SKIP_ARGOCD:-}" ]; then
  echo ">> Argo CD"
  helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
    --set dex.enabled=false --set notifications.enabled=false --set applicationSet.enabled=false \
    --wait --timeout 8m
fi

if [ -z "${SKIP_ROLLOUTS:-}" ]; then
  echo ">> Argo Rollouts"
  helm upgrade --install argo-rollouts argo/argo-rollouts -n argo-rollouts --create-namespace --wait --timeout 5m
fi

if [ -z "${SKIP_TEKTON:-}" ]; then
  echo ">> Tekton Pipelines"
  kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
  kubectl -n tekton-pipelines rollout status deploy/tekton-pipelines-controller --timeout=300s
  kubectl -n tekton-pipelines rollout status deploy/tekton-pipelines-webhook --timeout=300s
fi

if [ -z "${SKIP_PROMETHEUS:-}" ]; then
  echo ">> kube-prometheus-stack (release 'kps' : les CR doivent porter le label release=kps)"
  helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
    --set grafana.enabled=false --set alertmanager.enabled=false --set nodeExporter.enabled=false \
    --set defaultRules.create=false --set kubeEtcd.enabled=false --set kubeControllerManager.enabled=false \
    --set kubeScheduler.enabled=false --set kubeProxy.enabled=false --wait --timeout 10m
fi

if [ -z "${SKIP_ISTIO:-}" ]; then
  echo ">> Istio (mode sidecar)"
  helm upgrade --install istio-base istio/base -n istio-system --create-namespace --wait
  helm upgrade --install istiod istio/istiod -n istio-system --wait --timeout 8m
fi
echo "Plateforme installée. Suite : ./scripts/03-load-lab.sh"
