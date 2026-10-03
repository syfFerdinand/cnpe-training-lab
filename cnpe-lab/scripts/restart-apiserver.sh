#!/usr/bin/env bash
# Force le kube-apiserver (static pod) à relire l'audit policy.
# Dans l'examen : sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/ ; attendre ; le remettre.
set -euo pipefail
NODE=${NODE:-cnpe-control-plane}
docker exec "$NODE" bash -c 'mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/ && sleep 20 && mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/'
echo "Attente de l'apiserver..."
sleep 10
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
echo "apiserver prêt"
