#!/usr/bin/env bash
# ==============================================================================
# Charge (ou recharge) les pannes d'une session ou d'une tâche spécifique.
# Usage:
#   ./scripts/load-session.sh <infra|gitops|platform|observability|security>
#   ./scripts/load-session.sh 05          # recharge uniquement la tâche 05
# ==============================================================================
set -uo pipefail

LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
M="$LAB_DIR/manifests"

have_crd(){ kubectl get crd "$1" >/dev/null 2>&1 || { echo "   (CRD $1 absente : composant non installé, tâche ignorée)"; return 1; }; }

push_repo(){
  kubectl -n gitea get svc gitea-http >/dev/null 2>&1 || { echo "   (Gitea absent, dépôt non poussé)"; return 1; }
  kubectl -n gitea port-forward svc/gitea-http 3999:3000 >/tmp/pf-gitea.log 2>&1 &
  local PF=$!
  for _ in $(seq 1 30); do curl -sf localhost:3999/api/healthz >/dev/null && break; sleep 2; done
  curl -s -u gitea_admin:cnpe-lab-pass -H 'Content-Type: application/json' -X POST localhost:3999/api/v1/user/repos \
    -d '{"name":"gitops-repo","private":false,"default_branch":"main"}' >/dev/null || true
  local tmp; tmp=$(mktemp -d)
  cp -r "$LAB_DIR/gitops-repo/." "$tmp/"
  ( cd "$tmp" && git init -q -b main && git add -A && git -c user.name=lab -c user.email=lab@lab.local commit -qm "initial state" \
    && git push -q -f http://gitea_admin:cnpe-lab-pass@localhost:3999/gitea_admin/gitops-repo.git main )
  kill $PF 2>/dev/null || true; rm -rf "$tmp"
}

# --- Loaders ---
load_01(){ kubectl apply -f "$M/01-multitenancy/lab.yaml"; }
load_02(){ kubectl apply -f "$M/02-network/lab.yaml"; }
load_03(){ kubectl apply -f "$M/03-storage/lab.yaml"; }
load_04(){ kubectl apply -f "$M/04-rightsizing/lab.yaml"; }
load_05(){ have_crd applications.argoproj.io || return; push_repo; kubectl apply -f "$M/05-argocd/application.yaml"; }
load_06(){ have_crd pipelines.tekton.dev || return; kubectl apply -f "$M/06-tekton/lab.yaml" && sleep 3 && kubectl apply -f "$M/06-tekton/pipelinerun.yaml"; }
load_07(){ have_crd rollouts.argoproj.io || return; kubectl apply -f "$M/07-rollouts/lab.yaml"; sleep 15
  kubectl -n rollouts-demo patch rollout webapp --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"argoproj/rollouts-demo:yellow"}]'; }
load_08(){ echo "   fichier à corriger : $M/08-crd/webapp-crd.yaml"; }
load_09(){ kubectl apply -f "$M/09-operator/operator.yaml"; }
load_10(){ have_crd servicemonitors.monitoring.coreos.com || return; kubectl apply -f "$M/10-prometheus/lab.yaml"; }
load_11(){ kubectl apply -f "$M/11-incident/lab.yaml"; }
load_12(){ kubectl apply -f "$M/12-tracing/lab.yaml"; kubectl apply -f "$M/12-tracing/telemetrygen-job.yaml"; }
load_13(){ have_crd authorizationpolicies.security.istio.io || return; kubectl apply -f "$M/13-istio/lab.yaml"; }
load_14(){ kubectl apply -f "$M/14-rbac/lab.yaml"; }
load_15(){ have_crd clusterpolicies.kyverno.io || return; kubectl apply -f "$M/15-kyverno/lab.yaml"; sleep 5; kubectl apply -f "$M/15-kyverno/policies.yaml"; }
load_16(){ cp "$LAB_DIR/kubeadm/audit-policy.yaml.orig" /etc/kubernetes/policies/audit-policy.yaml; "$LAB_DIR/scripts/restart-apiserver.sh"; }
load_17(){ have_crd clusterpolicies.kyverno.io || return; kubectl apply -f "$M/17-selfservice/policy.yaml"; }
load_18(){
  kubectl cordon node01 >/dev/null 2>&1 || true
  kubectl apply -f "$M/18-node-mgmt/lab.yaml"
}
load_19(){ kubectl apply -f "$M/19-etcd/lab.yaml"; }
load_20(){ kubectl apply -f "$M/20-vap/lab.yaml"; }
load_21(){
  kubectl apply -f "$M/21-troubleshoot/lab.yaml"
  # Chaos : casser kube-scheduler static pod (typo flag)
  if [ -f /etc/kubernetes/manifests/kube-scheduler.yaml ] && [ ! -f /tmp/kube-scheduler.yaml.orig ]; then
    cp /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/kube-scheduler.yaml.orig
    sed -i 's/--leader-elect=true/--leader-elect-broken=true/' /etc/kubernetes/manifests/kube-scheduler.yaml
  fi
}
load_22(){ kubectl apply -f "$M/22-pss/lab.yaml"; }

