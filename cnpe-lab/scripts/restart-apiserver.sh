#!/usr/bin/env bash
# Force le kube-apiserver (static pod) à relire l'audit policy. (Même geste que sur le noeud d'examen.)
set -euo pipefail
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
echo "apiserver arrêté, attente 20s..."; sleep 20
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
sleep 10
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
echo "apiserver prêt"
