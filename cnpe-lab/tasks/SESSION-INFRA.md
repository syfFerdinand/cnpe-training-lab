# Session 1 : Architecture, Infra & Cluster Ops (`infra`)

Lancement de la session sur Killercoda :
```bash
./scripts/setup-killercoda.sh infra
```
Correction : `./scripts/grade.sh infra` (ou `./scripts/grade.sh 01 18` pour des tâches précises).

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

## T18 – Node Management & HA Scheduling (5 pts) *(Spécifique 2 nœuds)*
**Contexte** : dans le namespace `ha-scheduling`, `web-ha` est Pending et `maintenance-app` est bloqué en scheduling manuel (`nodeName`). De plus, `node01` est en maintenance (`SchedulingDisabled`).
**Task** :
1. Make `node01` schedulable again (`uncordon`).
2. Fix Deployment `web-ha` so its 2 replicas run on **2 distinct nodes** (`controlplane` and `node01`) using **required** `podAntiAffinity` on `kubernetes.io/hostname` (remove the invalid `nodeSelector`).
3. Fix Deployment `maintenance-app` by removing `spec.template.spec.nodeName` so it is managed by the Kubernetes scheduler and has 2/2 ready replicas.
Quick Reference : https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

## T19 – Etcd Snapshot & Restore (6 pts)
**Contexte** : le cluster Killercoda stocke son état dans etcd (static pod sur `controlplane`). Le namespace `etcd-lab` contient un ConfigMap critique `critical-data`.
**Task** :
1. Take a snapshot of the cluster's etcd database and save it to `/tmp/etcd-backup.db` (inspect `/etc/kubernetes/manifests/etcd.yaml` for endpoints and TLS certificates).
2. Verify the snapshot status (`etcdctl snapshot status /tmp/etcd-backup.db`).
3. *(Entraînement)* Delete `cm critical-data -n etcd-lab`, then restore `/tmp/etcd-backup.db` into a new data directory (e.g. `/var/lib/etcd-restored`) and update `/etc/kubernetes/manifests/etcd.yaml` to confirm `critical-data` comes back.
Quick Reference : https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
