<p align="center">
  <strong>INTERNAL DEVELOPER PLATFORM &nbsp;·&nbsp; LOCAL ENVIRONMENT</strong>
</p>

<h1 align="center">Local Development</h1>

<p align="center">
  Build an image. Deploy a service. Verify the running system.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/cluster-kind-326CE5?style=flat-square" alt="Cluster: kind">
  <img src="https://img.shields.io/badge/workload-reference_service-7357D9?style=flat-square" alt="Workload: reference service">
  <img src="https://img.shields.io/badge/health-readiness_%2B_liveness-188F89?style=flat-square" alt="Health checks: readiness and liveness">
</p>

<p align="center">
  <img src="assets/local-cluster.gif" width="960" alt="Animated local setup path: Docker Engine, kind, Kubernetes, and a kubectl readiness check">
</p>

<p align="center">
  <a href="../README.md">Overview</a> &nbsp;·&nbsp;
  <a href="architecture.md">Architecture</a> &nbsp;·&nbsp;
  <a href="#create-the-cluster">Cluster</a> &nbsp;·&nbsp;
  <a href="#build-and-load-the-image">Build</a> &nbsp;·&nbsp;
  <a href="#deploy-the-reference-service">Deploy</a> &nbsp;·&nbsp;
  <a href="#verify-the-service">Verify</a> &nbsp;·&nbsp;
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

This guide reproduces the current local platform baseline: a dedicated kind cluster running the **reference service** in the **development** namespace, with an internal Service and HTTP readiness and liveness probes.

The workflow is **build → load → deploy → verify**. Image building, loading, and deployment are currently manual. CI, registry publishing, and GitOps reconciliation remain part of the [target architecture](architecture.md).

## Environment at a glance

| Item | Value |
| --- | --- |
| Cluster | `internal-developer-platform` |
| kubectl context | `kind-internal-developer-platform` |
| Namespace | `development` |
| Deployment and Service | `reference-service` |
| Application image | `reference-service:0.1.0` |
| Application port | `8080` |
| Local URL during port-forwarding | `http://127.0.0.1:8080` |
| Health endpoint | `/health` |

The baseline was verified with **kind v0.31.0** and **Kubernetes v1.35.0**. Generated Pod names and IP addresses vary between deployments.

## How the pieces fit

| Component | Responsibility |
| --- | --- |
| Application source | Defines the HTTP routes and dependency versions. |
| Docker image | Packages Python, dependencies, application code, and the startup command. |
| Docker Engine | Builds the image and runs the container that acts as the kind node. |
| kind | Creates the local Kubernetes cluster and loads application images into its node. |
| Deployment | Maintains the desired application Pod and its health checks. |
| Service | Gives matching Pods a stable internal address and DNS name. |
| kubectl context | Selects which cluster receives a command. |

Application files live in `apps/reference-service/`. Kubernetes configuration for this environment lives in `platform/environments/development/`.

## Prerequisites

Use a Bash terminal with **Git, Docker, kind, kubectl, and curl** available. Docker must be running. Initial setup also needs network access to obtain the node image, Python base image, and application dependencies.

Check Docker connectivity. A working connection shows both **Client** and **Server** sections:

```bash
docker version
```

Check the installed kind and kubectl client versions:

```bash
kind version
kubectl version --client
```

Run the remaining commands from the **repository root**. For a fresh checkout, clone the repository:

```bash
git clone https://github.com/Rano1000/internal-developer-platform.git
```

Then enter the directory created by Git:

```bash
cd internal-developer-platform
```

If your terminal is already at the repository root, continue with cluster setup.

## Create the cluster

List existing kind clusters to check whether this project's cluster already exists:

```bash
kind get clusters
```

If `internal-developer-platform` is absent, create it. `--name` gives it a dedicated identity:

```bash
kind create cluster --name internal-developer-platform
```

