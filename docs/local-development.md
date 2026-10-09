<p align="center">
  <strong>INTERNAL DEVELOPER PLATFORM &nbsp;·&nbsp; LOCAL ENVIRONMENT</strong>
</p>

<h1 align="center">Local Development</h1>

<p align="center">
  Run the platform locally. Release through Git. Verify the running system.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/cluster-kind-326CE5?style=flat-square" alt="Cluster: kind">
  <img src="https://img.shields.io/badge/registry-GHCR-7357D9?style=flat-square" alt="Registry: GitHub Container Registry">
  <img src="https://img.shields.io/badge/delivery-Argo_CD-188F89?style=flat-square" alt="Delivery: Argo CD">
  <img src="https://img.shields.io/badge/reconciliation-auto_sync_%2B_self_heal-326CE5?style=flat-square" alt="Reconciliation: automated sync and self-healing">
</p>

<p align="center">
  <img src="assets/local-cluster.gif" width="960" alt="Animated local cluster foundation: Docker Engine, kind, Kubernetes, and kubectl verification">
</p>

<p align="center">
  <a href="../README.md">Overview</a> &nbsp;·&nbsp;
  <a href="architecture.md">Architecture</a> &nbsp;·&nbsp;
  <a href="#create-and-verify-the-cluster">Cluster</a> &nbsp;·&nbsp;
  <a href="#bootstrap-argo-cd">Bootstrap</a> &nbsp;·&nbsp;
  <a href="#verify-the-reference-service">Verify</a> &nbsp;·&nbsp;
  <a href="#release-through-git">Release</a> &nbsp;·&nbsp;
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## Operating model

This guide provisions a local Kubernetes environment and connects the reference service to GitOps delivery.

**GitHub Actions builds and checks the container image. GHCR stores the published image. Argo CD reconciles the Kubernetes workload with its configuration in Git.**

The initial cluster and Argo CD installation are bootstrapped with kubectl. After the Application is registered, routine workload changes flow through Git.

> **Release selection is explicit.** Publishing an image to GHCR does not change the running workload. A deployment change must select that image in Git.

## Environment at a glance

| Item | Baseline |
| --- | --- |
| Cluster | `internal-developer-platform` |
| kubectl context | `kind-internal-developer-platform` |
| Topology | One control-plane node |
| Workload namespace | `development` |
| Platform namespace | `argocd` |
| Deployment and Service | `reference-service` |
| Argo CD Application | `reference-service-development` |
| Container registry | `ghcr.io/rano1000/reference-service` |
| Image selection | Explicit image reference in the Deployment manifest |
| Application port | `8080` |
| Application tunnel | `http://127.0.0.1:8080` |
| Argo CD tunnel | `https://127.0.0.1:8443` |
| Automated sync | Enabled |
| Self-healing | Enabled |
| Automated pruning | Disabled |

The baseline was verified with **kind v0.31.0**, **Kubernetes v1.35.0**, and **Argo CD v3.5.4**. Pod names and IP addresses are assigned at runtime.

This is a local development environment. Production availability, scoped platform access, enforced network isolation, and observability remain separate platform increments.

## How the pieces fit

| Component | Responsibility |
| --- | --- |
| Application source | Defines the HTTP routes and dependencies. |
| Dockerfile | Describes how to package and start the application. |
| GitHub Actions | Builds the image, starts a container, and checks HTTP endpoints. |
| GHCR | Stores images published by successful main-branch workflow runs. |
| Docker Engine | Runs the container that acts as the kind node. |
| kind | Creates the local Kubernetes cluster. |
| Argo CD Application | Connects a Git directory to a destination cluster and namespace. |
| Deployment | Maintains the declared replicas and container configuration. |
| Service | Provides an internal address for matching, ready Pods. |
| Health probes | Control traffic eligibility and container recovery. |

### Configuration locations

| Path | Purpose |
| --- | --- |
| `apps/reference-service/` | Application source and container build files |
| `.github/workflows/reference-service-ci.yaml` | Build, endpoint checks, and registry publishing |
| `platform/components/argocd/` | Argo CD installation configuration |
| `platform/applications/reference-service-development.yaml` | GitOps assignment and sync policy |
| `platform/environments/development/namespace.yaml` | Development namespace |
| `platform/environments/development/reference-service/` | Workload Deployment and Service |

