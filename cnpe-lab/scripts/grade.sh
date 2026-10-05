#!/usr/bin/env bash
# Correcteur du lab CNPE.  Usage : ./scripts/grade.sh [NN ...]   (sans argument : toutes les tâches)
# Nécessite : kubectl, jq, sudo (tâche 16 : lecture du log d'audit).
set -u
SCORE=0; TOTAL=0; _fail=0
OK=$'\e[32m'; KO=$'\e[31m'; NC=$'\e[0m'

chk(){ local d=$1; shift; if "$@" >/dev/null 2>&1; then echo "   ${OK}✔${NC} $d"; else echo "   ${KO}✘${NC} $d"; _fail=1; fi; }
chkw(){ local d=$1 t=$2 i=0; shift 2
  while (( i < t )); do "$@" >/dev/null 2>&1 && { echo "   ${OK}✔${NC} $d"; return; }; sleep 3; i=$((i+3)); done
  echo "   ${KO}✘${NC} $d"; _fail=1; }
eq(){ [ "$1" = "$2" ]; }
not(){ ! "$@"; }
can(){ [ "$(kubectl auth can-i "$@" 2>/dev/null)" = yes ]; }

# ---------- T01 Multi-tenancy ----------
t01_lr(){ kubectl -n team-alpha get limitrange -o json | jq -e '[.items[].spec.limits[]|select(.type=="Container" and .defaultRequest.cpu != null and .default.memory != null)]|length>0'; }
t01_ready(){ eq "$(kubectl -n team-alpha get deploy api -o jsonpath='{.status.readyReplicas}')" 4; }
t01(){
  chk "LimitRange avec defaultRequest + default limit sur les conteneurs" t01_lr
  chkw "Deployment api : 4/4 replicas prêts" 90 t01_ready
  chk "ResourceQuota non contourné (requests.cpu = 1)" eq "$(kubectl -n team-alpha get resourcequota compute-quota -o jsonpath='{.spec.hard.requests\.cpu}')" 1
  chk "Quota : services.loadbalancers = 0" eq "$(kubectl -n team-alpha get resourcequota -o jsonpath='{.items[*].spec.hard.services\.loadbalancers}' | tr -d ' ')" 0
}

