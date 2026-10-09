# Monitoring

The local platform uses Prometheus to collect and store Kubernetes metrics and
Grafana to display them.

The verified baseline includes development workload CPU and memory dashboards,
persistent storage, and recovery of metric history after a Prometheus pod
replacement.

## Components

| Component | Responsibility |
| --- | --- |
| Prometheus | Scrapes metrics, evaluates rules, and stores time series. |
| Grafana | Queries Prometheus and displays dashboards. |
| Prometheus Operator | Manages Prometheus resources inside Kubernetes. |
| kube-state-metrics | Reports Kubernetes object state, including configured resource requests and limits. |
| Node exporter | Reports operating-system metrics for the Kubernetes node. |

This installation monitors the local kind cluster. It does not currently
collect application-specific HTTP request counts, latency, or error rates.

## Installation configuration

| Setting | Value |
| --- | --- |
| Kubernetes context | `kind-internal-developer-platform` |
| Namespace | `monitoring` |
| Helm release | `monitoring` |
| Chart | `prometheus-community/kube-prometheus-stack` |
| Chart version | `92.2.0` |
| Prometheus replicas | `1` |
| Scrape interval | `30s` |
| Evaluation interval | `30s` |
| Time retention | `24h` |
| Size retention | `1GiB` |
| Prometheus storage | `2Gi`, using storage class `standard` |
| Grafana storage | `1Gi`, using storage class `standard` |
| Alertmanager | Disabled |

Retention is bounded by both time and size. Prometheus may remove older data
before 24 hours when its size threshold is reached.

The configuration is stored in:

- [Namespace manifest](../platform/components/monitoring/namespace.yaml)
- [Helm values](../platform/components/monitoring/values.yaml)
- [Installation script](../platform/components/monitoring/install.sh)

Monitoring is installed and upgraded through Helm. The current Argo CD
applications manage the development environment and reference service; they do
not reconcile this Helm release.

## Resource budgets

The main containers use these configured budgets:

| Container | CPU request | CPU limit | Memory request | Memory limit |
| --- | --- | --- | --- | --- |
| Prometheus | `200m` | `1000m` | `512Mi` | `1Gi` |
| Grafana | `100m` | `500m` | `512Mi` | `1Gi` |
| Prometheus Operator | `100m` | `500m` | `128Mi` | `256Mi` |
| kube-state-metrics | `50m` | `250m` | `64Mi` | `128Mi` |
| Node exporter | `50m` | `250m` | `32Mi` | `64Mi` |

The values file also specifies budgets for configuration reloaders and Grafana
sidecars.

Grafana has a startup probe that allows approximately ten minutes for
initialization before startup failures trigger a restart. Once startup succeeds,
its normal readiness and liveness probes take over.

## Install or upgrade

Run commands from the repository root. Helm and kubectl must be available, and
the kind cluster must be running.

For a new installation, create the namespace:

```bash
kubectl apply \
  --context kind-internal-developer-platform \
  -f platform/components/monitoring/namespace.yaml
```

Grafana uses an existing Kubernetes Secret named `monitoring-grafana-admin`.
Create it once for a new installation:

```bash
read -r -s -p "Choose Grafana admin password: " GRAFANA_ADMIN_PASSWORD
printf '\n'

kubectl create secret generic monitoring-grafana-admin \
  --namespace monitoring \
  --context kind-internal-developer-platform \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"

unset GRAFANA_ADMIN_PASSWORD
```

Keep the credential outside Git. For an existing installation, reuse the
existing Secret.

Check the script syntax and render the pinned chart:

```bash
bash -n platform/components/monitoring/install.sh

helm template monitoring prometheus-community/kube-prometheus-stack \
  --version 92.2.0 \
  --namespace monitoring \
  --kube-version 1.35.0 \
  --include-crds \
  --values platform/components/monitoring/values.yaml \
  > /tmp/idp-monitoring-rendered.yaml
```

Rendering checks template generation; it does not confirm runtime readiness.

Install or upgrade:

```bash
bash platform/components/monitoring/install.sh
```

The script waits up to fifteen minutes for the release to become ready.

## Verify the installation

```bash
helm status monitoring \
  --namespace monitoring \
  --kube-context kind-internal-developer-platform

kubectl get pods \
  --namespace monitoring \
  --context kind-internal-developer-platform

kubectl get pvc \
  --namespace monitoring \
  --context kind-internal-developer-platform
```

Expected results:

- Helm reports `STATUS: deployed`.
- Grafana reports `3/3 Running`.
- Prometheus reports `2/2 Running`.
- Operator, kube-state-metrics, and node exporter are ready.
- The Grafana and Prometheus persistent volume claims are `Bound`.

Temporary admission webhook jobs may appear during installation or upgrade.
A successful job reports `Completed`.

## Access Grafana from Windows

Find the current WSL address:

```bash
hostname -I
```

Set `WSL_IP` to the WSL IPv4 address. The address below was used during initial
verification; update it if WSL assigns a different address.

```bash
WSL_IP=172.17.157.237

kubectl port-forward \
  --namespace monitoring \
  --context kind-internal-developer-platform \
  --address "$WSL_IP" \
  service/monitoring-grafana \
  3000:80
```

