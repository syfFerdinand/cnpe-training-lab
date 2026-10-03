# Lab d'entraînement CNPE (Certified Cloud Native Platform Engineer)

Lab local basé sur **kind** qui reproduit l'esprit de l'examen : tâches indépendantes, chacune avec un problème à diagnostiquer et corriger en ligne de commande.
Il suit les 5 domaines du programme : Architecture & infra (15 %), GitOps & CD (25 %), Platform APIs & self-service (25 %), Observabilité (20 %), Sécurité (15 %).
17 tâches = 100 points, pondérées comme le blueprint.

## Prérequis
docker, kind, kubectl (>= 1.34), helm, jq, git, curl. Docker : ~6 vCPU / 12 Go RAM pour tout installer.
(Options d'allègement : `SKIP_ISTIO=1 SKIP_PROMETHEUS=1 SKIP_TEKTON=1 SKIP_ARGOCD=1 SKIP_ROLLOUTS=1 SKIP_KYVERNO=1 SKIP_GITEA=1 ./scripts/02-install-platform.sh` ;
les tâches dont l'outil manque sont ignorées au chargement.)

## Démarrage
```bash
./scripts/00-prereqs.sh
KIND_NODE_IMAGE=kindest/node:v1.35.0 ./scripts/01-cluster.sh   # ou sans variable : version par défaut de kind
./scripts/02-install-platform.sh      # Kyverno, Gitea, Argo CD/Rollouts, Tekton, Prometheus operator, Istio (10-20 min)
./scripts/03-load-lab.sh              # injecte les 17 pannes
less tasks/TASKS.md
```
Rejouer une tâche : `./scripts/03-load-lab.sh 05` (reset + rechargement de l'état cassé). Corriger : `./scripts/grade.sh 05` ou `./scripts/grade.sh`.
Tout supprimer : `kind delete cluster --name cnpe`.

## Règles pour t'entraîner comme le jour J
- Pas de moteur de recherche : uniquement kubernetes.io/docs, /blog, `kubectl explain`, `--help`, et la doc d'outil quand elle est donnée en Quick Reference.
- Tu peux utiliser `k`, `yq`, `jq`. Ne "triche" pas en supprimant/recréant les namespaces sauf si l'énoncé le permet.
- Vise ~6 min par tâche. Lis toujours tout l'énoncé : les contraintes ("without increasing the quota", "minimum RBAC"...) sont vérifiées.
- Ne regarde `cnpe-solution` qu'après avoir fini ou séché : il contient les fichiers finaux, un guide de diagnostic par tâche et un script qui applique tout.

## Ce qui diffère de l'examen
- Un seul cluster kind (pas de `ssh node` : la tâche 16 se fait via le dossier monté + `restart-apiserver.sh`).
- Le jour J, les outils exacts (Argo, Flux, Crossplane, Flagger, Linkerd, OpenCost, Grafana...) peuvent varier : entraîne-toi à lire `kubectl explain`, `kubectl api-resources` et la doc fournie.
- Non couvert ici (à pratiquer en plus si tu as le temps) : Crossplane (Compositions), Flux, Flagger, OpenCost, Linkerd, Gatekeeper/OPA, SBOM/scan d'images (Trivy) dans un pipeline.

## Arborescence
```
kind/            config du cluster + audit policy (tâche 16)
manifests/NN-*/  fichiers "cassés" de chaque tâche
gitops-repo/     dépôt poussé dans Gitea (tâche 05)
scripts/         installation, chargement des pannes, correcteur
tasks/TASKS.md   énoncés
```
