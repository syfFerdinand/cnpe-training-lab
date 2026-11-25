# Session 3 : Platform APIs & Self-Service (`platform`)

Lancement de la session sur Killercoda :
```bash
./scripts/setup-killercoda.sh platform
```
Correction : `./scripts/grade.sh platform` (ou `./scripts/grade.sh 08 09 17 20`).

---

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

## T17 – Self-service tenant (7 pts)
**Contexte** : la plateforme veut qu'un namespace labellisé `platform.example.org/tenant=true` reçoive automatiquement quota + default-deny. Rien ne se passe (`manifests/17-selfservice/policy.yaml` à corriger).
**Task** : Fix and apply ClusterPolicy `tenant-bootstrap` so that creating a namespace with label `platform.example.org/tenant=true` generates ResourceQuota `tenant-quota` and NetworkPolicy `default-deny`
in it, and **keeps them synchronized** (deleted -> recreated). Kyverno's background controller may lack permissions: fix that too.
Quick Reference : https://kyverno.io/docs/writing-policies/generate/

## T20 – Native ValidatingAdmissionPolicy (6 pts)
**Contexte** : la plateforme veut bloquer les pods dangereux sans outil tiers, via la fonctionnalité native Kubernetes `ValidatingAdmissionPolicy` (CEL). La policy `deny-privileged-and-hostnetwork` est mal configurée.
**Task** :
1. Fix `ValidatingAdmissionPolicy` `deny-privileged-and-hostnetwork` so it **denies** any Pod where `hostNetwork` is `true` **OR** any container has `securityContext.privileged == true`.
2. Fix `ValidatingAdmissionPolicyBinding` `deny-privileged-binding` so its `validationActions` is `["Deny"]` and it only applies to namespaces matching label `vap-enforced: "true"`.
Quick Reference : https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
