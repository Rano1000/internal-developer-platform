<p align="center">
  <strong>PLATFORM ENGINEERING &nbsp;·&nbsp; KUBERNETES &nbsp;·&nbsp; GITOPS</strong>
</p>

<h1 align="center">Internal Developer Platform</h1>

<p align="center">
  From a Git change to a scanned image and a healthy Kubernetes workload.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active_development-7357D9?style=flat-square" alt="Status: active development">
  <img src="https://img.shields.io/badge/runtime-Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="Runtime: Kubernetes">
  <img src="https://img.shields.io/badge/delivery-Argo_CD-188F89?style=flat-square" alt="Delivery: Argo CD">
  <img src="https://img.shields.io/badge/milestone-scanned_release_verified-188F89?style=flat-square" alt="Milestone: scanned release verified">
</p>

<p align="center">
  <a href="https://github.com/Rano1000/internal-developer-platform/actions/workflows/reference-service-ci.yaml">
    <img src="https://github.com/Rano1000/internal-developer-platform/actions/workflows/reference-service-ci.yaml/badge.svg?branch=main" alt="Reference Service CI status">
  </a>
</p>

<p align="center">
  <img src="docs/assets/delivery-flow.gif" width="960" alt="Animated target delivery path: Git, CI, registry, Argo CD, Kubernetes, and metrics"><br>
  <sub>Target delivery architecture · CI, image scanning, registry publishing, and GitOps are implemented; metrics and dashboards are planned.</sub>
</p>

<p align="center">
  <a href="#current-implementation">Implemented</a> &nbsp;·&nbsp;
  <a href="docs/image-delivery.md">Image delivery</a> &nbsp;·&nbsp;
  <a href="#getting-started">Get started</a> &nbsp;·&nbsp;
  <a href="docs/architecture.md">Architecture</a> &nbsp;·&nbsp;
  <a href="#project-roadmap">Roadmap</a>
</p>

---

## Overview

The Internal Developer Platform provides a growing foundation for building, deploying, and operating containerized services on Kubernetes. Application code, delivery automation, and deployment configuration are versioned together, making the delivery path visible and reviewable.

The current implementation connects **GitHub Actions**, **GitHub Container Registry**, and **Argo CD** to a dedicated local Kubernetes environment. CI builds the reference-service image, checks its HTTP endpoints, scans its dependencies, and publishes passing images to GHCR. A Git change selects the image to deploy, and Argo CD reconciles the declared configuration with Kubernetes.

The platform is under active development. Its verified baseline includes resource policies, container security settings, and scoped Argo CD projects. Additional environments, broader access controls, network isolation, and observability remain on the roadmap.

## Current implementation

| Component | Implemented behavior |
| --- | --- |
| Local Kubernetes | A dedicated, single-node kind cluster named `internal-developer-platform`. |
| Development environment | A namespace, ResourceQuota, and LimitRange declared in Git. |
| Reference service | Flask and Gunicorn expose service metadata at `/` and health status at `/health`. |
| Container image | An Alpine-based Python image installs application dependencies and removes pip from the runtime filesystem. |
| Container identity | The application runs with user and group ID `10001`. |
| Continuous integration | GitHub Actions builds the image, starts a container, checks both HTTP endpoints, scans vulnerabilities, and displays application logs. |
| Security gate | Trivy blocks publication when it detects HIGH or CRITICAL vulnerabilities, including findings without available fixes. |
| Image registry | Successful non-pull-request runs on `main` publish the checked image to GHCR, tagged with the source commit SHA. |
| Workload deployment | One replica runs an image explicitly selected in the Deployment manifest. |
| Internal networking | A ClusterIP Service exposes port `8080` and selects application Pods by label. |
| Health checks | HTTP readiness and liveness probes check `/health` with separate timing settings. |
| Resource budget | The container requests `100m` CPU and `64Mi` memory, with limits of `500m` CPU and `128Mi` memory. |
| Runtime security | Kubernetes enforces non-root execution, disables privilege escalation, drops Linux capabilities, and applies the runtime's default seccomp profile. |
| API credentials | Automatic service-account token mounting is disabled for the reference service. |
| Argo CD installation | Kustomize installs Argo CD from the official `v3.5.4` manifests into the `argocd` namespace. |
| GitOps applications | Separate Applications manage the reference-service workload and development environment policies. |
| Deployment scope | Separate AppProjects constrain the permitted Git repository, destination, and resource types for each Application. |
| Automatic sync | Argo CD applies changes to tracked manifests automatically. |
| Self-healing | Argo CD restores managed configuration when the live cluster differs from Git. |

