<p align="center">
  <strong>INTERNAL DEVELOPER PLATFORM &nbsp;·&nbsp; DELIVERY</strong>
</p>

<h1 align="center">Image Delivery</h1>

<p align="center">
  Build once. Verify before publishing. Select releases through Git.
</p>

<p align="center">
  <a href="../README.md">Overview</a> &nbsp;·&nbsp;
  <a href="architecture.md">Architecture</a> &nbsp;·&nbsp;
  <a href="local-development.md">Local Development</a>
</p>

---

## Delivery model

The reference service follows two connected stages:

1. **Publish:** GitHub Actions builds the image, checks the application endpoints, scans dependencies, and publishes the passing image to GitHub Container Registry.
2. **Deploy:** A Git change selects the published image in the development Deployment. Argo CD detects that change and reconciles Kubernetes with the repository.

Image selection is currently a manual Git change. Publishing an image does not automatically update the Deployment.

<p align="center">
  <img src="assets/delivery-flow.gif" width="960" alt="Target platform delivery flow from Git through CI, registry, Argo CD, Kubernetes, and metrics">
</p>

<p align="center">
  <sub>Target platform workflow. This guide covers image verification, publication, and deployment.</sub>
</p>

## CI checks

The workflow is defined in:

`.github/workflows/reference-service-ci.yaml`

| Stage | What it verifies |
| --- | --- |
| Checkout | Retrieves the source revision for the workflow run. |
| Build | Builds the reference-service image from its Dockerfile. |
| Start | Starts a container from the built image. |
| Endpoint checks | Requires successful HTTP responses from `/health` and `/`. |
| Vulnerability scan | Checks operating-system and Python dependencies with Trivy. |
| Registry login | Authenticates to GHCR using the workflow's `GITHUB_TOKEN`. |
| Publish | Tags and uploads the same image that passed the checks. |
| Application logs | Displays container logs whenever the container-start step succeeded, including after later failures. |

The workflow runs for pushes to `main`, pull requests targeting `main`, and manual dispatches.

Registry login and publication run only for non-pull-request events on `main`. A failed build, endpoint check, or vulnerability scan prevents publication.

## Security gate

The image scan uses Trivy `v0.75.0` with these settings:

| Setting | Policy |
| --- | --- |
| Scanner | Vulnerabilities |
| Package coverage | Operating-system and supported application dependencies |
| Blocking severities | HIGH and CRITICAL |
| Unfixed vulnerabilities | Included |
| Failure behavior | Exit code `1` when blocking findings are detected |

A passing scan means that Trivy reported no HIGH or CRITICAL findings in the scanned image using the database available at that time.

It does not establish that the image is free of vulnerabilities at other severity levels. Findings can change as vulnerability databases are updated.

### Runtime image

The reference service currently uses:

- Official Python base: `python:3.14.8-alpine3.24`
- Application dependencies installed during the build
- `pip` removed from the final runtime filesystem after installation
- Application user and group ID: `10001`

The Alpine image was checked locally with both application endpoints and a Trivy scan. The CI pipeline independently rebuilt, tested, scanned, and published the release.

## Release identity

Published images use this naming convention:

```text
ghcr.io/rano1000/reference-service:<full-source-commit-sha>
```

The tag identifies the source commit used by CI.

Two commits participate in a release:

| Commit | Purpose |
| --- | --- |
| Image-build commit | Supplies the source and Dockerfile used to build the published image. |
| Deployment-selection commit | Updates the Deployment to reference that image tag. |

Argo CD reports the Git revision containing the deployment configuration. That revision can differ from the commit SHA used as the image tag.

## Select an image for development

### 1. Confirm the publishing run

Open the successful Reference Service CI run in GitHub Actions.

Confirm that the endpoint checks, vulnerability scan, and image-publication steps passed. Copy the full source commit SHA associated with that run.

### 2. Update the Deployment

Edit the existing development Deployment:

```bash
nano platform/environments/development/reference-service/deployment.yaml
```

Set its container image to the GHCR reference tagged with the successful build's full commit SHA.

Review the change:

```bash
git --no-pager diff -- platform/environments/development/reference-service/deployment.yaml
```

### 3. Record and publish the release selection

Stage the Deployment and check the staged change for whitespace errors:

```bash
git add platform/environments/development/reference-service/deployment.yaml
git diff --cached --check
```

Commit and push the image selection:

```bash
git commit -m "feat: select reference service image for development"
git push
```

Argo CD's automated synchronization applies the updated configuration to the cluster.

## Verify deployment

Check the Git revision, synchronization status, and application health:

```bash
kubectl get application reference-service-development \
  --namespace argocd \
  --context kind-internal-developer-platform \
  -o custom-columns='NAME:.metadata.name,REVISION:.status.sync.revision,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Expect the deployment-selection revision with `Synced` and `Healthy`.

Inspect the images reported by the running containers:

```bash
kubectl get pods \
  --namespace development \
  --context kind-internal-developer-platform \
  --selector app=reference-service \
  -o custom-columns='NAME:.metadata.name,IMAGE:.status.containerStatuses[*].image,READY:.status.containerStatuses[*].ready,STATUS:.status.phase'
```

Confirm that the selected image tag is running and its container is ready.

Check both endpoints through the Kubernetes Service:

```bash
kubectl exec \
  --context kind-internal-developer-platform \
  --namespace development \
  deployment/reference-service \
  -- python -c '
from urllib.request import urlopen

for path in ("/health", "/"):
    with urlopen("http://reference-service:8080" + path, timeout=5) as response:
        print(path, "HTTP", response.status)
        print(response.read().decode())
'
```

Expect HTTP `200` from both endpoints.

<details>
<summary><strong>Argo CD still shows an earlier Git revision</strong></summary>

Request a fresh comparison with a hard refresh. This invalidates Argo CD's cached manifests and target-cluster state before it refreshes the Application:

```bash
kubectl annotate application reference-service-development \
  --namespace argocd \
  --context kind-internal-developer-platform \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```

Recheck the Application's revision and status.

If the refresh fails, inspect the Application's conditions before taking further action:

```bash
kubectl describe application reference-service-development \
  --namespace argocd \
  --context kind-internal-developer-platform
```

A DNS timeout or repository-access error requires investigation; refreshing alone does not resolve the underlying problem.

</details>

---

A release is verified when the selected Git revision is synchronized,
the expected image is running, and the service endpoints respond successfully.
