<p align="center">
  <strong>PLATFORM ENGINEERING &nbsp;·&nbsp; KUBERNETES &nbsp;·&nbsp; GITOPS</strong>
</p>

<h1 align="center">Internal Developer Platform</h1>

<p align="center">
  From a Git change to a healthy, reconciled Kubernetes workload.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active_development-7357D9?style=flat-square" alt="Status: active development">
  <img src="https://img.shields.io/badge/runtime-Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="Runtime: Kubernetes">
  <img src="https://img.shields.io/badge/delivery-Argo_CD-188F89?style=flat-square" alt="Delivery: Argo CD">
  <img src="https://img.shields.io/badge/milestone-GitOps_baseline_verified-188F89?style=flat-square" alt="Milestone: GitOps baseline verified">
</p>

<p align="center">
  <a href="https://github.com/Rano1000/internal-developer-platform/actions/workflows/reference-service-ci.yaml">
    <img src="https://github.com/Rano1000/internal-developer-platform/actions/workflows/reference-service-ci.yaml/badge.svg?branch=main" alt="Reference Service CI status">
  </a>
</p>

<p align="center">
  <img src="docs/assets/delivery-flow.gif" width="960" alt="Animated target delivery path: Git, CI, registry, Argo CD, Kubernetes, and metrics"><br>
  <sub>Target delivery architecture · CI, registry publishing, and GitOps are implemented; metrics and dashboards are planned.</sub>
</p>

<p align="center">
  <a href="#current-implementation">Implemented</a> &nbsp;·&nbsp;
  <a href="#delivery-workflow">Delivery workflow</a> &nbsp;·&nbsp;
  <a href="#getting-started">Get started</a> &nbsp;·&nbsp;
  <a href="docs/architecture.md">Architecture</a> &nbsp;·&nbsp;
  <a href="#project-roadmap">Roadmap</a>
</p>

---

## Overview

The Internal Developer Platform provides a growing foundation for building, deploying, and operating containerized services on Kubernetes. Application code, delivery automation, and deployment configuration are versioned together, making the delivery path visible and reviewable.

The current implementation connects **GitHub Actions**, **GitHub Container Registry**, and **Argo CD** to a dedicated local Kubernetes environment. CI builds and checks the reference-service image, publishes it to GHCR, and Argo CD automatically applies workload configuration declared in Git.

The platform is under active development. Its verified baseline runs on a single-node kind cluster; environment guardrails, broader security controls, and observability remain on the roadmap.

## Current implementation

| Component | Implemented behavior |
| --- | --- |
| Local Kubernetes | A dedicated, single-node kind cluster named `internal-developer-platform`. |
| Development environment | A `development` namespace declared in Git. |
| Reference service | Flask and Gunicorn expose service metadata at `/` and health status at `/health`. |
| Container runtime | The application image runs as `appuser`, UID `10001`. |
| Continuous integration | GitHub Actions builds the image, starts a container, checks both HTTP endpoints, and displays application logs. |
| Image registry | Successful workflow runs on `main` publish the tested image to `ghcr.io/rano1000/reference-service`, tagged with the Git commit SHA. |
| Workload deployment | One replica runs a version explicitly selected from GHCR in the Deployment manifest. |
| Internal networking | A ClusterIP Service exposes port `8080` and selects application pods by label. |
| Health checks | HTTP readiness and liveness probes check `/health` with separate timing settings. |
| Argo CD installation | Kustomize installs Argo CD from the official `v3.5.4` manifests into the `argocd` namespace. |
| GitOps application | `reference-service-development` tracks the workload manifests on the `main` branch. |
| Automatic sync | Argo CD applies changes to the tracked workload manifests without a manual sync request. |
| Self-healing | Argo CD restores managed configuration when the live cluster differs from Git. |

## Delivery workflow

1. **Commit:** Application changes enter the repository.
2. **Build and check:** GitHub Actions builds a container image, starts it, and checks `/health` and `/`.
3. **Publish:** Successful runs on `main` publish the tested image to GHCR using the commit SHA as its tag.
4. **Select a release:** Update the image reference in the development Deployment manifest, then commit and push that configuration.
5. **Reconcile:** Argo CD reads the manifests from Git and applies the declared configuration to Kubernetes.
6. **Verify:** Kubernetes health probes and Argo CD's sync and health statuses show the resulting workload state.

> **Release selection is explicit.** Publishing a new image does not automatically change the deployed version. The image reference committed in the Deployment manifest determines the selected release.

Pull requests targeting `main` run the build and endpoint checks. Registry publishing is restricted to successful runs on `main`; the workflow also supports manual execution.

See the [CI workflow](.github/workflows/reference-service-ci.yaml) for the implemented steps.

## GitOps behavior

| Setting | Current behavior |
| --- | --- |
| Git source | `Rano1000/internal-developer-platform`, branch `main`. |
| Manifest path | `platform/environments/development/reference-service`. |
| Destination | The cluster where Argo CD runs, namespace `development`. |
| Automatic sync | Enabled. Changes in the tracked manifests are applied automatically. |
| Self-healing | Enabled. Live configuration drift is corrected against Git. |
| Automatic pruning | Disabled. Removing a manifest from Git does not automatically delete its live resource. |