# ---------- T02 NetworkPolicy ----------
t02_fb(){ kubectl -n team-beta exec deploy/frontend -- curl -s -m 3 http://backend:5678 | grep -q backend-ok; }
t02_fdb(){ kubectl -n team-beta exec deploy/frontend -- curl -s -m 3 http://db:5678 | grep -q db-ok; }
t02_ib(){ kubectl -n team-beta exec deploy/intruder -- curl -s -m 3 http://backend:5678 | grep -q backend-ok; }
t02(){
  chkw "frontend -> backend:5678 autorisé" 30 t02_fb
  chk "frontend -> db bloqué" not t02_fdb
  chk "intruder -> backend bloqué" not t02_ib
  chk "default-deny-all toujours présent" kubectl -n team-beta get netpol default-deny-all
}

# ---------- T03 Storage ----------
t03_pv(){ kubectl get pv -o json | jq -e '[.items[]|select(.spec.claimRef.name=="data-pvc")|.spec.persistentVolumeReclaimPolicy][0]=="Retain"'; }
t03(){
  chk "StorageClass fast-ssd (provisioner rancher.io/local-path)" eq "$(kubectl get sc fast-ssd -o jsonpath='{.provisioner}' 2>/dev/null)" rancher.io/local-path
  chk "reclaimPolicy = Retain" eq "$(kubectl get sc fast-ssd -o jsonpath='{.reclaimPolicy}' 2>/dev/null)" Retain
  chk "volumeBindingMode = WaitForFirstConsumer" eq "$(kubectl get sc fast-ssd -o jsonpath='{.volumeBindingMode}' 2>/dev/null)" WaitForFirstConsumer
  chkw "PVC data-pvc Bound" 60 bash -c "[ \"\$(kubectl -n team-data get pvc data-pvc -o jsonpath='{.status.phase}')\" = Bound ]"
  chkw "Deployment writer disponible et données écrites" 60 kubectl -n team-data exec deploy/writer -- cat /data/out.txt
  chk "PV avec reclaimPolicy Retain" t03_pv
}

# ---------- T04 Right-sizing + HPA ----------
t04_res(){ kubectl -n team-perf get deploy web -o json | jq -e '.spec.template.spec.containers[0].resources as $r | ($r.requests.cpu|rtrimstr("m")|tonumber) <= 100 and ($r.requests.memory|rtrimstr("Mi")|tonumber) <= 128 and ($r.limits != null)'; }
t04_hpa(){ kubectl -n team-perf get hpa web -o json | jq -e '.spec.scaleTargetRef.name=="web" and .spec.minReplicas==2 and .spec.maxReplicas==6 and ([.spec.metrics[]|select(.type=="Resource" and .resource.name=="cpu" and .resource.target.averageUtilization==60)]|length==1)'; }
t04_active(){ kubectl -n team-perf get hpa web -o json | jq -e '[.status.conditions[]|select(.type=="ScalingActive" and .status=="True")]|length==1'; }
t04(){
  chk "requests <= 100m / 128Mi et limits définies" t04_res
  chkw "Deployment web : >= 2 replicas prêts" 90 bash -c "[ \"\$(kubectl -n team-perf get deploy web -o jsonpath='{.status.readyReplicas}')\" -ge 2 ]"
  chk "HPA web : cible web, min 2, max 6, CPU 60%" t04_hpa
  chkw "HPA : ScalingActive=True (metrics-server OK)" 120 t04_active
}

# ---------- T05 Argo CD ----------
t05_a(){ kubectl -n argocd get app webapp-prod -o json; }
t05(){
  chkw "Application Synced" 120 bash -c "kubectl -n argocd get app webapp-prod -o jsonpath='{.status.sync.status}' | grep -q Synced"
  chkw "Application Healthy" 120 bash -c "kubectl -n argocd get app webapp-prod -o jsonpath='{.status.health.status}' | grep -q Healthy"
  chk "syncPolicy automated : prune + selfHeal" bash -c "kubectl -n argocd get app webapp-prod -o json | jq -e '.spec.syncPolicy.automated.prune==true and .spec.syncPolicy.automated.selfHeal==true'"
  chk "syncOption CreateNamespace=true" bash -c "kubectl -n argocd get app webapp-prod -o json | jq -e '.spec.syncPolicy.syncOptions|index(\"CreateNamespace=true\")'"
  chk "Deployment webapp : 2 replicas dans webapp-prod" eq "$(kubectl -n webapp-prod get deploy webapp -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" 2
}

# ---------- T06 Tekton ----------
t06_run(){ kubectl -n ci get pipelinerun -o json | jq -e '[.items[]|select(.status.conditions[0].status=="True")]|length>=1'; }
t06(){
  chkw "Un PipelineRun a réussi" 150 t06_run
  chk "Deployment hello présent dans ci-target" kubectl -n ci-target get deploy hello
  chk "pipeline-sa peut créer des deployments dans ci-target" can create deployments -n ci-target --as system:serviceaccount:ci:pipeline-sa
  chk "pipeline-sa ne peut PAS créer de deployments dans default" not can create deployments -n default --as system:serviceaccount:ci:pipeline-sa
  chk "pipeline-sa ne peut PAS lire les secrets de ci-target" not can get secrets -n ci-target --as system:serviceaccount:ci:pipeline-sa
}

# ---------- T07 Argo Rollouts ----------
t07_tpl(){ kubectl -n rollouts-demo get analysistemplate smoke-test -o json | jq -e '[.spec.metrics[].provider.job.spec.template.spec.containers[].args[]]|map(test(":8080"))|any|not'; }
t07_pause(){ kubectl -n rollouts-demo get rollout webapp -o json | jq -e '[.spec.strategy.canary.steps[]|select(has("pause") and (.pause.duration==null))]|length==0'; }
t07_ok(){ kubectl -n rollouts-demo get rollout webapp -o json | jq -e '.status.phase=="Healthy" and .spec.template.spec.containers[0].image=="argoproj/rollouts-demo:yellow" and .status.updatedReplicas==.spec.replicas'; }
t07(){
  chk "Service webapp-canary existe" kubectl -n rollouts-demo get svc webapp-canary
  chk "AnalysisTemplate : plus de port 8080 dans la commande de test" t07_tpl
  chk "Aucune pause indéfinie dans les steps" t07_pause
  chkw "Rollout Healthy, image yellow entièrement promue" 240 t07_ok
}

# ---------- T08 CRD ----------
mkcr(){ cat <<EOF
apiVersion: platform.example.org/v1
kind: WebApp
metadata: {name: probe, namespace: default}
spec: {image: nginx, replicas: $1, tier: $2}
EOF
}
apply_cr(){ mkcr "$@" | kubectl apply --dry-run=server -f -; }
t08_ver(){ kubectl get crd webapps.platform.example.org -o json | jq -e '([.spec.versions[]|select(.storage)]|length)==1 and ([.spec.versions[]|select(.storage)][0].name=="v1")'; }
t08_meta(){ kubectl get crd webapps.platform.example.org -o json | jq -e '.spec.scope=="Namespaced" and (.spec.names.shortNames|index("wa")) and (.spec.versions[]|select(.name=="v1")|.subresources.status!=null and (.additionalPrinterColumns|length)>=3)'; }
t08(){
  chk "CRD Established" bash -c "kubectl get crd webapps.platform.example.org -o jsonpath='{.status.conditions[?(@.type==\"Established\")].status}' | grep -q True"
  chk "Une seule version de stockage : v1" t08_ver
  chk "Namespaced + shortName 'wa' + subresource status + >=3 printer columns" t08_meta
  chk "CR valide acceptée (replicas 2, bronze)" apply_cr 2 bronze
  chk "replicas 20 refusé (maximum 10)" not apply_cr 20 bronze
  chk "replicas 0 refusé (minimum 1)" not apply_cr 0 bronze
  chk "CEL : replicas 5 + tier silver refusé" not apply_cr 5 silver
  chk "CEL : replicas 5 + tier gold accepté" apply_cr 5 gold
  chk "tier hors enum refusé" not apply_cr 1 platinum
}

# ---------- T09 Opérateur ----------
t09_owner(){ kubectl -n team-gamma get deploy demo -o json | jq -e '.metadata.ownerReferences[0].kind=="WebApp"'; }
t09(){
  kubectl get crd webapps.platform.example.org >/dev/null 2>&1 && kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: platform.example.org/v1
kind: WebApp
metadata: {name: demo, namespace: team-gamma}
spec: {image: "nginx:1.27-alpine", replicas: 2, port: 80, tier: bronze}
EOF
  chk "Opérateur utilise le ServiceAccount webapp-operator" eq "$(kubectl -n platform-system get deploy webapp-operator -o jsonpath='{.spec.template.spec.serviceAccountName}')" webapp-operator
  chkw "Pod de l'opérateur Running" 90 bash -c "[ \"\$(kubectl -n platform-system get deploy webapp-operator -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
  chkw "Deployment 'demo' créé par l'opérateur (2 replicas prêts)" 120 bash -c "[ \"\$(kubectl -n team-gamma get deploy demo -o jsonpath='{.status.readyReplicas}')\" = 2 ]"
  chk "Deployment 'demo' a une ownerReference WebApp" t09_owner
  chk "Service 'demo' créé" kubectl -n team-gamma get svc demo
  chkw "status.readyReplicas = 2 sur la CR" 60 bash -c "[ \"\$(kubectl -n team-gamma get webapp demo -o jsonpath='{.status.readyReplicas}')\" = 2 ]"
}

# ---------- T10 Prometheus ----------
prom(){ kubectl get --raw "/api/v1/namespaces/monitoring/services/kps-kube-prometheus-stack-prometheus:9090/proxy$1"; }
t10_target(){ prom /api/v1/targets | jq -e '[.data.activeTargets[]|select(.labels.namespace=="shop-metrics" and .health=="up")]|length>=1'; }
t10_rule(){ prom /api/v1/rules | jq -e '[.data.groups[].rules[]|select(.name=="HighErrorRatio" and .health=="ok")]|length==1'; }
t10_alert(){ prom /api/v1/alerts | jq -e '[.data.alerts[]|select(.labels.alertname=="HighErrorRatio")]|length>=1'; }
t10(){
  chkw "Target shop-metrics/example-app UP dans Prometheus" 150 t10_target
  chkw "Règle HighErrorRatio chargée, health=ok" 150 t10_rule
  chkw "Alerte HighErrorRatio pending/firing" 180 t10_alert
}

# ---------- T11 Incident ----------
t11_ep(){ kubectl -n shop get endpointslices -l kubernetes.io/service-name=frontend -o json | jq -e '[.items[].endpoints[]?|select(.conditions.ready==true)]|length>=1'; }
t11(){
  chkw "checkout : disponible" 90 bash -c "[ \"\$(kubectl -n shop get deploy checkout -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
  chkw "cart : disponible (plus d'OOMKill)" 90 bash -c "[ \"\$(kubectl -n shop get deploy cart -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
  chkw "frontend : 2 replicas prêts" 90 bash -c "[ \"\$(kubectl -n shop get deploy frontend -o jsonpath='{.status.readyReplicas}')\" = 2 ]"
  chkw "Service frontend a des endpoints prêts" 60 t11_ep
}

# ---------- T12 Traces ----------
t12_send(){ kubectl -n tracing delete job grader-probe --ignore-not-found >/dev/null 2>&1
  kubectl -n tracing create -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata: {name: grader-probe, namespace: tracing}
spec:
  backoffLimit: 1
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: gen
        image: ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:v0.111.0
        args: ["traces","--otlp-endpoint","otel-collector:4317","--otlp-insecure","--traces","5","--service","grader-probe"]
EOF
  kubectl -n tracing wait --for=condition=complete job/grader-probe --timeout=60s; }
t12_jaeger(){ kubectl get --raw /api/v1/namespaces/tracing/services/jaeger:16686/proxy/api/services | jq -e '.data|index("grader-probe")'; }
t12_logs(){ kubectl -n tracing logs deploy/otel-collector --tail=500 | grep -q ResourceSpans; }
t12(){
  chkw "otel-collector prêt" 90 bash -c "[ \"\$(kubectl -n tracing get deploy otel-collector -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
  chk "Job de test (telemetrygen) via otel-collector:4317 réussi" t12_send
  chkw "Service 'grader-probe' visible dans Jaeger" 45 t12_jaeger
  chk "Spans visibles dans les logs du collector (debug exporter, verbosity detailed)" t12_logs
}

# ---------- T13 Istio ----------
code(){ kubectl -n mesh-demo exec deploy/"$1" -c curl -- curl -s -o /dev/null -w '%{http_code}' -m 5 http://server:5678; }
t13_side(){ kubectl -n mesh-demo get pods -o json | jq -e '[.items[]|select(.status.phase=="Running")|select(([.spec.containers[].name]+[(.spec.initContainers//[])[].name])|index("istio-proxy"))]|length>=3'; }
t13_strict(){ kubectl -n mesh-demo get peerauthentication -o json | jq -e '[.items[]|select(.spec.mtls.mode=="STRICT" and (.spec.selector==null))]|length>=1'; }
t13_allowed(){ [ "$(code client-allowed 2>/dev/null)" = 200 ]; }
t13_plain(){ kubectl -n default run plain-probe --rm -i --restart=Never --image=curlimages/curl:8.10.1 -- curl -sf -m 5 http://server.mesh-demo:5678; }
t13(){
  chk "Namespace mesh-demo : injection activée" eq "$(kubectl get ns mesh-demo -o jsonpath='{.metadata.labels.istio-injection}')" enabled
  chkw "Les 3 pods ont un sidecar istio-proxy" 90 t13_side
  chk "PeerAuthentication STRICT dans mesh-demo" t13_strict
  chkw "client-allowed -> server : HTTP 200" 60 t13_allowed
  chk "client-denied -> server : HTTP 403" eq "$(code client-denied 2>/dev/null)" 403
  chk "Client hors mesh (plaintext) rejeté" not t13_plain
}

# ---------- T14 RBAC ----------
t14_crb(){ kubectl get clusterrolebinding -o json | jq -e '[.items[]|select(.subjects[]?|.name=="ci-deployer")]|length>0'; }
t14(){
  SA=system:serviceaccount:apps-prod:ci-deployer
  chk "Plus de ClusterRoleBinding pour ci-deployer" not t14_crb
  chk "ci-deployer : create deployments (apps-prod)" can create deployments -n apps-prod --as $SA
  chk "ci-deployer : patch services (apps-prod)" can patch services -n apps-prod --as $SA
  chk "ci-deployer : PAS de lecture des secrets" not can get secrets -n apps-prod --as $SA
  chk "ci-deployer : PAS de delete deployments" not can delete deployments -n apps-prod --as $SA
  chk "ci-deployer : PAS d'accès hors apps-prod" not can create deployments -n default --as $SA
  chk "ci-deployer : PAS de list nodes" not can list nodes --as $SA
  chk "alice : get pods (apps-prod)" can get pods -n apps-prod --as alice
  chk "alice : PAS de lecture des secrets" not can get secrets -n apps-prod --as alice
  chk "alice : PAS de modification des deployments" not can patch deployments -n apps-prod --as alice
  chk "alice : PAS d'exec dans les pods" not can create pods/exec -n apps-prod --as alice
}

# ---------- T15 Kyverno ----------
mkdep(){ cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: $1, namespace: policy-demo}
spec:
  replicas: 1
  selector: {matchLabels: {app: $1}}
  template:
    metadata:
      labels:
        app: $1
$( [ "$3" = yes ] && echo "        team: probe" )
    spec:
      containers:
      - name: c
        image: $2
$( [ "$4" = yes ] && printf '        resources:\n          limits:\n            memory: 64Mi\n' )
EOF
}
dry(){ mkdep "$@" | kubectl apply --dry-run=server -f -; }
t15_enf(){ kubectl get cpol -o json | jq -e '[.items[]|select(.metadata.name|IN("require-team-label","disallow-latest-tag","require-memory-limit"))|.spec.rules[].validate.failureAction]|length>=4 and all(.=="Enforce")'; }
t15_rep(){ [ "$(kubectl -n policy-demo get policyreport -o json | jq '[.items[].summary.fail]|add // 0')" = 0 ]; }
t15(){
  chk "Les 3 ClusterPolicies sont en Enforce" t15_enf
  chk "Refus : image :latest" not dry p1 nginx:latest yes yes
  chk "Refus : image sans tag" not dry p2 nginx yes yes
  chk "Refus : label team absent" not dry p3 nginx:1.27-alpine no yes
  chk "Refus : limite mémoire absente" not dry p4 nginx:1.27-alpine yes no
  chk "Accepté : workload conforme" dry p5 nginx:1.27-alpine yes yes
  chkw "Deployment legacy remis en conformité et disponible" 90 bash -c "[ \"\$(kubectl -n policy-demo get deploy legacy -o jsonpath='{.status.readyReplicas}')\" = 1 ]"
  chkw "PolicyReport policy-demo : 0 échec" 150 t15_rep
}

# ---------- T16 Audit ----------
alog(){ sudo tail -n 3000 /var/log/kubernetes/audit/audit.log; }
t16_secret(){ alog | jq -e --arg n "$S" 'select(.objectRef.resource=="secrets" and .objectRef.name==$n and .verb=="create")|(.level=="Metadata" and (has("requestObject")|not) and (has("responseObject")|not))' | grep -q true; }
t16_cm(){ alog | jq -e --arg n "$C" 'select(.objectRef.resource=="configmaps" and .objectRef.name==$n and .verb=="create")|(.level=="Metadata" and (has("requestObject")|not))' | grep -q true; }
t16_role(){ alog | jq -e --arg n "$R" 'select(.objectRef.resource=="roles" and .objectRef.name==$n and .verb=="create")|(.level=="RequestResponse" and has("requestObject"))' | grep -q true; }
t16_recv(){ alog | jq -e 'select(.stage=="RequestReceived")' >/dev/null; }
t16_noise(){ alog | jq -e 'select(.requestURI|test("^/(healthz|livez|readyz|version)"))' >/dev/null; }
t16(){
  S=audit-probe-$RANDOM; C=audit-probe-cm-$RANDOM; R=audit-probe-role-$RANDOM
  kubectl create secret generic "$S" --from-literal=k=SUPERSECRET >/dev/null 2>&1
  kubectl create configmap "$C" --from-literal=k=v >/dev/null 2>&1
  kubectl create role "$R" --verb=get --resource=pods >/dev/null 2>&1
  sleep 5
  chk "Fichier de log d'audit présent" sudo test -s /var/log/kubernetes/audit/audit.log
  chk "Secrets : niveau Metadata, jamais de body" t16_secret
  chk "ConfigMaps : niveau Metadata" t16_cm
  chk "RBAC (roles) : niveau RequestResponse" t16_role
  chk "Stage RequestReceived omis" not t16_recv
  chk "Pas de bruit /healthz /livez /readyz /version" not t16_noise
  kubectl delete secret "$S" >/dev/null 2>&1; kubectl delete cm "$C" >/dev/null 2>&1; kubectl delete role "$R" >/dev/null 2>&1
}

# ---------- T17 Self-service ----------
t17_sync(){ kubectl get cpol tenant-bootstrap -o json | jq -e '[.spec.rules[].generate.synchronize]|length>=2 and all(.==true)'; }
t17(){
  chk "ClusterPolicy tenant-bootstrap : synchronize=true partout" t17_sync
  kubectl delete ns tenant-x --ignore-not-found --wait=true >/dev/null 2>&1
  # generate se déclenche à la création du namespace : on le crée directement avec le label
  kubectl apply -f - >/dev/null 2>&1 <<EOF
apiVersion: v1
kind: Namespace
metadata: {name: tenant-x, labels: {platform.example.org/tenant: "true"}}
EOF
  chkw "ResourceQuota tenant-quota générée" 60 kubectl -n tenant-x get resourcequota tenant-quota
  chkw "NetworkPolicy default-deny générée" 60 kubectl -n tenant-x get netpol default-deny
  kubectl -n tenant-x delete resourcequota tenant-quota >/dev/null 2>&1
  chkw "synchronize : quota supprimé -> recréé" 60 kubectl -n tenant-x get resourcequota tenant-quota
  kubectl delete ns tenant-x --wait=false >/dev/null 2>&1
}

run_task(){ local n=$1 pts=$2 title=$3; echo; echo "== T$n ($pts pts) $title"; _fail=0; "t$n"
  TOTAL=$((TOTAL+pts)); if [ $_fail = 0 ]; then SCORE=$((SCORE+pts)); echo "   => ${OK}OK${NC}"; else echo "   => ${KO}à corriger${NC}"; fi; }

declare -A META=(
 [01]="4|Multi-tenancy : quota / LimitRange" [02]="4|NetworkPolicy" [03]="3|Storage : StorageClass / PVC" [04]="4|Right-sizing + HPA"
 [05]="9|GitOps : Argo CD" [06]="8|CI/CD : Tekton" [07]="8|Progressive delivery : Argo Rollouts"
 [08]="9|CRD" [09]="9|Opérateur" [17]="7|Self-service : Kyverno generate"
 [10]="7|Monitoring : ServiceMonitor / PrometheusRule" [11]="7|Incident : diagnostic" [12]="6|Tracing : OTel Collector + Jaeger"
 [13]="4|Sécurité : mTLS Istio + AuthZ" [14]="3|Sécurité : RBAC" [15]="4|Sécurité : Kyverno admission" [16]="4|Sécurité : audit policy" )

if [ $# -gt 0 ]; then LIST=("$@"); else LIST=(01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17); fi
for n in "${LIST[@]}"; do n=$(printf '%02d' "$((10#$n))"); IFS='|' read -r pts title <<<"${META[$n]}"; run_task "$n" "$pts" "$title"; done
echo; echo "=========================================="
echo " SCORE : $SCORE / $TOTAL points"
echo "=========================================="
