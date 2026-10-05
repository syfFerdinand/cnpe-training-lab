#!/usr/bin/env bash
# Vérifie la machine hôte. Le lab s'installe sur une VM Linux DÉDIÉE (Ubuntu 22.04/24.04 ou Debian 12) : kubeadm modifie le système.
ok=1
[ "$(uname -s)" = Linux ] || { echo "✘ Linux requis"; ok=0; }
grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null && echo "✔ OS $(. /etc/os-release; echo $PRETTY_NAME)" || { echo "✘ Ubuntu/Debian attendus (apt)"; ok=0; }
cpus=$(nproc); mem=$(awk '/MemTotal/{printf "%d",$2/1024/1024}' /proc/meminfo)
[ "$cpus" -ge 4 ] && echo "✔ $cpus vCPU" || { echo "✘ $cpus vCPU (6 conseillés, 4 minimum avec SKIP_*)"; ok=0; }
[ "$mem" -ge 7 ] && echo "✔ ${mem} Go RAM" || { echo "✘ ${mem} Go RAM (12 conseillés, 8 minimum avec SKIP_*)"; ok=0; }
sudo -n true 2>/dev/null && echo "✔ sudo sans mot de passe" || { echo "✘ sudo sans mot de passe requis (le correcteur lit le log d'audit)"; ok=0; }
curl -sfI https://pkgs.k8s.io >/dev/null && echo "✔ accès internet (pkgs.k8s.io)" || { echo "✘ pas d'accès à pkgs.k8s.io"; ok=0; }
echo "Disque libre : $(df -h / | awk 'NR==2{print $4}') (30 Go conseillés)"
echo "Allègement : SKIP_ISTIO=1 SKIP_PROMETHEUS=1 SKIP_TEKTON=1 SKIP_ARGOCD=1 SKIP_ROLLOUTS=1 (voir README)."
[ $ok = 1 ] || exit 1
