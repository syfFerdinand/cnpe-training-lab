#!/usr/bin/env bash
# Détruit le cluster kubeadm de ce noeud (pour repartir de zéro) : sudo ./scripts/99-reset-cluster.sh
set -u
[ "$(id -u)" = 0 ] || { echo "sudo requis"; exit 1; }
kubeadm reset -f
rm -rf /etc/cni/net.d /var/lib/cni /var/lib/etcd /etc/kubernetes/policies /var/log/kubernetes
iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X 2>/dev/null
rm -rf "${SUDO_USER:+$(getent passwd "$SUDO_USER" | cut -d: -f6)}/.kube" 2>/dev/null
echo "Cluster supprimé. Relance sudo ./scripts/01-cluster.sh pour recommencer."