## Delivery workflow

1. **Commit:** Application changes enter the repository.
2. **Build and check:** GitHub Actions builds a container image, starts it, and checks `/health` and `/`.
3. **Scan:** Trivy checks the image for HIGH and CRITICAL vulnerabilities.
4. **Publish:** Passing runs on `main` publish the checked image to GHCR using the source commit SHA as its tag.
5. **Select a release:** Update the image reference in the development Deployment, then commit and push that configuration.
6. **Reconcile:** Argo CD reads the manifests from Git and applies the declared configuration to Kubernetes.
7. **Verify:** Confirm the Git revision, running image, readiness, and responses through the Kubernetes Service.

> **Release selection is explicit.** Publishing a new image does not automatically change the deployed version. The image reference committed in the Deployment determines the selected release.

Pull requests targeting `main` run the build, endpoint checks, and vulnerability scan. Registry login and publishing run only for non-pull-request events on `main`. The workflow also supports manual execution.

See the [image delivery guide](docs/image-delivery.md) for release selection and verification, and the [CI workflow](.github/workflows/reference-service-ci.yaml) for the implemented checks.

## Development guardrails

| Control | Current policy |
| --- | --- |
| Container requests | `100m` CPU and `64Mi` memory for the reference service. |
| Container limits | `500m` CPU and `128Mi` memory for the reference service. |
| Namespace request budget | Aggregate requests up to `1` CPU and `512Mi` memory. |
| Namespace limit budget | Aggregate limits up to `2` CPUs and `1Gi` memory. |
| Pod count | Up to `10` Pods, subject to the resource budgets. |
| Container defaults | LimitRange supplies requests of `100m` / `64Mi` and limits of `500m` / `128Mi` when omitted. |
| Workload AppProject | Permits Deployments and Services in `development` from the configured repository. |
| Environment AppProject | Permits the `development` Namespace and its ResourceQuota and LimitRange. |

ResourceQuota checks declared resource totals rather than live CPU or memory consumption. A workload must fit every applicable budget.

The AppProjects constrain deployment through Argo CD. Kubernetes RBAC and enforced network isolation are separate controls on the roadmap.

## GitOps behavior

| Setting | Current behavior |
| --- | --- |
| Git source | `Rano1000/internal-developer-platform`, branch `main`. |
| Workload path | `platform/environments/development/reference-service`. |
| Environment path | `platform/environments/development`, with directory recursion disabled. |
| Destination | The cluster where Argo CD runs, namespace `development`. |
| Automatic sync | Enabled for both Applications. |
| Self-healing | Enabled for both Applications. |
| Automatic pruning | Disabled. Removing a manifest from Git does not automatically delete its live resource. |

The workload Application manages the Deployment and Service. The environment Application manages the Namespace, ResourceQuota, and LimitRange without including the nested workload directory.

Application and AppProject definitions live in `argocd`. The application workload and namespace policies apply to `development`.

Argo CD, its AppProjects, and its Application definitions are bootstrapped separately. The current Applications manage their configured manifest paths; they do not manage their own definitions or the Argo CD installation.

## Verified behavior

The implemented baseline has been checked through:

- Successful image builds and HTTP endpoint checks in GitHub Actions.
- A passing HIGH/CRITICAL vulnerability scan before image publication.
- Pulling a published GHCR image into Kubernetes.
- Confirming the selected image is running and ready.
- Successful requests to both endpoints through the Kubernetes Service's DNS name.
- Git-driven scaling from one replica to two and back to one.
- Restoring one replica after the live Deployment was manually scaled to two.
- ResourceQuota rejecting an over-budget server-side dry-run request.
- LimitRange injecting resource defaults during a server-side dry run.
- Runtime checks confirming UID/GID `10001`, dropped capabilities, no privilege escalation, seccomp filtering, and no mounted API token.
- Both Applications reporting **Synced** and **Healthy** under their assigned AppProjects.

A passing scan reflects the selected severities and vulnerability database available at scan time. Findings can change as the database is updated.

## Getting started

Use Docker, kind, kubectl, and Git. Start with the [local development guide](docs/local-development.md) for prerequisites, cluster creation, and local recovery.

Clone the repository if needed, then run the remaining commands from its root:

```bash
git clone https://github.com/Rano1000/internal-developer-platform.git
cd internal-developer-platform
```

### Bootstrap the development environment

With the `internal-developer-platform` cluster running, create the development namespace and its resource policies:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/environments/development/namespace.yaml

kubectl apply --context kind-internal-developer-platform \
  -f platform/environments/development/resource-quota.yaml

