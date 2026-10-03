# CNPE Lab – Énoncés des tâches

Format examen : contexte en **français** (pour toi), consigne en **anglais** (comme le jour J).
Contexte machine : `kubectl config use-context kind-cnpe` (un seul cluster, tu es admin). Alias conseillé : `alias k=kubectl`.
Documentation autorisée pendant l'entraînement : kubernetes.io/docs et kubernetes.io/blog uniquement, + la doc de l'outil concerné
quand elle est citée dans "Quick Reference" (à l'examen, ces liens sont fournis dans l'énoncé).
Chrono : 2h pour 15-20 tâches, soit ~6 min/tâche. Ici 17 tâches : vise 2h15 maximum en tout.
Vérification : `./scripts/grade.sh 05` (une tâche) ou `./scripts/grade.sh` (tout).

| # | Domaine | Pts | Sujet |
|---|---|---|---|
| 01 | Architecture (15) | 4 | Multi-tenancy : ResourceQuota + LimitRange |
| 02 | Architecture | 4 | NetworkPolicy (default-deny) |
| 03 | Architecture | 3 | StorageClass / PVC |
| 04 | Architecture | 4 | Right-sizing + HPA |
| 05 | GitOps/CD (25) | 9 | Argo CD Application + Kustomize |
| 06 | GitOps/CD | 8 | Pipeline Tekton + RBAC |
| 07 | GitOps/CD | 8 | Canary avec Argo Rollouts |
| 08 | Platform APIs (25) | 9 | CRD `WebApp` |
| 09 | Platform APIs | 9 | Opérateur qui réconcilie `WebApp` |
| 17 | Platform APIs | 7 | Self-service : provisionnement de tenant (Kyverno generate) |
| 10 | Observabilité (20) | 7 | ServiceMonitor + PrometheusRule |
| 11 | Observabilité | 7 | Incident : diagnostic et remédiation |
| 12 | Observabilité | 6 | Traces : OTel Collector -> Jaeger |
| 13 | Sécurité (15) | 4 | mTLS + AuthorizationPolicy (Istio) |
| 14 | Sécurité | 3 | RBAC moindre privilège |
| 15 | Sécurité | 4 | Politiques d'admission (Kyverno) |
| 16 | Sécurité | 4 | Audit policy de l'API server |

---

## T01 – Multi-tenancy (4 pts)
**Contexte** : le namespace `team-alpha` a un quota, mais les pods du Deployment `api` ne sont jamais créés.
**Task** : In namespace `team-alpha`, make all 4 replicas of Deployment `api` run **without increasing** the existing ResourceQuota `compute-quota`.
Create a LimitRange that gives every container default requests (cpu 100m, memory 64Mi) and default limits (cpu 200m, memory 128Mi).
Additionally, forbid LoadBalancer Services in this namespace by adding `services.loadbalancers: 0` to a quota in the namespace.
Quick Reference : https://kubernetes.io/docs/concepts/policy/limit-range/ · https://kubernetes.io/docs/concepts/policy/resource-quotas/

## T02 – NetworkPolicy (4 pts)
**Contexte** : `team-beta` est en default-deny (ingress + egress). Un ancien essai (`allow-frontend`) est cassé.
**Task** : In namespace `team-beta`: allow `frontend` pods to reach `backend` pods on TCP 5678 **only**. `frontend` must be able to resolve DNS.
`frontend` must NOT reach `db`, and `intruder` must NOT reach `backend`. Keep `default-deny-all`. Fix or replace `allow-frontend`.
Test : `kubectl -n team-beta exec deploy/frontend -- curl -s -m 3 http://backend:5678`
Quick Reference : https://kubernetes.io/docs/concepts/services-networking/network-policies/

## T03 – Storage (3 pts)
**Contexte** : le PVC `data-pvc` (ns `team-data`) reste Pending ; le pod `writer` ne démarre pas.
**Task** : Make PVC `data-pvc` Bound and Deployment `writer` running **without editing the PVC**. Create StorageClass `fast-ssd` using the provisioner
already used by the default class (`rancher.io/local-path`), `volumeBindingMode: WaitForFirstConsumer`, `reclaimPolicy: Retain`.
Quick Reference : https://kubernetes.io/docs/concepts/storage/storage-classes/

