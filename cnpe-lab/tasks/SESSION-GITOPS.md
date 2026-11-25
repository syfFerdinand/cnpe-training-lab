# Session 2 : GitOps & CI/CD (`gitops`)

Lancement de la session sur Killercoda :
```bash
./scripts/setup-killercoda.sh gitops
```
Correction : `./scripts/grade.sh gitops` (ou `./scripts/grade.sh 05`).

---

## T05 – Argo CD (9 pts)
**Contexte** : l'Application `webapp-prod` (ns `argocd`) est OutOfSync/Unknown. Le dépôt Git est dans Gitea :
```bash
kubectl -n gitea port-forward svc/gitea-http 3000:3000 &
git clone http://gitea_admin:cnpe-lab-pass@localhost:3000/gitea_admin/gitops-repo.git ~/gitops-work
```
(URL interne pour Argo : `http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/gitops-repo.git`).
**Task** : Make Application `webapp-prod` **Synced and Healthy**, deploying `apps/webapp/overlays/prod` into namespace `webapp-prod` with **2 replicas**.
Fix the Application spec **and** any error in the Git repository (commit + push to `main`). Enable automated sync with **prune** and **selfHeal**, and let Argo CD create the namespace.
Quick Reference : https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/ · https://kubectl.docs.kubernetes.io/references/kustomize/

## T06 – CI/CD Tekton (8 pts)
**Contexte** : ns `ci`. Le PipelineRun `run-1` échoue. Le pipeline doit tester puis déployer `hello` dans `ci-target`.
**Task** : Make Pipeline `build-test-deploy` complete successfully with a PipelineRun (create a new one, e.g. `run-2`). It must deploy Deployment `hello` in `ci-target`.
Fix the Pipeline parameters, the workspace binding, and give ServiceAccount `pipeline-sa` the **minimum** RBAC required (namespaced, in `ci-target` only; no secrets, no cluster-wide rights).
Quick Reference : https://tekton.dev/docs/pipelines/pipelineruns/ · https://tekton.dev/docs/pipelines/workspaces/

## T07 – Progressive delivery (8 pts)
**Contexte** : ns `rollouts-demo`. Le Rollout `webapp` (canary) est bloqué / dégradé lors du passage `blue` -> `yellow`.
**Task** : Get Rollout `webapp` **Healthy** with image `argoproj/rollouts-demo:yellow` fully promoted, **without manual promotion**.
Fix the missing canary Service, the failing AnalysisTemplate `smoke-test` (Service port is 80), and remove any indefinite pause in the canary steps (use a duration of 10s).
Quick Reference : https://argo-rollouts.readthedocs.io/en/stable/features/canary/ · https://argo-rollouts.readthedocs.io/en/stable/features/analysis/