The Application watches the workload directory. It does not manage its own definition, the development namespace manifest, or the Argo CD installation.

## Prerequisites

Use a Bash terminal with **Git, Docker, kind, kubectl, and curl** available. On Windows, run the Bash commands in WSL with Docker Desktop integration enabled.

Network access is required to download cluster images, Argo CD manifests, and workload images.

Check that Docker is reachable:

```bash
docker version
```

Expect both **Client** and **Server** sections.

Check the installed Kubernetes tools:

```bash
kind version
kubectl version --client
```

Run the remaining Bash commands from the **repository root**.

For a fresh checkout, download the repository:

```bash
git clone https://github.com/Rano1000/internal-developer-platform.git
```

Enter the directory created by Git:

```bash
cd internal-developer-platform
```

If the repository is already open in your terminal, continue below.

> **Using a fork:** update the Application's repository URL to your fork. To publish your own images, also update the workflow's registry image name and select your published image in the Deployment.

## Create and verify the cluster

List existing clusters before creating another one:

```bash
kind get clusters
```

If `internal-developer-platform` is absent, create it:

```bash
kind create cluster --name internal-developer-platform
```

kind creates a single node and registers the context `kind-internal-developer-platform`. Its default Kubernetes version depends on the installed kind release.

Verify the intended node:

```bash
kubectl get nodes --context kind-internal-developer-platform
```

Expect `internal-developer-platform-control-plane` with status **Ready**.

Every cluster command in this guide uses an explicit context to select this project.

## Bootstrap Argo CD

### Create the workload namespace

Apply the namespace manifest. `-f` selects a single manifest file:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/environments/development/namespace.yaml
```

The `development` namespace contains the reference-service workload. Argo CD runs separately in `argocd`.

### Install the platform component

Apply the Argo CD configuration directory:

```bash
kubectl apply --context kind-internal-developer-platform \
  --server-side --force-conflicts \
  -k platform/components/argocd
```

`-k` uses Kustomize to assemble the namespace manifest and the pinned upstream installation.

Server-side apply avoids the annotation-size limit of client-side apply for large CRDs. `--force-conflicts` takes ownership of conflicting fields; review local customizations before reapplying installation manifests.

Wait for the Argo CD Deployments to become available:

```bash
kubectl wait --context kind-internal-developer-platform \
  --namespace argocd --for=condition=Available \
  deployment --all --timeout=180s
```

Then wait for its application controller:

```bash
kubectl rollout status statefulset/argocd-application-controller \
  --namespace argocd --context kind-internal-developer-platform \
  --timeout=180s
```

Inspect the Pods:

```bash
kubectl get pods --namespace argocd \
  --context kind-internal-developer-platform
```

Continue when the components are ready.

### Register the reference service

Apply the Application definition:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/applications/reference-service-development.yaml
```

The Application selects:

| Setting | Value |
| --- | --- |
| Repository | `https://github.com/Rano1000/internal-developer-platform.git` |
| Branch | `main` |
| Manifest directory | `platform/environments/development/reference-service` |
| Destination API | `https://kubernetes.default.svc` |
| Destination namespace | `development` |

The destination API address identifies the cluster where Argo CD runs. It is not the dashboard URL.

Inspect reconciliation status:

```bash
kubectl get application reference-service-development \
  --namespace argocd --context kind-internal-developer-platform
```

The expected settled state is:

```text
NAME                            SYNC STATUS   HEALTH STATUS
reference-service-development   Synced        Healthy
```

Initial reconciliation may take time. `Synced` reports configuration agreement; `Healthy` reports Argo CD's resource health assessment.

The node pulls the image selected in the Deployment from GHCR when it is not already available. Manual image loading is not required for this delivery path.

## Verify the reference service

### Inspect the workload

Once Argo CD has created the Deployment, wait for its rollout:

```bash
kubectl rollout status deployment/reference-service \
  --namespace development --context kind-internal-developer-platform \
  --timeout=120s
```

List matching Pods:

```bash
kubectl get pods --namespace development \
  --context kind-internal-developer-platform \
  --selector app=reference-service
```

With the baseline replica count, expect one Pod showing **Running** and **1/1** ready.

Inspect the Service:

```bash
kubectl get service reference-service --namespace development \
  --context kind-internal-developer-platform
```

Expect type **ClusterIP** and port **8080/TCP**. An external IP of `<none>` is normal for this internal Service.

