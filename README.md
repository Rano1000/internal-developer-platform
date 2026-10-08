<p align="center">
  <strong>PLATFORM ENGINEERING &nbsp;·&nbsp; KUBERNETES &nbsp;·&nbsp; GITOPS</strong>
</p>

<h1 align="center">Internal Developer Platform</h1>

<p align="center">
  A consistent path from a code change to a healthy, observable service.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/status-active_development-7357D9?style=flat-square" alt="Status: active development">
  <img src="https://img.shields.io/badge/runtime-Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white" alt="Runtime: Kubernetes">
  <img src="https://img.shields.io/badge/milestone-local_workload_ready-188F89?style=flat-square" alt="Milestone: local workload ready">
</p>

<p align="center">
  <img src="docs/assets/delivery-flow.gif" width="960" alt="Animated target workflow: Git, CI, registry, GitOps, Kubernetes, and metrics"><br>
  <sub>Target delivery workflow · current implementation: a working local Kubernetes service.</sub>
</p>

<p align="center">
  <a href="#current-implementation">Current implementation</a> &nbsp;·&nbsp;
  <a href="#getting-started">Get started</a> &nbsp;·&nbsp;
  <a href="docs/architecture.md">Architecture</a> &nbsp;·&nbsp;
  <a href="#project-roadmap">Roadmap</a>
</p>

---

## Overview

The Internal Developer Platform is being built to give engineering teams a repeatable way to build, deploy, and operate containerized services on Kubernetes. Its target delivery path connects automated checks, versioned images, deployment configuration stored in Git, and service monitoring.

The current implementation runs a containerized reference service in a local kind cluster. Its deployment configuration and operating instructions are versioned in this repository. Image building, image loading, and deployment are currently manual.

The platform is under active development. The sections below record the implemented local baseline and the planned delivery, security, and operations capabilities.

## Current implementation

| Component | Implemented behavior |
| --- | --- |
| Local Kubernetes | A dedicated, single-node kind cluster named `internal-developer-platform`. |
| Development environment | A `development` namespace declared in a Kubernetes manifest. |
| Reference service | Flask and Gunicorn serve application metadata at `/` and health status at `/health`. |
| Container image | A Dockerfile packages the application and runs it as `appuser`, UID `10001`. |
| Deployment | One replica runs `reference-service:0.1.0` with `imagePullPolicy: IfNotPresent`. |
| Internal networking | A ClusterIP Service exposes port `8080` and selects the application Pods by label. |
| Health checks | HTTP readiness and liveness probes check `/health` with separate timing settings. |
| Local access | kubectl port-forwarding provides access through `127.0.0.1:8080`. |
| Documentation | A guide covers setup, deployment, verification, and common recovery steps. |

The local baseline has been verified through HTTP requests to the application, an in-cluster request through the Service's DNS name, and inspection of the running Pod's health check configuration.

## Getting started

Follow the [local development guide](docs/local-development.md) to create or recover the cluster, build and load the image, apply the manifests, and verify the service.

Run its commands from the repository root. The guide explains each step and includes expected results and troubleshooting instructions.

With the local forwarding session active, the service exposes:

| Endpoint | Purpose |
| --- | --- |
| `http://127.0.0.1:8080/` | Returns the service name and application version. |
| `http://127.0.0.1:8080/health` | Returns the application's health response. |

For the system map, component responsibilities, and release approach, see the [platform architecture](docs/architecture.md).

## Target workflow

1. **Commit:** A developer pushes an application change to Git.
2. **Verify and package:** CI runs checks, builds a container image, and scans it.
3. **Select a release:** A reviewed change in Git records the image version to deploy.
4. **Deploy:** Argo CD reconciles the declared configuration with Kubernetes.
5. **Operate:** Health checks, metrics, and dashboards show how the service behaves.

CI, image publishing, Argo CD, metrics collection, and dashboards are planned additions to the current local baseline.

## Planned platform capabilities

| Area | Target capability | Why it matters |
| --- | --- | --- |
| Delivery | Automated checks and published, versioned container images | Each release can be traced to a source change. |
| Deployment | GitOps with Argo CD | Deployment changes are reviewable and repeatable. |
| Runtime | Additional environments, external routing, scaling, and resource policies | Services run within consistent operating boundaries. |
| Security | RBAC, network policies, and managed secrets | Access is limited to what workloads require. |
| Operations | Metrics, dashboards, and documented recovery procedures | Teams can assess health and investigate failures. |

## Project roadmap

| Milestone | Outcome | Status |
| --- | --- | --- |
| Foundation | Repository structure, platform architecture, and Git workflow | Complete |
| Workload | Local Kubernetes cluster, reference service, internal routing, and health probes | Complete — local baseline |
| Delivery | CI checks, image publishing, and GitOps deployment | Planned |
| Guardrails | Environment boundaries and security controls | Planned |
| Operations | Metrics, dashboards, and recovery procedures | Planned |

## Repository layout

```text
.
├── .gitignore                         # Excludes local environments and Python caches
├── README.md                          # Project overview and implementation progress
├── apps/
│   └── reference-service/
│       ├── .dockerignore              # Excludes local files from the image build
│       ├── Dockerfile                 # Packages and starts the application
│       ├── app.py                     # Application and health endpoints
│       └── requirements.txt           # Application dependency versions
├── docs/
│   ├── architecture.md                # Target system design and delivery flow
│   ├── local-development.md           # Build, deploy, verify, and troubleshoot
│   └── assets/
│       ├── delivery-flow.gif          # Target workflow illustration
│       └── local-cluster.gif          # Local environment illustration
└── platform/
    └── environments/
        └── development/
            ├── namespace.yaml         # Declares the development namespace
            └── reference-service/
                ├── deployment.yaml    # Image, replica count, and health probes
                └── service.yaml       # Internal application routing
```

Application code and image packaging live under `apps/`. Kubernetes configuration for each environment lives under `platform/environments/`. Design and operating documentation live under `docs/`.

---

<p align="center">
  <strong>Current milestone: a documented, running Kubernetes workload.</strong><br>
  <a href="docs/local-development.md">Run the local platform</a> &nbsp;·&nbsp;
  <a href="docs/architecture.md">Explore the target architecture</a>
</p>