The Application definition lives in the `argocd` namespace. The Deployment and Service it manages live in `development`.

Argo CD's installation and its Application definition are bootstrapped separately. The current Application manages the reference-service workload manifests; it does not manage its own definition or the Argo CD installation.

## Verified behavior

The implemented delivery baseline has been verified through:

- Successful container builds and HTTP endpoint checks in GitHub Actions.
- Publishing an image to GHCR, pulling it locally, and running it successfully.
- Kubernetes pulling the selected GHCR image and serving both application endpoints.
- Requests through the Kubernetes Service's DNS name.
- Git-driven scaling from one replica to two and back to one using automatic sync.
- Restoring one replica after the live Deployment was manually scaled to two.
- Argo CD reporting **Synced** and **Healthy** after reconciliation.

## Getting started

Use Docker, kind, kubectl, and Git. Start with the [local development guide](docs/local-development.md) for prerequisites, cluster creation, and local recovery.

Clone the repository if needed, then run the remaining commands from its root:

```bash
git clone https://github.com/Rano1000/internal-developer-platform.git
cd internal-developer-platform
```

### Bootstrap GitOps

With the `internal-developer-platform` cluster running, create the workload namespace and install Argo CD:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/environments/development/namespace.yaml

kubectl apply --context kind-internal-developer-platform \
  --server-side --force-conflicts \
  -k platform/components/argocd
```

Check Argo CD's pods. Wait until they report ready before proceeding:

```bash
kubectl get pods --namespace argocd \
  --context kind-internal-developer-platform
```

Register the Application so Argo CD can deploy the reference service from Git:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/applications/reference-service-development.yaml
```

Argo CD will fetch the configured repository and reconcile its workload manifests. Check the result:

```bash
kubectl get application reference-service-development \
  --namespace argocd \
  --context kind-internal-developer-platform
```

Expect **Synced** and **Healthy** once reconciliation completes.

### Access the reference service

Forward the Service to a local port:

```bash
kubectl port-forward --context kind-internal-developer-platform \
  --namespace development --address 127.0.0.1 \
  service/reference-service 8080:8080
```

Keep that terminal running. From another terminal, request the health endpoint:

```bash
curl --fail http://127.0.0.1:8080/health
```

Expected response:

```json
{"status":"healthy"}
```

| Endpoint | Purpose |
| --- | --- |
| `http://127.0.0.1:8080/` | Returns the service name and application version. |
| `http://127.0.0.1:8080/health` | Returns the application's health response. |

For component responsibilities and the target architecture, see the [platform architecture](docs/architecture.md).

## Project roadmap

| Milestone | Outcome | Status |
| --- | --- | --- |
| Foundation | Repository structure, platform architecture, and Git workflow | Complete |
| Workload | Local Kubernetes cluster, reference service, internal routing, and health probes | Complete — local baseline |
| Delivery | CI checks, image publishing, automatic GitOps deployment, and drift correction | In progress — delivery baseline verified |
| Guardrails | Resource policies, scoped access, environment boundaries, and security controls | Planned |
| Operations | Metrics, dashboards, and expanded recovery procedures | Planned |

Further work includes image vulnerability scanning, additional environments, external routing, resource requests and limits, access controls, network policy enforcement, and secrets management.

## Repository layout

```text
.
├── .github/
│   └── workflows/
│       └── reference-service-ci.yaml       # Build, check, and publish the image
├── .gitignore                             # Local environments and Python caches
├── README.md                              # Overview and implementation progress
├── apps/
│   └── reference-service/
│       ├── .dockerignore                  # Files excluded from image builds
│       ├── Dockerfile                     # Application image and startup command
│       ├── app.py                         # Application and health endpoints
│       └── requirements.txt               # Application dependency versions
├── docs/
│   ├── architecture.md                    # Target design and delivery responsibilities
│   ├── local-development.md               # Local setup, verification, and recovery
│   └── assets/
│       ├── delivery-flow.gif              # Target delivery illustration
│       └── local-cluster.gif              # Local environment illustration
└── platform/
    ├── applications/
    │   └── reference-service-development.yaml  # GitOps source, destination, and policy
    ├── components/
    │   └── argocd/
    │       ├── kustomization.yaml         # Pinned Argo CD installation
    │       └── namespace.yaml             # Argo CD namespace
    └── environments/
        └── development/
            ├── namespace.yaml             # Development namespace
            └── reference-service/
                ├── deployment.yaml        # Selected image, replicas, and probes
                └── service.yaml           # Internal application routing
```

Application source and image packaging live under `apps/`. Shared platform installations live under `platform/components/`. Argo CD assignments live under `platform/applications/`, while workload manifests live under `platform/environments/`.

---

<p align="center">
  <strong>Current milestone: automatic GitOps deployment and drift correction verified.</strong><br>
  <a href="#getting-started">Run the local platform</a> &nbsp;·&nbsp;
  <a href="docs/architecture.md">Explore the architecture</a> &nbsp;·&nbsp;
  <a href="https://github.com/Rano1000/internal-developer-platform/actions">View delivery runs</a>
</p>