Inspect its backing endpoints:

```bash
kubectl get endpointslices --namespace development \
  --context kind-internal-developer-platform \
  --selector kubernetes.io/service-name=reference-service
```

Expect the application Pod's address and port **8080**.

### Test the internal Service route

Run an HTTP client inside an application Pod. `--` separates kubectl options from the container command:

```bash
kubectl exec --context kind-internal-developer-platform \
  --namespace development deployment/reference-service -- python -c '
from urllib.request import urlopen

for path in ("/health", "/"):
    with urlopen("http://reference-service:8080" + path, timeout=5) as response:
        print(path, "HTTP", response.status)
        print(response.read().decode())
'
```

Expected responses:

```text
/health HTTP 200
{"status":"healthy"}

/ HTTP 200
{"service":"reference-service","version":"0.1.0"}
```

This request verifies Service DNS resolution, routing, and application responses from inside the cluster.

### Access the application locally

Start a temporary tunnel using the Service to select an application Pod:

```bash
kubectl port-forward --context kind-internal-developer-platform \
  --namespace development --address 127.0.0.1 \
  service/reference-service 8080:8080
```

`8080:8080` maps local port 8080 to the Service port. Keep this terminal running.

In a second terminal, request the root endpoint:

```bash
curl -i http://127.0.0.1:8080/
```

Check health:

```bash
curl -i http://127.0.0.1:8080/health
```

Both should return **HTTP 200**.

Port-forwarding tunnels to a selected Pod; it does not test the Service's ClusterIP routing. The earlier in-cluster request covers that path.

Press **Ctrl+C** in the forwarding terminal to close the tunnel. The workload continues running. Restart forwarding if its selected Pod is replaced.

## Access the Argo CD dashboard

Forward local port 8443 to the Argo CD server's HTTPS port:

```bash
kubectl port-forward --context kind-internal-developer-platform \
  --namespace argocd --address 127.0.0.1 \
  service/argocd-server 8443:443
```

Open **https://127.0.0.1:8443/** in your browser. Keep the forwarding terminal running.

The installation uses a self-signed certificate. A certificate warning is expected for this local endpoint.

### First login

For a fresh installation, retrieve the initial password locally:

```bash
kubectl get secret argocd-initial-admin-secret \
  --namespace argocd --context kind-internal-developer-platform \
  -o jsonpath='{.data.password}' | base64 --decode
```

Sign in as `admin`. Change the password through **User Info → Update Password**, then remove the initial-password Secret:

```bash
kubectl delete secret argocd-initial-admin-secret \
  --namespace argocd --context kind-internal-developer-platform
```

Keep credentials out of Git and shared command outputs. On an existing installation, use the password already configured.

<details>
<summary><strong>Windows browser cannot reach the WSL localhost tunnel</strong></summary>

First check the endpoint from WSL:

```bash
curl -k -I --max-time 5 https://127.0.0.1:8443/
```

`-k` skips certificate verification for this local diagnostic.

Then run the same check from Windows PowerShell:

```powershell
curl.exe -k -I --max-time 5 https://127.0.0.1:8443/
```

If WSL returns HTTP 200 while Windows cannot connect, stop the existing forwarding command with **Ctrl+C**.

Find the WSL address:

```bash
hostname -I
```

Select the WSL IPv4 address. Replace `WSL_IPV4_ADDRESS` below with that address:

```bash
kubectl port-forward --context kind-internal-developer-platform \
  --namespace argocd --address WSL_IPV4_ADDRESS \
  service/argocd-server 8443:443
```

Open `https://WSL_IPV4_ADDRESS:8443/` in Windows using the same address.

This binds the listener to the WSL interface. The address can change after WSL restarts; retrieve it again when needed.

</details>

## Release through Git

<p align="center">
  <img src="assets/delivery-flow.gif" width="960" alt="Target delivery path from Git through CI, registry, Argo CD, Kubernetes, and metrics">
</p>

<p align="center">
  <sub>CI, registry publishing, and GitOps reconciliation are implemented. Metrics and dashboards are planned.</sub>
</p>

### Build and publish

The [reference-service workflow](../.github/workflows/reference-service-ci.yaml) runs for pushes to `main`, pull requests targeting `main`, and manual dispatch.

It builds an image, starts a container, checks `/health` and `/`, and captures application logs.