## T04 – Right-sizing + HPA (4 pts)
**Contexte** : `team-perf`, Deployment `web` demande 2 CPU / 2Gi par pod alors que l'usage observé est ~20m CPU / ~40Mi. HPA mal configurée.
**Task** : Right-size Deployment `web` (requests cpu **50m**, memory **64Mi**; limits memory **128Mi**, cpu 200m). Fix HPA `web` so it targets Deployment `web`,
scales between **2 and 6** replicas on **CPU utilization 60%**. `kubectl top pods -n team-perf` must work (metrics-server is installed).
Quick Reference : https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/

## T05 – Argo CD (9 pts)
**Contexte** : l'Application `webapp-prod` (ns `argocd`) est OutOfSync/Unknown. Le dépôt Git est dans Gitea :
`kubectl -n gitea port-forward svc/gitea-http 3000:3000 &` puis
`git clone http://gitea_admin:cnpe-lab-pass@localhost:3000/gitea_admin/gitops-repo.git ~/gitops-work` (URL interne pour Argo : `http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/gitops-repo.git`).
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

## T08 – CRD (9 pts)
**Contexte** : la plateforme veut exposer une API `WebApp`. Le fichier `manifests/08-crd/webapp-crd.yaml` est invalide.
**Task** : Fix and apply the CRD `webapps.platform.example.org`: namespaced, kind `WebApp`, short name `wa`, category `platform`, **single served+storage version `v1`**.
Schema for `spec`: `image` (string, required); `replicas` (integer, default 1, min 1, max 10); `port` (integer, default 80); `tier` (enum bronze/silver/gold, default bronze).
Add a CEL validation rule: `replicas` greater than 3 is only allowed when `tier` is `gold`. Enable the `status` subresource (`status.readyReplicas` integer).
Add printer columns Image, Replicas, Ready (`status.readyReplicas`).
Quick Reference : https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/ · https://kubernetes.io/docs/reference/using-api/cel/

## T09 – Opérateur (9 pts) *(dépend de T08)*
**Contexte** : ns `platform-system`, Deployment `webapp-operator` (un mini-opérateur en bash). Il ne démarre pas / n'a pas les droits.
**Task** : Make the operator work. Then apply `manifests/09-operator/sample-webapp.yaml`. The operator must create Deployment and Service `demo` in `team-gamma`
(owned by the WebApp, 2 replicas) and write `status.readyReplicas` on the WebApp. Fix the Deployment (script path, ServiceAccount) and grant the ServiceAccount
**least-privilege** ClusterRole permissions (list/watch webapps, patch webapps/status, manage deployments and services).
Quick Reference : https://kubernetes.io/docs/concepts/extend-kubernetes/operator/ · https://kubernetes.io/docs/reference/access-authn-authz/rbac/

## T10 – Prometheus (7 pts)
**Contexte** : Prometheus Operator (release helm `kps`, ns `monitoring`) ne scrape pas `example-app` (ns `shop-metrics`) et l'alerte n'existe pas.
**Task** : Make Prometheus scrape `example-app` (target UP) and load alert rule `HighErrorRatio` (health ok, then pending/firing given the generated traffic).
Fix ServiceMonitor `example-app` and PrometheusRule `example-alerts`. Prometheus API : `kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090`.
Hint : `kubectl -n monitoring get prometheus -o yaml | grep -A3 Selector`
Quick Reference : https://prometheus-operator.dev/docs/developer/getting-started/

## T11 – Incident (7 pts)
**Contexte** : ns `shop`, trois services sont en panne, trois causes différentes.
**Task** : Diagnose and fix Deployments `checkout`, `cart` and `frontend` and Service `frontend` in namespace `shop` so that all pods are Ready and the Service has endpoints.
Do not delete the namespace; do not recreate the ConfigMap from scratch.
Quick Reference : https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/

