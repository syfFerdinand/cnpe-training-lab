#!/usr/bin/env bash
# Vérifie les outils nécessaires sur ta machine (le lab tourne en local avec kind)
ok=1
for b in docker kind kubectl helm jq curl git; do
  if command -v "$b" >/dev/null; then echo "✔ $b"; else echo "✘ $b manquant"; ok=0; fi
done
docker info >/dev/null 2>&1 || { echo "✘ le démon docker ne répond pas"; ok=0; }
echo
echo "Ressources conseillées : 6 vCPU / 12 Go RAM pour Docker (tout installé)."
echo "Allègement possible : SKIP_ISTIO=1 SKIP_PROMETHEUS=1 SKIP_TEKTON=1 SKIP_ARGOCD=1 SKIP_ROLLOUTS=1 (voir README)."
[ $ok = 1 ] || exit 1
