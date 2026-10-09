# Development Security

The development environment combines resource budgets, container security settings, network restrictions, and scoped Kubernetes access. Argo CD reconciles the versioned configuration from this repository.

This guide describes the controls implemented and verified in the local kind cluster. It does not claim production readiness.

## Configuration ownership

| Configuration | Location | Management |
| --- | --- | --- |
| Container resources and security settings | `platform/environments/development/reference-service/deployment.yaml` | Reference-service Argo CD Application |
| Application network restrictions | `platform/environments/development/reference-service/network-policy.yaml` | Reference-service Argo CD Application |
| Namespace resource budget | `platform/environments/development/resource-quota.yaml` | Development-environment Argo CD Application |
| Container resource defaults | `platform/environments/development/limit-range.yaml` | Development-environment Argo CD Application |
| Observer identity and permissions | `platform/environments/development/observer-*.yaml` | Development-environment Argo CD Application |
| Argo CD deployment boundaries | `platform/projects/` | Explicit bootstrap apply |

The development-environment Application reads the top-level environment manifests without recursing into the reference-service directory. Each Application therefore manages a separate set of resources.

## Resource budgets

The reference-service container declares:

| Resource | Request | Limit |
| --- | --- | --- |
| CPU | `100m` | `500m` |
| Memory | `64Mi` | `128Mi` |

Requests influence scheduling. CPU limits constrain CPU consumption through throttling; exceeding a memory limit can cause the container to be terminated.

The namespace ResourceQuota applies these aggregate budgets:

| Resource | Namespace budget |
| --- | --- |
| CPU requests | `1` |
| Memory requests | `512Mi` |
| CPU limits | `2` |
| Memory limits | `1Gi` |
| Pods | `10` |

Quota accounting measures declared resources, not current CPU or memory consumption. A namespace can exhaust its CPU-limit budget even when its containers are mostly idle.

The LimitRange supplies defaults for containers that omit resource declarations:

- Requests: `100m` CPU and `64Mi` memory.
- Limits: `500m` CPU and `128Mi` memory.

These defaults apply during admission of new Pods. This LimitRange does not define minimum or maximum values.

Verification confirmed that Kubernetes rejected a Pod whose declared resources exceeded the namespace quota. A server-side dry run also confirmed that omitted requests and limits received the configured defaults.

Inspect the current policies:

```bash
kubectl describe resourcequota development-budget \
  --namespace development \
  --context kind-internal-developer-platform

kubectl describe limitrange development-defaults \
  --namespace development \
  --context kind-internal-developer-platform
```

## Container security

The reference-service Deployment specifies:

- A non-root user and group, both numbered `10001`.
- The runtime's default seccomp profile.
- Privilege escalation disabled.
- All Linux capabilities dropped.
- Automatic service-account token mounting disabled.

The application does not require Kubernetes API access.

Runtime inspection verified UID and GID `10001`, empty effective and bounding capability sets, enabled `NoNewPrivs`, active seccomp filtering, and an absent service-account token.

Both application endpoints continued to return HTTP 200 after the security settings were applied.

The container filesystem remains writable. A read-only root filesystem has not been implemented.

## Network restrictions

The `reference-service-traffic` NetworkPolicy selects Pods labelled:

```yaml
app: reference-service
```

It permits:

- Incoming TCP traffic on port `8080` from Pods in the same namespace carrying `access: reference-service`.
- Outgoing UDP and TCP traffic on port `53` to CoreDNS Pods in `kube-system`.

Other incoming and outgoing connections are restricted for the selected Pods according to Kubernetes NetworkPolicy semantics. Reply traffic for permitted connections is allowed automatically.

The policy applies to the reference-service Pods, rather than every Pod in the development namespace. NetworkPolicies are additive: another policy selecting the same Pods can permit additional traffic.

The access label is a traffic-selection convention. It is not an authentication mechanism; identities allowed to create or relabel Pods could create a matching caller.

### Verified behavior

| Test | Observed result |
| --- | --- |
| Same-namespace client with the access label calls `/health` | HTTP 200 |
| Same-namespace client without the access label calls `/health` | Connection timeout |
| Reference service resolves its Service name through DNS | Successful resolution |
| Unrestricted test client connects to a temporary HTTP server | HTTP 200 |
| Reference service connects to that same HTTP server | Connection timeout |