# --- Resetters ---
reset_ns(){ kubectl delete ns "$@" --ignore-not-found --wait=true >/dev/null 2>&1; }
reset_01(){ reset_ns team-alpha; }
reset_02(){ reset_ns team-beta; }
reset_03(){ reset_ns team-data; }
reset_04(){ reset_ns team-perf; }
reset_05(){ kubectl -n argocd delete application webapp-prod --ignore-not-found >/dev/null 2>&1; reset_ns webapp-prod; }
reset_06(){ reset_ns ci ci-target; }
reset_07(){ reset_ns rollouts-demo; }
reset_08(){ kubectl delete crd webapps.platform.example.org --ignore-not-found >/dev/null 2>&1; }
reset_09(){ reset_ns platform-system team-gamma; kubectl delete clusterrole,clusterrolebinding webapp-operator --ignore-not-found >/dev/null 2>&1; }
reset_10(){ reset_ns shop-metrics; }
reset_11(){ reset_ns shop; }
reset_12(){ reset_ns tracing; }
reset_13(){ reset_ns mesh-demo; kubectl -n default delete peerauthentication default --ignore-not-found >/dev/null 2>&1; }
reset_14(){ reset_ns apps-prod; kubectl delete clusterrolebinding ci-deployer-admin --ignore-not-found >/dev/null 2>&1; }
reset_15(){ kubectl delete cpol require-team-label disallow-latest-tag require-memory-limit --ignore-not-found >/dev/null 2>&1; reset_ns policy-demo; }
reset_16(){ :; }
reset_17(){ kubectl delete cpol tenant-bootstrap --ignore-not-found >/dev/null 2>&1; kubectl delete clusterrole kyverno-tenant-generate --ignore-not-found >/dev/null 2>&1; reset_ns tenant-x; }
reset_18(){ kubectl uncordon node01 >/dev/null 2>&1 || true; reset_ns ha-scheduling; }
reset_19(){ reset_ns etcd-lab; rm -f /tmp/etcd-backup.db; }
reset_20(){ kubectl delete validatingadmissionpolicy deny-privileged-and-hostnetwork --ignore-not-found >/dev/null 2>&1; kubectl delete validatingadmissionpolicybinding deny-privileged-binding --ignore-not-found >/dev/null 2>&1; reset_ns vap-demo; }
reset_21(){
  if [ -f /tmp/kube-scheduler.yaml.orig ]; then
    cp /tmp/kube-scheduler.yaml.orig /etc/kubernetes/manifests/kube-scheduler.yaml
    rm -f /tmp/kube-scheduler.yaml.orig
  fi
  reset_ns chaos-ops
}
reset_22(){ reset_ns secure-apps; }

declare -A SESSIONS=(
  [infra]="01 02 03 04 18 19"
  [gitops]="05 06 07"
  [platform]="08 09 17 20"
  [observability]="10 11 12 21"
  [security]="13 14 15 16 22"
)

TARGET=${1:-}
if [ -z "$TARGET" ]; then
  echo "Usage: $0 <infra|gitops|platform|observability|security|NN>"
  exit 1
fi

if [[ -n "${SESSIONS[$TARGET]:-}" ]]; then
  for n in ${SESSIONS[$TARGET]}; do
    echo ">> Chargement T$n..."
    "reset_$n" || true
    "load_$n" || true
  done
else
  n=$(printf '%02d' "$((10#$TARGET))")
  echo ">> Reset + reload T$n..."
  "reset_$n"
  "load_$n"
fi