Successful eligible main-branch runs publish the tested image to GHCR with the full Git commit SHA as its tag. Pull-request runs do not publish.

The endpoint checks currently validate HTTP success; they do not assert the JSON response contents.

### Select a release

Choose a published image from the [reference-service package](https://github.com/Rano1000/internal-developer-platform/pkgs/container/reference-service).

Open the Deployment manifest:

```bash
nano platform/environments/development/reference-service/deployment.yaml
```

Set its `image` field to the complete GHCR reference for the chosen tag. Review the change:

```bash
git --no-pager diff -- platform/environments/development/reference-service/deployment.yaml
```

Stage the manifest:

```bash
git add platform/environments/development/reference-service/deployment.yaml
```

Record the release selection:

```bash
git commit -m "feat: update development reference service image"
```

Publish the commit:

```bash
git push
```

Argo CD detects the changed Git configuration and applies it. Routine workload updates do not require a separate `kubectl apply`.

The release-selection push also triggers CI. Any image produced by that new workflow run remains separate from the image explicitly selected in the Deployment.

### Observe reconciliation

Watch the Deployment:

```bash
kubectl get deployment reference-service --namespace development \
  --context kind-internal-developer-platform --watch
```

Press **Ctrl+C** after the rollout settles, then check the Application:

```bash
kubectl get application reference-service-development \
  --namespace argocd --context kind-internal-developer-platform
```

Expect **Synced** and **Healthy**, then repeat the endpoint checks.

To restore an earlier release, select its published image in Git and push that configuration change.

## Reconciliation policy

| Policy | Current behavior |
| --- | --- |
| Automated sync | Applies detected differences from the tracked Git configuration |
| Self-healing | Corrects live changes that differ from that configuration |
| Automated pruning | Disabled; removing a manifest does not automatically delete its live resource |

Argo CD checks Git periodically. A push does not imply an immediate rollout.

Live edits such as manually scaling the Deployment can be reverted by self-healing. Make persistent workload changes in Git.

Changes to the Application definition itself still require applying that file with kubectl because this Application does not manage its own manifest.

### Verified behavior

| Check | Observed result |
| --- | --- |
| CI container checks | Both HTTP endpoints responded successfully |
| Registry delivery | The published image was pulled and run locally |
| Kubernetes image pull | The workload started from GHCR |
| Service routing | Both endpoints responded through internal Service DNS |
| Git-based scaling | Replica changes from one to two and back to one reconciled |
| Drift correction | Manual scaling to two was restored to the declared one replica |
| Application status | Synced and Healthy |

## Inspect health and logs

Both probes call `/health` on the named `http` port.

| Setting | Readiness | Liveness |
| --- | --- | --- |
| Initial delay | 5 seconds | 10 seconds |
| Check interval | 5 seconds | 10 seconds |
| Request timeout | 2 seconds | 2 seconds |
| Consecutive failure threshold | 3 | 3 |
| Failure action | Remove traffic eligibility | Restart the failing container |

Readiness and liveness run independently. Their current endpoint checks the application's ability to respond; it does not evaluate external dependencies.

Inspect Pod configuration and events:

```bash
kubectl describe pods --namespace development \
  --context kind-internal-developer-platform \
  --selector app=reference-service
```

Check the selected image, probe settings, readiness, restart count, and **Events**.

Read recent application logs:

```bash
kubectl logs deployment/reference-service --namespace development \
  --context kind-internal-developer-platform --tail=15
```

Successful probe requests show `/health`, status **200**, and a `kube-probe/` user agent.

## Optional local container testing

<details>
<summary><strong>Build and run before publishing a change</strong></summary>

Build directly from the application directory:

```bash
docker build --progress=plain -t reference-service:local apps/reference-service
```

The Dockerfile includes the Python runtime and dependencies, so a host Python virtual environment is not required for this build.

Run the image on a separate local port:

```bash
docker run --rm --name reference-service-local \
  --publish 127.0.0.1:18080:8080 reference-service:local
```

In another terminal, check its health:

```bash
curl -i http://127.0.0.1:18080/health
```

Check the root endpoint:

```bash
curl -i http://127.0.0.1:18080/
```

Press **Ctrl+C** in the container terminal when finished.

This tests a local image without changing the GitOps workload. The committed Deployment continues selecting its published GHCR image.

</details>

## Troubleshooting

<details>
<summary><strong>Kubernetes connection refused after a shutdown</strong></summary>

Confirm Docker connectivity:

```bash
docker version
```

Inspect the node container, including stopped containers:

```bash
docker ps -a --filter name=internal-developer-platform-control-plane
```

If it exists with status **Exited**, start it:

```bash
docker start internal-developer-platform-control-plane
```

Allow recovery, then check the node:

```bash
kubectl get nodes --context kind-internal-developer-platform
```

If the container is absent, recreate the cluster and repeat the bootstrap steps.

</details>

<details>
<summary><strong>ImagePullBackOff or ErrImagePull</strong></summary>

Read the Pod's **Events** using the describe command above.

Confirm that the selected image name and tag exist in GHCR and that the node can reach the registry. The current package is public; private packages require suitable image-pull credentials.

Pulling an image with host Docker does not place it in the kind node's separate image store.

</details>

<details>
<summary><strong>Application remains Unknown or reports ComparisonError</strong></summary>

Read the actual comparison error:

```bash
kubectl describe application reference-service-development \
  --namespace argocd --context kind-internal-developer-platform
```

Check the repository URL, tracked branch, and manifest directory. For DNS errors, inspect CoreDNS:

```bash
kubectl get pods --namespace kube-system \
  --context kind-internal-developer-platform \
  --selector k8s-app=kube-dns
```

Test repository-server name resolution from the controller:

```bash
kubectl exec --namespace argocd \
  --context kind-internal-developer-platform \
  argocd-application-controller-0 -- \
  timeout 10 getent ahostsv4 argocd-repo-server.argocd.svc.cluster.local.
```

Compare resolution from the reference-service Pod if that workload is running:

```bash
kubectl exec --namespace development \
  --context kind-internal-developer-platform \
  deployment/reference-service -- timeout 10 python -c \
  'import socket; print(socket.gethostbyname("argocd-repo-server.argocd.svc.cluster.local"))'
```

In the verified recovery incident, resolution timed out from the controller while succeeding from the application Pod. Recreating the controller restored resolution:

```bash
kubectl rollout restart statefulset/argocd-application-controller \
  --namespace argocd --context kind-internal-developer-platform
```

Wait for replacement:

```bash
kubectl rollout status statefulset/argocd-application-controller \
  --namespace argocd --context kind-internal-developer-platform \
  --timeout=120s
```

Repeat the DNS and Application checks. The incident's root cause was not established; a restart is a targeted recovery step, not a general DNS fix.

</details>

<details>
<summary><strong>Application is OutOfSync</strong></summary>

Inspect the Application's **Diff** in the dashboard.

Existing resources initially showed missing Argo CD tracking annotations during adoption. Review the complete diff before treating it as metadata-only.

For the current automated policy, allow reconciliation and inspect any sync failure in the Application details. If automated sync is deliberately disabled, use **Sync → Synchronize** after reviewing the proposed changes.

</details>

<details>
<summary><strong>Local port is already occupied</strong></summary>

Stop an earlier forwarding process if it is no longer needed, or choose another local port:

```bash
kubectl port-forward --context kind-internal-developer-platform \
  --namespace development --address 127.0.0.1 \
  service/reference-service 8081:8080
```

Use `http://127.0.0.1:8081/health` while this tunnel is running.

</details>

<details>
<summary><strong>Rollout times out or a Pod remains unready</strong></summary>

Inspect Pod events and application logs. Events identify scheduling, image-pull, and probe failures; logs show startup and request handling.

A rollout timeout ends the command's wait. Kubernetes continues managing the workload.

</details>

## Remove the local cluster

<details>
<summary><strong>Delete the local environment</strong></summary>

This removes the named cluster, including its workloads, credentials, and cluster data:

```bash
kind delete cluster --name internal-developer-platform
```

Repository files and published GHCR images remain available.

To restore the environment, recreate the cluster and repeat the namespace, Argo CD installation, and Application bootstrap steps. A fresh Argo CD installation generates new initial credentials.

</details>

---

<p align="center">
  <strong>Verified baseline: published images, Git-based deployment, and automatic drift correction.</strong><br>
  <a href="../README.md">Platform overview</a> &nbsp;·&nbsp;
  <a href="architecture.md">Platform architecture</a> &nbsp;·&nbsp;
  <a href="https://github.com/Rano1000/internal-developer-platform/actions">CI runs</a>
</p>