The outgoing restriction was tested against a known working server. This avoids treating a closed port or an unavailable destination as evidence of enforcement.

The temporary development test Pods were removed after verification.

A labelled caller in another namespace was not separately tested. Successful DNS resolution does not imply that every DNS protocol path was tested.

## Networking recovery observation

During initial testing, a deny-ingress policy existed but traffic still reached the selected test Pod.

Investigation found:

- Repeated Kubernetes API TLS handshake timeouts in kindnet logs.
- The selected test Pod's IP missing from kindnet's policy-processing set.

Restarting the kindnet DaemonSet restored the observed enforcement behavior. The same request then timed out while the deny policy existed and succeeded after that policy was removed.

This was a recovery action. The underlying cause of the controller connectivity failures has not been established, and the restart does not prove a permanent fix.

If enforcement becomes unreliable, inspect the controller and API before changing application policies:

```bash
kubectl logs daemonset/kindnet \
  --namespace kube-system \
  --context kind-internal-developer-platform \
  --since=5m \
  --tail=100

kubectl get \
  --context kind-internal-developer-platform \
  --request-timeout=10s \
  --raw='/readyz?verbose'
```

A Ready node, healthy API response, or successfully created NetworkPolicy does not by itself prove network-policy enforcement. Repeat both allowed and denied traffic tests after recovery.

## Development observer access

The `development-observer` ServiceAccount receives a namespace-scoped Role through a RoleBinding.

| Resources | Granted actions |
| --- | --- |
| Pods, Services, Events | `get`, `list`, `watch` |
| Pod logs | `get` |
| Deployments, ReplicaSets | `get`, `list`, `watch` |

The ServiceAccount disables automatic API-token mounting. It is an automation identity; it does not create a human login or deploy an observer application.

Administrator-authorized impersonation was used to verify its permissions without generating credentials.

### Verified behavior

| Action | Result |
| --- | --- |
| List development Pods | Allowed; Pod listing succeeded |
| Read reference-service logs | Allowed; log retrieval succeeded |
| Patch development Deployments | Denied by authorization check |
| Get development Secrets | Denied by authorization check |
| List Argo CD Pods | Denied by authorization check |

Repeat the viewing checks:

```bash
kubectl get pods \
  --namespace development \
  --context kind-internal-developer-platform \
  --as=system:serviceaccount:development:development-observer

kubectl logs deployment/reference-service \
  --tail=5 \
  --namespace development \
  --context kind-internal-developer-platform \
  --as=system:serviceaccount:development:development-observer
```

Repeat the authorization checks:

```bash
kubectl auth can-i patch deployments \
  --namespace development \
  --context kind-internal-developer-platform \
  --as=system:serviceaccount:development:development-observer

kubectl auth can-i get secrets \
  --namespace development \
  --context kind-internal-developer-platform \
  --as=system:serviceaccount:development:development-observer

kubectl auth can-i list pods \
  --namespace argocd \
  --context kind-internal-developer-platform \
  --as=system:serviceaccount:development:development-observer
```

Each authorization check should return `no`. These checks do not perform the requested action.

Kubernetes RBAC permissions are additive. Additional bindings could grant this identity further access.

## Scope and remaining work

The implemented controls establish a development baseline:

- Resource budgets and admission defaults.
- Restricted application process permissions.
- Verified application network restrictions.
- Scoped read access for an observer identity.
- Argo CD project boundaries for workload and environment resources.

Remaining work includes:

- Investigating the recurring networking/controller failures.
- Managed application secrets when a workload requires them.
- Human authentication and access provisioning.
- Reviewing Argo CD administrator access and its default project.
- A read-only application filesystem.
- Monitoring and repeatable recovery procedures.

The reference service currently has no secret dependency. No managed application-secret system has been configured.

Argo CD AppProjects constrain Argo CD Applications. Kubernetes RBAC controls Kubernetes API access. Neither establishes complete tenant isolation on its own.

The cluster remains a single-node local environment administered through privileged bootstrap credentials.

## Related documentation

- [Local development](local-development.md)
- [Image delivery](image-delivery.md)
- [Platform architecture](architecture.md)
- [Kubernetes NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Kubernetes RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
