# Session 4 : Observabilité & Incident Chaos (`observability`)

Lancement de la session sur Killercoda :
```bash
./scripts/setup-killercoda.sh observability
```
Correction : `./scripts/grade.sh observability` (ou `./scripts/grade.sh 10 11 12 21`).

---

## T10 – Prometheus (7 pts)
**Contexte** : Prometheus Operator (release helm `kps`, ns `monitoring`) ne scrape pas `example-app` (ns `shop-metrics`) et l'alerte n'existe pas.
**Task** : Make Prometheus scrape `example-app` (target UP) and load alert rule `HighErrorRatio` (health ok, then pending/firing given the generated traffic).
Fix ServiceMonitor `example-app` and PrometheusRule `example-alerts`. Prometheus API : `kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090`.
Hint : `kubectl -n monitoring get prometheus -o yaml | grep -A3 Selector`
Quick Reference : https://prometheus-operator.dev/docs/developer/getting-started/

## T11 – Incident applicatif (7 pts)
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

## T21 – Cluster & Workload Chaos (6 pts)
**Contexte** : les développeurs signalent que le nouveau déploiement `payment-api` dans le namespace `chaos-ops` reste bloqué et ne répond pas. Il y a une panne au niveau du **control-plane** ET une panne au niveau **applicatif**.
**Task** :
1. Diagnose why new pods stay `Pending` across the cluster, fix the broken control-plane component manifest on `controlplane`, and verify it is `Running`.
2. Once `payment-api` pods are scheduled, diagnose why they restart/fail readiness and fix Deployment `payment-api` in `chaos-ops` so all 2 replicas are Ready and Service `payment-api` has ready endpoints.
Quick Reference : https://kubernetes.io/docs/tasks/debug/debug-cluster/