## T12 – Tracing (6 pts)
**Contexte** : ns `tracing`. Jaeger tourne. L'OTel Collector crashe ; le Job `telemetrygen` échoue.
**Task** : Fix the OpenTelemetry Collector so traces sent to `otel-collector:4317` (OTLP/gRPC) are exported to Jaeger. Keep a `debug` exporter with verbosity `detailed`
in the traces pipeline so spans are visible in the collector logs. Re-run Job `telemetrygen`; service `checkout` must appear in Jaeger
(`kubectl -n tracing port-forward svc/jaeger 16686`).
Quick Reference : https://opentelemetry.io/docs/collector/configuration/

## T13 – Service mesh security (4 pts)
**Contexte** : ns `mesh-demo`, mesh Istio (sidecar). Rien n'est chiffré.
**Task** : Enable sidecar injection for `mesh-demo` and restart the workloads. Enforce **STRICT mTLS** for the whole namespace (fix the misplaced PeerAuthentication).
Fix AuthorizationPolicy `server-allow` so **only** ServiceAccount `client-ok` can GET `server`. `client-denied` must get HTTP 403; a pod outside the mesh must be rejected.
Test : `kubectl -n mesh-demo exec deploy/client-allowed -c curl -- curl -s -o /dev/null -w '%{http_code}' http://server:5678`
Quick Reference : https://istio.io/latest/docs/reference/config/security/peer_authentication/ · https://istio.io/latest/docs/reference/config/security/authorization-policy/

## T14 – RBAC (3 pts)
**Contexte** : ns `apps-prod`. Le SA `ci-deployer` est cluster-admin ; l'utilisateur `alice` peut tout modifier.
**Task** : Replace the cluster-admin ClusterRoleBinding for `ci-deployer` by a namespaced Role `deployer` in `apps-prod` allowing get/list/watch/create/update/patch on `deployments` and `services` only.
Change `alice` to **read-only** in `apps-prod` (no secrets). Verify with `kubectl auth can-i`.
Quick Reference : https://kubernetes.io/docs/reference/access-authn-authz/rbac/

## T15 – Admission policies (4 pts)
**Contexte** : ns `policy-demo` (label `governance=enforced`). Trois ClusterPolicies Kyverno sont mal configurées ; `legacy` viole les règles.
**Task** : All three policies must be in **Enforce** mode and actually apply to namespaces labelled `governance=enforced`. Reject: images tagged `:latest` or without tag,
pods without label `team`, containers without memory limit. Then bring Deployment `legacy` into compliance (keep it running) and ensure the PolicyReport of `policy-demo` has 0 failures.
Quick Reference : https://kyverno.io/docs/writing-policies/validate/

## T16 – Audit policy (4 pts)
**Contexte** : l'audit est activé sur l'apiserver mais la policy est dangereuse (secrets loggés en clair). Fichier : `kind/audit/audit-policy.yaml` (hôte).
Sur un vrai noeud, ce serait `/etc/kubernetes/policies/audit-policy.yaml`.
**Task** : Rewrite the audit policy (first match wins): `secrets`, `configmaps` and `tokenreviews` at **Metadata** level only; RBAC resources (roles, rolebindings, clusterroles, clusterrolebindings)
at **RequestResponse**; drop `/healthz*`, `/livez*`, `/readyz*`, `/version` non-resource URLs (level None); omit stage `RequestReceived` globally; everything else Metadata.
Then restart the API server (`./scripts/restart-apiserver.sh`).
Quick Reference : https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/

## T17 – Self-service tenant (7 pts)
**Contexte** : la plateforme veut qu'un namespace labellisé `platform.example.org/tenant=true` reçoive automatiquement quota + default-deny. Rien ne se passe (`manifests/17-selfservice/policy.yaml` à appliquer/corriger).
**Task** : Fix and apply ClusterPolicy `tenant-bootstrap` so that creating a namespace with label `platform.example.org/tenant=true` generates ResourceQuota `tenant-quota` and NetworkPolicy `default-deny`
in it, and **keeps them synchronized** (deleted -> recreated). Kyverno's background controller may lack permissions: fix that too.
Quick Reference : https://kyverno.io/docs/writing-policies/generate/
