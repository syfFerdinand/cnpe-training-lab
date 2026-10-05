# Lab d'entraînement CNPE (Certified Cloud Native Platform Engineer) – version kubeadm

Lab qui reproduit l'esprit de l'examen : tâches indépendantes, chacune avec un problème à diagnostiquer et corriger en ligne de commande, directement sur un
**vrai cluster kubeadm** (static pods, `/etc/kubernetes/manifests`, containerd, Calico).
Il suit les 5 domaines du programme : Architecture & infra (15 %), GitOps & CD (25 %), Platform APIs & self-service (25 %), Observabilité (20 %), Sécurité (15 %).
17 tâches = 100 points, pondérées comme le blueprint.

## Prérequis : une VM Linux dédiée
- Ubuntu 22.04/24.04 (ou Debian 12), **6 vCPU / 12 Go RAM / 30 Go disque** conseillés (4 vCPU / 8 Go minimum avec `SKIP_*`), accès internet, utilisateur avec `sudo` sans mot de passe.
- ⚠️ kubeadm modifie le système (swap, sysctl, iptables) : utilise une VM jetable, pas ton poste. Le jour J tu passeras l'examen sur ta machine, pas dans une VM : ce lab, lui, peut tourner dans une VM.
- Tout se lance **sur le noeud control-plane** (single-node, scheduling autorisé). Worker optionnel : voir plus bas.

## Démarrage
```bash
./scripts/00-prereqs.sh
sudo ./scripts/01-cluster.sh          # containerd, kubeadm/kubelet/kubectl v1.35, kubeadm init (audit natif), Calico, local-path, metrics-server, helm
./scripts/02-install-platform.sh      # SANS sudo. Kyverno, Gitea, Argo CD/Rollouts, Tekton, Prometheus operator, Istio (10-20 min)
./scripts/03-load-lab.sh              # injecte les 17 pannes
less tasks/TASKS.md
```
Rejouer une tâche : `./scripts/03-load-lab.sh 05` (reset + rechargement de l'état cassé). Corriger : `./scripts/grade.sh 05` ou `./scripts/grade.sh`.
Tout détruire et recommencer : `sudo ./scripts/99-reset-cluster.sh`.

Allègement : `SKIP_ISTIO=1 SKIP_PROMETHEUS=1 SKIP_TEKTON=1 SKIP_ARGOCD=1 SKIP_ROLLOUTS=1 SKIP_KYVERNO=1 SKIP_GITEA=1 ./scripts/02-install-platform.sh` ; les tâches dont l'outil manque sont ignorées au chargement.

### Ajouter un worker (facultatif, pour s'entraîner à `drain`, affinités…)
Sur la 2e VM : `sudo NODE_ONLY=1 ./scripts/01-cluster.sh`, puis `kubeadm token create --print-join-command` sur le control-plane et colle la commande (root) sur le worker.
Les tâches fonctionnent avec ou sans worker.

## Règles pour t'entraîner comme le jour J
- Pas de moteur de recherche : uniquement kubernetes.io/docs, /blog, `kubectl explain`, `--help`, et la doc d'outil quand elle est donnée en Quick Reference.
- Tu peux utiliser `k`, `yq`, `jq`. Ne "triche" pas en supprimant/recréant les namespaces sauf si l'énoncé le permet.
- Vise ~6 min par tâche. Lis toujours tout l'énoncé : les contraintes ("without increasing the quota", "minimum RBAC"...) sont vérifiées.
- Ne regarde `cnpe-solution` qu'après avoir fini ou séché.

## Ce qui diffère de l'examen
- Un seul noeud, pas de `ssh <host>` entre plusieurs clusters ; le jour J, chaque tâche te fait entrer sur un hôte désigné.
- Les outils exacts (Argo, Flux, Crossplane, Flagger, Linkerd, OpenCost, Grafana...) peuvent varier : entraîne-toi à lire `kubectl explain`, `kubectl api-resources` et la doc fournie.
- Non couvert ici : Crossplane (Compositions), Flux, Flagger, OpenCost, Linkerd, Gatekeeper/OPA, SBOM/scan d'images (Trivy) dans un pipeline.

## Arborescence
```
kubeadm/         kubeadm-config.yaml (audit natif) + audit-policy initiale (tâche 16)
manifests/NN-*/  fichiers "cassés" de chaque tâche
gitops-repo/     dépôt poussé dans Gitea (tâche 05)
scripts/         installation du cluster, des briques, chargement des pannes, correcteur
tasks/TASKS.md   énoncés
```
