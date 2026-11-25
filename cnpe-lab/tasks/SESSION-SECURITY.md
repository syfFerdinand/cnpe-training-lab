# Session 5 : Sécurité & Gouvernance (`security`)

Lancement de la session sur Killercoda :
```bash
./scripts/setup-killercoda.sh security
```
Correction : `./scripts/grade.sh security` (ou `./scripts/grade.sh 13 14 15 16 22`).

---

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

## T15 – Admission policies Kyverno (4 pts)
**Contexte** : ns `policy-demo` (label `governance=enforced`). Trois ClusterPolicies Kyverno sont mal configurées ; `legacy` viole les règles.
**Task** : All three policies must be in **Enforce** mode and actually apply to namespaces labelled `governance=enforced`. Reject: images tagged `:latest` or without tag,
pods without label `team`, containers without memory limit. Then bring Deployment `legacy` into compliance (keep it running) and ensure the PolicyReport of `policy-demo` has 0 failures.
Quick Reference : https://kyverno.io/docs/writing-policies/validate/

## T16 – Audit policy (4 pts)
**Contexte** : l'audit est activé sur l'apiserver mais la policy est dangereuse (secrets loggés en clair).
Fichier à éditer : `/etc/kubernetes/policies/audit-policy.yaml`. Log : `/var/log/kubernetes/audit/audit.log`.
**Task** : Rewrite the audit policy (first match wins): `secrets`, `configmaps` and `tokenreviews` at **Metadata** level only; RBAC resources (roles, rolebindings, clusterroles, clusterrolebindings)
at **RequestResponse**; drop `/healthz*`, `/livez*`, `/readyz*`, `/version` non-resource URLs (level None); omit stage `RequestReceived` globally; everything else Metadata.
Then restart the API server so the new policy is loaded (`./scripts/restart-apiserver.sh`).
Quick Reference : https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/

## T22 – Pod Security Standards (5 pts)
**Contexte** : le namespace `secure-apps` doit appliquer le profil natif **Pod Security Standards (PSS)** `restricted`, et le Deployment `hardened-web` doit être mis en conformité.
**Task** :
1. Label namespace `secure-apps` to enforce the `restricted` Pod Security Standard (`pod-security.kubernetes.io/enforce: restricted`).
2. Fix Deployment `hardened-web` in `secure-apps` so its pod complies with the `restricted` profile (`runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `seccompProfile.type: RuntimeDefault`) and has 1/1 ready replica.
Quick Reference : https://kubernetes.io/docs/concepts/security/pod-security-standards/
