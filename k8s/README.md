# Kubernetes packaging

This directory ships a **Helm chart** for installable, configurable deployments of the API (including HPA and optional ServiceAccount).

## How this relates to the rest of the repo

The **primary cloud path** in this repository is **ECS Fargate + ALB**, provisioned by Terraform ([`infra/`](../infra/README.md)). Nothing here replaces that automation. These assets are **portable packaging**: useful on local clusters (kind, minikube, Docker Desktop Kubernetes), teaching, or a later move to managed Kubernetes **without** folding Helm into Terraform today.

For a **full stack with PostgreSQL** on one machine, see [`docker/`](../docker/README.md). The YAML in `k8s/` deploys the **API container only**; it does not create a database or inject `DATABASE_URL`. Endpoints that need the database (for example **`/deployments`** and **`/ready`**) only work once you wire Postgres yourself (Secret/ConfigMap, sidecar, or external service).

## Layout

```
k8s/
├── README.md
└── helm/devops-api/
    ├── Chart.yaml                 # chart v0.1.0, appVersion 1.0.0
    ├── values.yaml
    └── templates/
        ├── _helpers.tpl
        ├── deployment.yaml
        ├── hpa.yaml              # emitted when autoscaling.enabled is true
        ├── ingress.yaml
        ├── service.yaml
        └── serviceaccount.yaml   # emitted when serviceAccount.create is true
```

## Design choices (brief)

| Area | Choice | Rationale |
|------|--------|-----------|
| **Replicas** | Helm defaults `replicaCount: 2` | Availability over a single pod. With **autoscaling on**, the Deployment uses **`autoscaling.minReplicas`** (2) as the replica count; HPA scales between min and max. |
| **Image** | `mpeets/devops-api:latest` (defaults) | Aligns with CI image naming; `imagePullPolicy: Always` when using floating tags. |
| **Probes** | Liveness hits **`/health`**; readiness hits **`/ready`** | Liveness stays a fast process check, while readiness waits for the database before sending traffic to the pod. |
| **Resources** | Requests + limits (`100m` / 128Mi → `250m` / 256Mi) | Realistic guardrails for a small Node service. |
| **Rollout** | `maxUnavailable: 0`, `maxSurge: 1` | Zero-downtime rolling updates where the scheduler allows. |
| **Service** | `ClusterIP`, port **80** → container **3000** | Internal cluster access; Ingress fronts port 80. |
| **Ingress** | `ingressClassName: nginx`, host `devops-api.local` | Portable pattern; TLS configurable via `values.yaml`. |
| **Helm extras** | **HPA** (`autoscaling/v2`, CPU average **80%**, min **2** / max **5**), **ServiceAccount** | Autoscaling and pod identity. |

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

To turn off autoscaling and use a fixed replica count from `values.yaml`:

```bash
helm upgrade --install demo ./k8s/helm/devops-api -n devops --create-namespace \
  --set autoscaling.enabled=false \
  --set replicaCount=2
```

## CI validation (GitHub Actions)

Workflow: [`.github/workflows/k8s-lint.yml`](../.github/workflows/k8s-lint.yml).

| Trigger | Scope |
|--------|--------|
| **push** / **pull_request** to **`main`** | Only when paths under **`k8s/**`** change. |
| **workflow_dispatch** | Manual run anytime. |

Steps (current tooling as pinned in the workflow):

1. **`helm lint`** on `k8s/helm/devops-api/`.
2. **`helm template`** piped to **kubeconform** — validates rendered chart objects against a pinned Kubernetes OpenAPI schema (**1.30.0**), no cluster required.

Helm CLI in CI: **v3.14.4**. Kubeconform: **v0.6.7**.

**Why paths are only `k8s/**`:** the job validates packaging YAML, not application source. Commits under `app/` or `worker/` do not touch these files unless you change image tags or values here. Use **workflow_dispatch** or a manual re-run if you want another pass without editing `k8s/`.

## Local cluster (e.g. Docker Desktop)

1. Enable **Kubernetes** in Docker Desktop and wait until it is running.
2. `kubectl config use-context docker-desktop` (or whatever `kubectl config get-contexts` shows).
3. Install an **Ingress controller** that satisfies `ingressClassName: nginx` (for example the **ingress-nginx** Helm chart).
4. Map the Ingress host to the loopback address your controller uses (often `127.0.0.1 devops-api.local` in the OS hosts file).
5. Build and tag the app image if you are not pulling from a registry, then install with overrides as above.
6. If you need a working **`/deployments`** API (or **`/ready`**), run Postgres and set **`DATABASE_URL`** for the pods.

Expect brief **503** responses from the ingress while pods are still `ContainerCreating` or failing readiness; confirm `kubectl get pods -n <ns>` shows **Running** and **READY** before calling the URL again.
