# Kubernetes packaging

This directory shows two complementary ways to run the same API on Kubernetes: **plain manifests** for clarity, and a **Helm chart** for installable, configurable deployments.

The cloud path for this repo is **ECS Fargate + ALB**, provisioned by Terraform (`infra/`). Nothing here duplicates that automation. These manifests are deliberate **skills evidence** — useful for local clusters (kind, minikube, Docker Desktop Kubernetes), or a future migration to EKS/GKE without wedging Helm into Terraform today.

## Layout

```
k8s/
├── manifests/           # Vanilla YAML — educational baseline
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
└── helm/devops-api/     # Packaged chart
    ├── Chart.yaml
    ├── values.yaml
    └── templates/
```

## Design choices (brief)

| Area | Choice | Rationale |
|------|--------|-----------|
| **Replicas** | `2` | Availability over a single pod; pairs with HPA in Helm. |
| **Image** | `mpeets/devops-api:latest` (defaults) | Aligns with CI image name; `imagePullPolicy: Always` when using floating tags. |
| **Probes** | Liveness vs readiness on `/health` | Readiness gates traffic; shorter intervals avoid slow rollouts without hiding failures. |
| **Resources** | Requests + limits (`100m`/128Mi → `250m`/256Mi) | Realistic guardrails for a small Node service. |
| **Rollout** | `maxUnavailable: 0`, `maxSurge: 1` | Zero-downtime rolling updates where the scheduler allows. |
| **Service** | `ClusterIP` | External access is delegated to Ingress (or NLB/Ingress Controller in cloud). |
| **Ingress** | `ingressClassName: nginx`, host `devops-api.local` | Portable pattern; TLS block commented in raw YAML for local/dev without certs. |
| **Helm extras** | HPA, ServiceAccount | Chart shows autoscaling and identity without cluttering the raw baseline. |

## Raw manifests

Apply order does not strictly matter for a first install; Kubernetes reconciles types.

```bash
kubectl apply -f k8s/manifests/
```

Dry-run (no cluster changes):

```bash
kubectl apply -f k8s/manifests/ --dry-run=client
```

Edit names, hosts, and image references for your environment before production use.

## Helm chart

Render manifests without installing:

```bash
helm template demo ./k8s/helm/devops-api
```

Lint (when Helm is installed):

```bash
helm lint ./k8s/helm/devops-api
```

Install example (namespace and flags as you prefer):

```bash
helm upgrade --install demo ./k8s/helm/devops-api --namespace devops --create-namespace
```

Override image for a local build (split repository and tag to match `docker build -t repo:tag`):

```bash
helm upgrade --install demo ./k8s/helm/devops-api -n devops --create-namespace \
  --set image.repository=devops-api \
  --set image.tag=local \
  --set image.pullPolicy=IfNotPresent
```

## CI validation (GitHub Actions)

Workflow: [`.github/workflows/k8s-lint.yml`](../.github/workflows/k8s-lint.yml). On **push or pull_request** targeting **`main`**, runs only when files under **`k8s/`** change. It runs **helm lint**, pipes **helm template** into **kubeconform** (validates the rendered chart against a pinned Kubernetes OpenAPI schema — no cluster), then **kubeconform** again for **`k8s/manifests/*.yaml`**.

**Why paths are only `k8s/**`:** this job validates packaging YAML, not application source. Updates under `app/` or `worker/` do not mutate those files unless you edit image tags or related values here; widening paths would rerun the workflow on unrelated Node commits. Use **manual re-run** in the Actions UI after changing app behavior if you want another pass without touching `k8s/`.

## Local cluster (e.g. Docker Desktop)
1. Enable **Kubernetes** in Docker Desktop and wait until it is running.
2. `kubectl config use-context docker-desktop` (or whatever `kubectl config get-contexts` shows).
3. Install an **Ingress controller** that satisfies `ingressClassName: nginx` (e.g. **ingress-nginx** Helm chart).
4. Map the Ingress host to the loopback address your controller uses (often `127.0.0.1 devops-api.local` in the OS hosts file).
5. Build and tag the app image if you are not pulling from a registry, then install with overrides as above.

Expect brief **503** responses from the ingress while pods are still `ContainerCreating` or failing readiness; confirm `kubectl get pods -n <ns>` shows `Running` and `READY` before calling the URL final.