kind creates one control-plane node by default and registers the context `kind-internal-developer-platform`. The installed kind release selects the default Kubernetes node image. A kind configuration file can be introduced when topology or networking requirements change. [kind setup documentation](https://kind.sigs.k8s.io/docs/user/quick-start/#creating-a-cluster)

## Verify the cluster

Query the intended cluster explicitly. `--context` keeps commands directed at this project when several clusters share a kubeconfig:

```bash
kubectl get nodes --context kind-internal-developer-platform
```

Expect `internal-developer-platform-control-plane` with status **Ready** before deploying the workload. If the connection is refused, use the recovery steps under [Troubleshooting](#troubleshooting).

## Build and load the image

Build the reference-service image from its application directory. `-t` assigns the name and version; the final argument supplies the build context, including its Dockerfile and `.dockerignore`:

```bash
docker build --progress=plain -t reference-service:0.1.0 apps/reference-service
```

The Dockerfile supplies the Python runtime and installs the pinned application dependencies. It starts Gunicorn on port `8080` and runs the application as `appuser`, UID `10001`. The `.dockerignore` excludes the local virtual environment, Python caches, and local environment files from the build context. [Docker build context documentation](https://docs.docker.com/build/concepts/context/)

List the image to confirm it exists in Docker's local image store:

```bash
docker image ls reference-service:0.1.0
```

Load it into this named kind cluster. Docker's host image store and the node's image store are separate:

```bash
kind load docker-image reference-service:0.1.0 --name internal-developer-platform
```

The Deployment uses `imagePullPolicy: IfNotPresent`, allowing the node to use the loaded image. Loading makes the image available; the Deployment creates the application Pod. [kind image-loading documentation](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)

<details>
<summary><strong>Inspect the image inside the node</strong></summary>

Run `crictl images` inside the node container to list images available to Kubernetes:

```bash
docker exec internal-developer-platform-control-plane crictl images
```

Expect a row for `docker.io/library/reference-service` with tag `0.1.0`. That name is the normalized image reference; this step does not publish an image to Docker Hub.

</details>

## Deploy the reference service

Create or update the development namespace first. `-f` tells kubectl which manifest to read:

```bash
kubectl apply --context kind-internal-developer-platform -f platform/environments/development/namespace.yaml
```

Apply the Deployment to establish the image, replica count, container port, and health checks:

```bash
kubectl apply --context kind-internal-developer-platform -f platform/environments/development/reference-service/deployment.yaml
```

Apply the Service to create a stable internal destination for Pods labeled `app: reference-service`:

```bash
kubectl apply --context kind-internal-developer-platform -f platform/environments/development/reference-service/service.yaml
```

Wait for the Deployment to become available. The timeout limits this command's waiting period:

```bash
kubectl rollout status deployment/reference-service --namespace development --context kind-internal-developer-platform --timeout=60s
```

A successful result reports `deployment "reference-service" successfully rolled out`. Reapplying the same manifests is supported: kubectl updates existing resources to match their declared configuration.

## Verify the service

### Check the Pod and Service

List the application's Pods. The selector matches the label declared in the Deployment's Pod template:

```bash
kubectl get pods --namespace development --context kind-internal-developer-platform --selector app=reference-service
```

Expect **Running** and **1/1** under READY.

Inspect the Service's assigned address and port:

```bash
kubectl get service reference-service --namespace development --context kind-internal-developer-platform
```

Expect **ClusterIP** and **8080/TCP**. An external IP of `<none>` is expected for this internal Service. [Kubernetes Service documentation](https://kubernetes.io/docs/concepts/services-networking/service/#type-clusterip)

Inspect its EndpointSlices to see the Pod addresses associated with the Service:

```bash
kubectl get endpointslices --namespace development --context kind-internal-developer-platform --selector kubernetes.io/service-name=reference-service
```

With the current one-replica Deployment ready, expect a Pod address and port **8080**.

### Test the internal Service route

Execute a Python HTTP request inside an application Pod selected through the Deployment. The `--` separates kubectl options from the command run inside the container. Python's standard library supplies the HTTP client:

```bash
kubectl exec --context kind-internal-developer-platform --namespace development deployment/reference-service -- python -c '
from urllib.request import urlopen

with urlopen("http://reference-service:8080/health", timeout=5) as response:
    print("HTTP", response.status)
    print(response.read().decode())
'
```

The request uses the Service's DNS name from the same namespace. A successful response verifies name resolution, Service routing, and the health endpoint:

```text
HTTP 200
{"status":"healthy"}
```

### Access the application locally

Open a temporary tunnel to an application Pod selected through the Deployment. `--address 127.0.0.1` binds the local listener to loopback; `8080:8080` maps local port 8080 to the container's port 8080:

```bash
kubectl port-forward --context kind-internal-developer-platform --namespace development --address 127.0.0.1 deployment/reference-service 8080:8080
```

Keep that terminal open. In a second terminal, request the root endpoint. `-i` includes the HTTP response headers:

```bash
curl -i http://127.0.0.1:8080/
```

Expect **HTTP 200** and this JSON body:

```json
{"service":"reference-service","version":"0.1.0"}
```

Request the health endpoint through the same tunnel:

```bash
curl -i http://127.0.0.1:8080/health
```

Expect **HTTP 200** and `{"status":"healthy"}`.

Press **Ctrl+C** in the forwarding terminal to close the tunnel. The application keeps running. Restart the forwarding command if its selected Pod is replaced. Port-forwarding provides direct Pod access; the earlier in-cluster request verifies the Service route. [kubectl port-forward documentation](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_port-forward/)

## Inspect the health checks

Both probes call the application's `/health` endpoint on the named `http` port, which maps to container port 8080.

| Setting | Readiness | Liveness |
| --- | --- | --- |
| Initial delay | 5 seconds | 10 seconds |
| Check interval | 5 seconds | 10 seconds |
| Request timeout | 2 seconds | 2 seconds |
| Consecutive failure threshold | 3 | 3 |
| Failure action | Mark the Pod unready for matching Service traffic | Restart the failing container |

Readiness controls traffic eligibility. Liveness provides recovery after repeated failures. The probes run independently; liveness does not wait for readiness to succeed. These HTTP probes use the response status to determine success. [Kubernetes probe documentation](https://kubernetes.io/docs/concepts/workloads/pods/probes/)

Inspect the running Pod's configuration, conditions, restart count, and events:

```bash
kubectl describe pods --namespace development --context kind-internal-developer-platform --selector app=reference-service
```

Look for the **Liveness** and **Readiness** settings above and **Ready: True**. The displayed `#success=1` and `#failure=3` values are thresholds. **Restart Count** records actual container restarts in the current Pod.

Read the last 15 application log lines. Gunicorn writes HTTP access logs to standard output, making probe requests visible through kubectl:

```bash
kubectl logs deployment/reference-service --namespace development --context kind-internal-developer-platform --tail=15
```

Successful probe requests show `GET /health`, status **200**, and a user agent beginning with `kube-probe/`.

## Troubleshooting

<details>
<summary><strong>Connection refused after the environment has been stopped</strong></summary>

First confirm that Docker is running and reachable:

```bash
docker version
```

Inspect this cluster's node container, including stopped containers. `-a` includes all states, and the filter narrows the listing by name:

```bash
docker ps -a --filter name=internal-developer-platform-control-plane
```

If the named container exists with status **Exited**, start that existing node:

```bash
docker start internal-developer-platform-control-plane
```

Allow Kubernetes to recover, then check the node:

```bash
kubectl get nodes --context kind-internal-developer-platform
```

Once the node is **Ready**, repeat the Pod and Service checks. If the node container is absent, recreate the cluster and repeat image loading and manifest application.

</details>

<details>
<summary><strong>ImagePullBackOff or ErrImagePull</strong></summary>

Check that `reference-service:0.1.0` exists in Docker, then repeat the image-loading step for `internal-developer-platform`. The image name and tag must match the Deployment.

Use the Pod description from [Inspect the health checks](#inspect-the-health-checks) to read the exact failure under **Events**.

</details>

<details>
<summary><strong>Local port 8080 is already in use</strong></summary>

Stop the earlier local application or forwarding process if it is no longer needed. Alternatively, map local port **8081** to the application's unchanged container port **8080**:

```bash
kubectl port-forward --context kind-internal-developer-platform --namespace development --address 127.0.0.1 deployment/reference-service 8081:8080
```

Use `http://127.0.0.1:8081/` and `http://127.0.0.1:8081/health` while this tunnel is open.

</details>

<details>
<summary><strong>Rollout timeout or Pod not ready</strong></summary>

Inspect the Pod description and application logs using the commands above. **Events** identify image, scheduling, and probe failures; logs show application startup and request handling.

The rollout command timing out ends its wait. Kubernetes continues managing the Deployment.

</details>

## Remove the local cluster

<details>
<summary><strong>Delete this local environment</strong></summary>

The following command removes the named cluster, including its workloads and data. Repository files remain available:

```bash
kind delete cluster --name internal-developer-platform
```

To restore the baseline afterward, recreate the cluster, load the image again, and reapply the namespace, Deployment, and Service.

</details>

---

<p align="center">
  <strong>Local baseline: one service, a stable internal address, and two health checks.</strong><br>
  <a href="architecture.md">Explore the target platform architecture</a>
</p>
