#!/usr/bin/env bash
# Branche l'audit logging sur le kube-apiserver du noeud kind (équivalent des flags --audit-*)
set -euo pipefail
NODE=${NODE:-cnpe-control-plane}
M=/etc/kubernetes/manifests/kube-apiserver.yaml
if docker exec "$NODE" grep -q audit-policy-file "$M"; then echo "audit déjà configuré"; exit 0; fi
docker exec "$NODE" mkdir -p /var/log/kubernetes/audit
docker exec "$NODE" sed -i \
  -e '/^    - kube-apiserver$/a\    - --audit-policy-file=/etc/kubernetes/policies/audit-policy.yaml\n    - --audit-log-path=/var/log/kubernetes/audit/audit.log\n    - --audit-log-maxage=1\n    - --audit-log-maxbackup=2\n    - --audit-log-maxsize=50' \
  -e '0,/^    volumeMounts:$/s//    volumeMounts:\n    - mountPath: \/etc\/kubernetes\/policies\n      name: audit-policies\n      readOnly: true\n    - mountPath: \/var\/log\/kubernetes\/audit\n      name: audit-logs/' \
  -e '0,/^  volumes:$/s//  volumes:\n  - hostPath:\n      path: \/etc\/kubernetes\/policies\n      type: DirectoryOrCreate\n    name: audit-policies\n  - hostPath:\n      path: \/var\/log\/kubernetes\/audit\n      type: DirectoryOrCreate\n    name: audit-logs/' \
  "$M"
echo "Attente du redémarrage de l'apiserver..."
sleep 15
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
echo "apiserver prêt avec audit activé"
