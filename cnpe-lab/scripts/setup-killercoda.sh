#!/usr/bin/env bash
# ==============================================================================
# Setup du lab CNPE sur Killercoda "Playground 2 Nodes" (controlplane + node01)
# Usage: ./scripts/setup-killercoda.sh <session>
#   Sessions: infra | gitops | platform | observability | security | base
# ==============================================================================
set -euo pipefail

SESSION=${1:-}
if [ -z "$SESSION" ]; then
  echo "Usage: $0 <infra|gitops|platform|observability|security|base>"
  exit 1
fi

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CALICO_VERSION=${CALICO_VERSION:-v3.28.2}
LPP_VERSION=${LPP_VERSION:-v0.0.31}

echo "============================================================"
echo " CNPE Lab Setup (Killercoda 2-Node) - Session: $SESSION"
echo "============================================================"

# 1. Vérifier que le cluster Killercoda est prêt
echo ">> [1/5] Vérification du cluster et des outils de base..."
kubectl get nodes >/dev/null 2>&1 || { echo "Erreur: kubectl ne répond pas."; exit 1; }
command -v jq >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq jq >/dev/null; }
command -v helm >/dev/null 2>&1 || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null

# 2. Remplacer Flannel par Calico si nécessaire (requis pour NetworkPolicy T02/T17)
if ! kubectl -n kube-system get ds calico-node >/dev/null 2>&1; then
  echo ">> [2/5] Installation de Calico (support NetworkPolicy)..."
  # Détecter le Pod CIDR du cluster Killercoda
  POD_CIDR=$(grep -oE 'cluster-cidr=[0-9./]+' /etc/kubernetes/manifests/kube-controller-manager.yaml 2>/dev/null | cut -d= -f2 || echo "10.244.0.0/16")
  [ -z "$POD_CIDR" ] && POD_CIDR="10.244.0.0/16"
  echo "   Pod CIDR détecté: $POD_CIDR"

  # Supprimer Flannel s'il est présent
  if kubectl -n kube-flannel get ds kube-flannel-ds >/dev/null 2>&1; then
    kubectl delete ns kube-flannel --wait=false >/dev/null 2>&1 || true
    rm -f /etc/cni/net.d/*flannel* || true
    ssh -o StrictHostKeyChecking=no node01 "rm -f /etc/cni/net.d/*flannel*" >/dev/null 2>&1 || true
  elif kubectl -n kube-system get ds kube-flannel-ds >/dev/null 2>&1; then
    kubectl -n kube-system delete ds kube-flannel-ds >/dev/null 2>&1 || true
    rm -f /etc/cni/net.d/*flannel* || true
    ssh -o StrictHostKeyChecking=no node01 "rm -f /etc/cni/net.d/*flannel*" >/dev/null 2>&1 || true
  fi

  curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" -o /tmp/calico.yaml
  sed -i -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' \
         -e "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|" /tmp/calico.yaml
  kubectl apply -f /tmp/calico.yaml >/dev/null
  echo "   Attente de Calico..."
  kubectl -n kube-system rollout status ds/calico-node --timeout=180s
  kubectl wait --for=condition=Ready node --all --timeout=120s
else
  echo ">> [2/5] Calico déjà installé."
fi

# S'assurer que le controlplane permet le scheduling (par défaut sur Killercoda, mais au cas où)
kubectl taint nodes --all node-role.kubernetes.io/control-plane- >/dev/null 2>&1 || true

# 3. Stockage local-path + metrics-server
echo ">> [3/5] Vérification local-path-provisioner & metrics-server..."
if ! kubectl get sc local-path >/dev/null 2>&1; then
  kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LPP_VERSION}/deploy/local-path-storage.yaml" >/dev/null
  kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' >/dev/null
fi

if ! kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml >/dev/null
  kubectl -n kube-system patch deploy metrics-server --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]' >/dev/null
  kubectl -n kube-system rollout status deploy/metrics-server --timeout=120s
fi

# 4. Configuration spécifique à la session
echo ">> [4/5] Installation des briques pour la session '$SESSION'..."

install_kyverno() {
  if ! kubectl get ns kyverno >/dev/null 2>&1; then
    echo "   -> Kyverno (mode léger 1 replica)..."
    helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
    helm repo update kyverno >/dev/null
    helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace \
      --set admissionController.replicas=1 \
      --set backgroundController.replicas=1 \
      --set cleanupController.replicas=1 \
      --set reportsController.replicas=1 \
      --wait --timeout 5m >/dev/null
  fi
}

enable_audit() {
  if ! grep -q "audit-policy-file" /etc/kubernetes/manifests/kube-apiserver.yaml; then
    echo "   -> Activation de l'audit logging sur kube-apiserver..."
    mkdir -p /etc/kubernetes/policies /var/log/kubernetes/audit
    cp "$LAB_DIR/kubeadm/audit-policy.yaml.orig" /etc/kubernetes/policies/audit-policy.yaml
    cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak

    # Injection des flags et volumes avec python3 (présent sur Ubuntu)
    python3 - <<'PY'
import yaml

path = "/etc/kubernetes/manifests/kube-apiserver.yaml"
with open(path) as f:
    doc = yaml.safe_load(f)

c = doc["spec"]["containers"][0]
args = c.setdefault("command", [])
audit_flags = [
    "--audit-policy-file=/etc/kubernetes/policies/audit-policy.yaml",
    "--audit-log-path=/var/log/kubernetes/audit/audit.log",
    "--audit-log-maxage=1",
    "--audit-log-maxbackup=2",
    "--audit-log-maxsize=50",
]
for fl in audit_flags:
    if not any(a.startswith(fl.split("=")[0]) for a in args):
        args.append(fl)

vms = c.setdefault("volumeMounts", [])
for name, mp, ro in [("audit-policies", "/etc/kubernetes/policies", True), ("audit-logs", "/var/log/kubernetes/audit", False)]:
    if not any(v["name"] == name for v in vms):
        vms.append({"name": name, "mountPath": mp, "readOnly": ro})

vols = doc["spec"].setdefault("volumes", [])
for name, hp in [("audit-policies", "/etc/kubernetes/policies"), ("audit-logs", "/var/log/kubernetes/audit")]:
    if not any(v["name"] == name for v in vols):
        vols.append({"name": name, "hostPath": {"path": hp, "type": "DirectoryOrCreate"}})

with open(path, "w") as f:
    yaml.safe_dump(doc, f, sort_keys=False)
PY
    echo "   -> Attente du redémarrage de kube-apiserver..."
    sleep 15
    until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
  fi
}

case "$SESSION" in
  base)
    echo "   -> Profil base uniquement (Calico, local-path, metrics-server)."
    ;;
  infra)
    echo "   -> Vérification etcdctl pour T19..."
    if ! command -v etcdctl >/dev/null 2>&1; then
      apt-get update -qq && apt-get install -y -qq etcd-client >/dev/null || true
    fi
    ;;
  gitops)
    helm repo add gitea-charts https://dl.gitea.com/charts/ >/dev/null 2>&1 || true
    helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
    helm repo update >/dev/null
    if ! kubectl get ns gitea >/dev/null 2>&1; then
      echo "   -> Gitea..."
      helm upgrade --install gitea gitea-charts/gitea -n gitea --create-namespace \
        -f "$LAB_DIR/scripts/values/gitea.yaml" --wait --timeout 6m >/dev/null
    fi
    if ! kubectl get ns argocd >/dev/null 2>&1; then
      echo "   -> Argo CD (allégé)..."
      helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
        --set dex.enabled=false --set notifications.enabled=false \
        --set applicationSet.enabled=false --wait --timeout 6m >/dev/null
    fi
    if ! kubectl get ns argo-rollouts >/dev/null 2>&1; then
      echo "   -> Argo Rollouts..."
      helm upgrade --install argo-rollouts argo/argo-rollouts -n argo-rollouts --create-namespace --wait --timeout 4m >/dev/null
    fi
    if ! kubectl get ns tekton-pipelines >/dev/null 2>&1; then
      echo "   -> Tekton Pipelines..."
      kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml >/dev/null
      kubectl -n tekton-pipelines rollout status deploy/tekton-pipelines-controller --timeout=180s
      kubectl -n tekton-pipelines rollout status deploy/tekton-pipelines-webhook --timeout=180s
    fi
    ;;
  platform)
    install_kyverno
    ;;
  observability)
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
    helm repo update prometheus-community >/dev/null
    if ! kubectl get ns monitoring >/dev/null 2>&1; then
      echo "   -> kube-prometheus-stack (mode léger sans Grafana/Alertmanager)..."
      helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
        --set grafana.enabled=false --set alertmanager.enabled=false --set nodeExporter.enabled=false \
        --set defaultRules.create=false --set kubeEtcd.enabled=false --set kubeControllerManager.enabled=false \
        --set kubeScheduler.enabled=false --set kubeProxy.enabled=false \
        --wait --timeout 8m >/dev/null
    fi
    ;;
  security)
    install_kyverno
    helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null 2>&1 || true
    helm repo update istio >/dev/null
    if ! kubectl get ns istio-system >/dev/null 2>&1; then
      echo "   -> Istio (base + istiod)..."
      helm upgrade --install istio-base istio/base -n istio-system --create-namespace --wait >/dev/null
      helm upgrade --install istiod istio/istiod -n istio-system --wait --timeout 6m >/dev/null
    fi
    enable_audit
    ;;
  *)
    echo "Session inconnue: $SESSION"
    exit 1
    ;;
esac

# 5. Charger les pannes de la session
echo ">> [5/5] Chargement des exercices de la session '$SESSION'..."
if [ "$SESSION" != "base" ]; then
  "$LAB_DIR/scripts/load-session.sh" "$SESSION"
fi

echo
echo "============================================================"
echo " Prêt ! Ouvre tasks/SESSION-${SESSION^^}.md (ou tasks/README.md)"
echo " Pour corriger : ./scripts/grade.sh $SESSION"
echo "============================================================"