Keep that terminal running. Open `http://<WSL_IP>:3000` in Windows Chrome.

Log in as `admin` using the password chosen when creating
`monitoring-grafana-admin`.

The Helm chart's generic notes may show a different generated Secret name.
This installation uses the explicitly configured existing Secret.

Stopping port forwarding closes browser access without uninstalling Grafana.
After a pod replacement or a lost connection, start port forwarding again.

## Verify development dashboards

In Grafana:

1. Open **Dashboards**.
2. Search for **Compute Resources**.
3. Open **Kubernetes / Compute Resources / Namespace (Pods)**.
4. Select namespace **development**.
5. Select **Last 15 minutes** and refresh.

CPU and memory utilisation panels compare actual usage with configured requests
and limits.

During initial verification, the reference service showed:

| Panel | Observed value |
| --- | --- |
| CPU utilisation from requests | `0.992%` |
| CPU utilisation from limits | `0.198%` |
| Memory utilisation from requests | `62.0%` |
| Memory utilisation from limits | `31.0%` |

These were observations at one point in time, not expected fixed values.

With the service's configured budgets, they represented approximately `1m` CPU
and `39.7Mi` memory usage.

## Inspect underlying metrics

PromQL expressions belong in **Grafana → Explore → Prometheus → Code**.
They are not Bash commands.

Configured requests:

```promql
kube_pod_container_resource_requests{
  namespace="development",
  container="reference-service"
}
```

Configured limits:

```promql
kube_pod_container_resource_limits{
  namespace="development",
  container="reference-service"
}
```

CPU usage in cores:

```promql
rate(container_cpu_usage_seconds_total{
  namespace="development",
  container="reference-service"
}[5m])
```

Memory working set in bytes:

```promql
container_memory_working_set_bytes{
  namespace="development",
  container="reference-service"
}
```

Kubelet scrape status:

```promql
up{job="kubelet"}
```

During verification, the `/metrics`, `/metrics/cadvisor`, and `/metrics/probes`
targets each returned `1`.

A successful scrape confirms endpoint collection. Check individual metrics
separately when investigating missing dashboard data.

## Verify metric-history recovery

This procedure briefly interrupts Prometheus collection while its pod is
replaced. The persistent volume claim remains in place.

First, run this query in Grafana Explore:

```promql
kube_pod_container_resource_requests{
  namespace="development",
  container="reference-service",
  resource="cpu"
} offset 30m
```

Confirm that historical data exists. During initial verification, it returned
`0.1`.

In a separate WSL terminal, replace the Prometheus pod:

```bash
kubectl delete pod prometheus-monitoring-kube-prometheus-prometheus-0 \
  --namespace monitoring \
  --context kind-internal-developer-platform

kubectl get pods \
  --namespace monitoring \
  --context kind-internal-developer-platform \
  --watch
```

Wait for Prometheus to return to `2/2 Running`, then stop watching with Ctrl+C.

Promptly rerun the historical query. Complete the comparison within thirty
minutes so the query still reaches data from before the replacement.

During initial verification:

- Kubernetes recreated the Prometheus pod.
- The replacement reached `2/2 Running` in approximately sixteen seconds.
- The historical query still returned `0.1`.
- Grafana remained ready.

This verified metric-history retention across a pod replacement. It did not
verify recovery from deletion of the persistent volume or the kind cluster.

## Troubleshooting

### Grafana restarts or disconnects

Inspect the pod and its main container's previous logs:

```bash
kubectl describe pods \
  --namespace monitoring \
  --context kind-internal-developer-platform \
  --selector app.kubernetes.io/name=grafana,app.kubernetes.io/instance=monitoring

kubectl logs deployment/monitoring-grafana \
  --container grafana \
  --previous \
  --tail=60 \
  --namespace monitoring \
  --context kind-internal-developer-platform
```

During initial setup, Grafana reported `OOMKilled` with a `256Mi` memory limit.
Increasing its memory request to `512Mi` and limit to `1Gi` resolved the observed
restarts. It subsequently remained ready with zero restarts during an extended
dashboard session.

Exit code `137` alone does not establish an out-of-memory cause. Inspect the
termination reason and events.

A startup probe allows more initialization time; it does not prevent an
out-of-memory termination.

### Dashboard shows No data

Check the selected data source, namespace, and time range. In particular,
confirm that the development workload dashboard is using `development`.

Use Explore to check raw metrics and the panel's precomputed metrics. A
`No data` result alone does not mean the workload has stopped.

### Helm reports failed

Inspect pod readiness, events, and logs. Resources may remain installed after
a readiness timeout.

Correct the values file and rerun the installation script to upgrade the
existing release.

## Current limits

- This is a single-node local environment.
- Monitoring configuration is versioned in Git but applied through Helm.
- The Grafana credential is a manually provisioned Kubernetes Secret.
- Local-path storage supports pod replacement but is not a backup.
- Node exporter describes the kind node, not the Windows host as a whole.
- Application-specific HTTP metrics have not been implemented.
- External alert notification delivery is not configured.
- Backup restoration and recovery after cluster loss have not been verified.
