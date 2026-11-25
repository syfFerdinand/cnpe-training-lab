# Lab d'entraînement CNPE — Édition Killercoda (Playground 2 Nodes)

Ce lab est conçu pour tourner directement dans le **Kubernetes Playground (2 Nodes)** de Killercoda (`controlplane` + `node01`, 2 Go RAM/nœud, session de 60 min).
Pour respecter la limite mémoire de Killercoda tout en restant fidèle aux 5 domaines de l'examen **CNPE (CNCF)**, les **22 exercices** sont découpés en **5 sessions thématiques indépendantes**.

---

## Démarrage rapide sur Killercoda

1. Ouvre le playground **Kubernetes 2 Nodes** sur Killercoda.
2. Clone ce dépôt sur le nœud `controlplane` :
   ```bash
   git clone <URL_DU_REPO|https://github.com/syfFerdinand/cnpe-training-lab.git> ~/cnpe-lab && git switch killercoda && cd ~/cnpe-lab/cnpe-lab
   ```
3. Lance la session de ton choix (installe Calico, `local-path`, `metrics-server`, les outils de la session et injecte les pannes) :
   ```bash
   ./scripts/setup-killercoda.sh <session>
   ```
4. Ouvre l'énoncé correspondant dans `tasks/SESSION-*.md` et résous les pannes !
5. Corrige ta session :
   ```bash
   ./scripts/grade.sh <session>
   ```

---

## Les 5 sessions thématiques

| Session | Commande | Tâches | Outils installés | Énoncés |
|---|---|---|---|---|
| **1. Infra & Cluster Ops** | `./scripts/setup-killercoda.sh infra` | T01-T04, T18, T19 | Calico, local-path, metrics-server, etcdctl | [SESSION-INFRA.md](tasks/SESSION-INFRA.md) |
| **2. GitOps & CI/CD** | `./scripts/setup-killercoda.sh gitops` | T05, T06, T07 | Gitea, Argo CD, Argo Rollouts, Tekton | [SESSION-GITOPS.md](tasks/SESSION-GITOPS.md) |
| **3. Platform APIs** | `./scripts/setup-killercoda.sh platform` | T08, T09, T17, T20 | Kyverno, ValidatingAdmissionPolicy | [SESSION-PLATFORM.md](tasks/SESSION-PLATFORM.md) |
| **4. Observabilité & Chaos** | `./scripts/setup-killercoda.sh observability` | T10, T11, T12, T21 | Prometheus Operator, Jaeger, OTel, Chaos | [SESSION-OBSERVABILITY.md](tasks/SESSION-OBSERVABILITY.md) |
| **5. Sécurité & Gouvernance** | `./scripts/setup-killercoda.sh security` | T13-T16, T22 | Istio, Kyverno, Audit Policy, PSS | [SESSION-SECURITY.md](tasks/SESSION-SECURITY.md) |

---

## Commandes utiles pendant l'entraînement

- Rejouer une tâche précise (reset + réinjection de la panne) :
  ```bash
  ./scripts/load-session.sh 05
  ```
- Corriger une ou plusieurs tâches précises :
  ```bash
  ./scripts/grade.sh 05 06
  ```
- Alias recommandé : `alias k=kubectl`

---

## Nouveautés de cette version Killercoda

- **Remplacement auto de Flannel par Calico** pour que les `NetworkPolicy` (T02, T17) fonctionnent réellement.
- **Découpage par session** adapté aux 4 Go de RAM cumulés de Killercoda.
- **5 nouveaux exercices (T18 à T22)** :
  - **T18** : Node management (`uncordon`), `podAntiAffinity` sur 2 nœuds distincts.
  - **T19** : Sauvegarde et restauration `etcd` (`etcdctl snapshot`).
  - **T20** : `ValidatingAdmissionPolicy` natif (CEL).
  - **T21** : Chaos cluster + applicatif (manifest `kube-scheduler` cassé + livenessProbe).
  - **T22** : Pod Security Standards (`restricted`) et `securityContext`.