kubectl apply --context kind-internal-developer-platform \
  -f platform/environments/development/limit-range.yaml
```

Install Argo CD using the pinned Kustomize configuration:

```bash
kubectl apply --context kind-internal-developer-platform \
  --server-side \
  -k platform/components/argocd
```

Check Argo CD's Pods. Proceed once all its containers report ready:

```bash
kubectl get pods --namespace argocd \
  --context kind-internal-developer-platform
```

Create the AppProjects before registering the Applications that use them:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/projects/development-environment.yaml

kubectl apply --context kind-internal-developer-platform \
  -f platform/projects/development-workloads.yaml
```

Register the environment Application so Argo CD manages the namespace and resource policies:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/applications/development-environment.yaml
```

Register the workload Application so Argo CD deploys the reference service from Git:

```bash
kubectl apply --context kind-internal-developer-platform \
  -f platform/applications/reference-service-development.yaml
```

Check both Applications:

```bash
kubectl get applications --namespace argocd \
  --context kind-internal-developer-platform
```

Expect **Synced** and **Healthy** once reconciliation completes. If an Application reports an error, inspect its conditions before continuing.

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

## Documentation

| Guide | Coverage |
| --- | --- |
| [Architecture](docs/architecture.md) | Target design, component responsibilities, and delivery boundaries. |
| [Local development](docs/local-development.md) | Local setup, verification, access, and recovery. |
| [Image delivery](docs/image-delivery.md) | CI checks, the vulnerability gate, release identity, image selection, and deployment verification. |

## Project roadmap

| Milestone | Outcome | Status |
| --- | --- | --- |
| Foundation | Repository structure, platform architecture, and Git workflow | Complete |
| Workload | Local Kubernetes cluster, reference service, internal routing, and health probes | Complete — local baseline |
| Delivery | CI checks, vulnerability scanning, image publishing, GitOps deployment, and drift correction | In progress — scanned release verified |
| Guardrails | Resource policies, scoped deployment permissions, environment boundaries, and security controls | In progress — resource and runtime controls implemented |
| Operations | Metrics, dashboards, and expanded recovery procedures | Planned |

Further work includes additional environments, external routing and TLS, autoscaling, Kubernetes access controls, network policy enforcement, secrets management, and observability.

## Repository layout

```text
.
├── .github/
│   └── workflows/
│       └── reference-service-ci.yaml       # Build, test, scan, and publish
├── .gitignore                             # Local environments and Python caches
├── README.md                              # Overview and implementation progress
├── apps/
│   └── reference-service/
│       ├── .dockerignore                  # Files excluded from image builds
│       ├── Dockerfile                     # Runtime image and startup command
│       ├── app.py                         # Application and health endpoints
│       └── requirements.txt               # Application dependency versions
├── docs/
│   ├── architecture.md                    # Target design and responsibilities
│   ├── image-delivery.md                  # Image checks and release selection
│   ├── local-development.md               # Local setup and recovery
│   └── assets/
│       ├── delivery-flow.gif              # Target delivery illustration
│       └── local-cluster.gif              # Local environment illustration
└── platform/
    ├── applications/
    │   ├── development-environment.yaml   # Namespace and policy reconciliation
    │   └── reference-service-development.yaml
    ├── components/
    │   └── argocd/
    │       ├── kustomization.yaml         # Pinned Argo CD installation
    │       └── namespace.yaml             # Argo CD namespace
    ├── environments/
    │   └── development/
    │       ├── limit-range.yaml           # Default container resource settings
    │       ├── namespace.yaml             # Development namespace
    │       ├── resource-quota.yaml        # Aggregate namespace resource budget
    │       └── reference-service/
    │           ├── deployment.yaml        # Image, probes, resources, and security
    │           └── service.yaml           # Internal application routing
    └── projects/
        ├── development-environment.yaml   # Environment deployment permissions
        └── development-workloads.yaml     # Workload deployment permissions
```

Application source and image packaging live under `apps/`. Shared platform installations live under `platform/components/`. Argo CD assignments live under `platform/applications/`, their deployment permissions under `platform/projects/`, and environment manifests under `platform/environments/`.

---

<p align="center">
  <strong>Current milestone: scanned image deployed and verified through GitOps.</strong><br>
  <a href="#getting-started">Run the local platform</a> &nbsp;·&nbsp;
  <a href="docs/image-delivery.md">Follow the release process</a> &nbsp;·&nbsp;
  <a href="https://github.com/Rano1000/internal-developer-platform/actions">View delivery runs</a>
</p>
