#!/usr/bin/env bash
# Installe un cluster kubeadm (control-plane seul, scheduling autorisé dessus) : sudo ./scripts/01-cluster.sh
#   K8S_MINOR=v1.35  POD_CIDR=10.244.0.0/16  CALICO_VERSION=...  LPP_VERSION=...   (variables optionnelles)
#   NODE_ONLY=1 sudo -E ./scripts/01-cluster.sh   -> prépare seulement un noeud (containerd + kubeadm) pour un worker à joindre
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "Lance avec sudo : sudo ./scripts/01-cluster.sh"; exit 1; }
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
K8S_MINOR=${K8S_MINOR:-v1.35}
POD_CIDR=${POD_CIDR:-10.244.0.0/16}
CALICO_VERSION=${CALICO_VERSION:-v3.30.3}
LPP_VERSION=${LPP_VERSION:-v0.0.31}
REAL_USER=${SUDO_USER:-root}; REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
export DEBIAN_FRONTEND=noninteractive

echo ">> 1/6 système (swap off, modules, sysctl)"
swapoff -a; sed -i '/\sswap\s/ s/^/#/' /etc/fstab
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/k8s.conf
modprobe overlay; modprobe br_netfilter
cat > /etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

echo ">> 2/6 containerd (cgroup systemd)"
apt-get update -y >/dev/null
apt-get install -y apt-transport-https ca-certificates curl gpg jq git containerd >/dev/null
mkdir -p /etc/containerd; containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable containerd >/dev/null; systemctl restart containerd

echo ">> 3/6 kubeadm / kubelet / kubectl ($K8S_MINOR) + helm"
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/Release.key" | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update -y >/dev/null
apt-get install -y kubelet kubeadm kubectl >/dev/null
apt-mark hold kubelet kubeadm kubectl >/dev/null
systemctl enable kubelet >/dev/null
command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

if [ -n "${NODE_ONLY:-}" ]; then
  echo "Noeud préparé. Sur le control-plane : kubeadm token create --print-join-command  -> à lancer ici en root."; exit 0
fi

echo ">> 4/6 kubeadm init (audit logging natif via ClusterConfiguration)"
mkdir -p /etc/kubernetes/policies /var/log/kubernetes/audit
cp "$LAB_DIR/kubeadm/audit-policy.yaml" /etc/kubernetes/policies/audit-policy.yaml
if [ ! -f /etc/kubernetes/admin.conf ]; then
  sed -e "s#__K8S_VERSION__#$(kubeadm version -o short)#" -e "s#__POD_CIDR__#$POD_CIDR#" \
    "$LAB_DIR/kubeadm/kubeadm-config.yaml" > /tmp/kubeadm-config.yaml
  kubeadm init --config /tmp/kubeadm-config.yaml
else
  echo "   cluster déjà initialisé, étape ignorée"
fi
mkdir -p "$REAL_HOME/.kube"; cp /etc/kubernetes/admin.conf "$REAL_HOME/.kube/config"; chown -R "$REAL_USER":"$(id -gn "$REAL_USER")" "$REAL_HOME/.kube"
export KUBECONFIG=/etc/kubernetes/admin.conf

echo ">> 5/6 CNI Calico $CALICO_VERSION (applique les NetworkPolicy)"
curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" -o /tmp/calico.yaml
sed -i -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' -e "s|#   value: \"192.168.0.0/16\"|  value: \"${POD_CIDR}\"|" /tmp/calico.yaml
kubectl apply -f /tmp/calico.yaml
kubectl -n kube-system rollout status ds/calico-node --timeout=300s
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
kubectl wait --for=condition=Ready node --all --timeout=300s

echo ">> 6/6 local-path-provisioner (StorageClass par défaut) + metrics-server"
kubectl apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/${LPP_VERSION}/deploy/local-path-storage.yaml"
kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deploy/metrics-server --timeout=180s
echo
echo "Cluster prêt (kubeconfig copié dans $REAL_HOME/.kube/config). Suite (SANS sudo) : ./scripts/02-install-platform.sh"
