# Kubernetes

Helm chart: [`charts/deployment-platform`](charts/deployment-platform). It installs the API, the worker, and a migration Job. It does not install PostgreSQL. Real environments use RDS. CI uses the throwaway Postgres manifest in [`ci/postgres.yaml`](ci/postgres.yaml).

Images are `<owner>/devops-api`, `<owner>/devops-worker`, and `<owner>/devops-migrate`, tagged with `image.tag`.

## What the chart deploys

| Resource | Name | Role |
|----------|------|------|
| Deployment | `<fullname>-api` | API. Container port is `api.port` (3000). |
| Service | `<fullname>-api` | ClusterIP. Port 80 targets the API container. |
| HorizontalPodAutoscaler | `<fullname>-api` | Present when `api.autoscaling.enabled` is true. The Deployment then omits `replicas` and the HPA owns the count. |
| PodDisruptionBudget | `<fullname>-api` | Present when `api.pdb.enabled` is true. |
| Ingress | `<fullname>-api` | Present when `ingress.enabled` is true. Off by default. |
| Deployment | `<fullname>-worker` | Polls the database and moves deployments from `pending` to `running`, then `succeeded` or `failed`. |
| Job | `<fullname>-migrate` | Helm `pre-install,pre-upgrade` hook. Runs `scripts/run_migrations.py`. |

`<fullname>` is `fullnameOverride` when that is set. Otherwise Helm combines the release name and the chart name.

The API and worker read `DATABASE_URL` from the Secret named by `database.existingSecret` (default `dp-db`), key `DATABASE_URL`.

## Values that matter

Defaults are in [`charts/deployment-platform/values.yaml`](charts/deployment-platform/values.yaml).

| Value | Default | Why it matters |
|-------|---------|----------------|
| `image.owner` | `""` | Docker Hub namespace. Empty renders an image name with no registry user. |
| `image.tag` | `""` | Image tag. Empty falls back to `Chart.appVersion` (`latest`). CI sets the git SHA. |
| `image.pullPolicy` | `IfNotPresent` | Kind can use images loaded with `kind load` and does not try to pull them. |
| `database.existingSecret` | `dp-db` | Secret that already exists in the release namespace. Key `DATABASE_URL`. |
| `migrations.enabled` | `true` | Turns the migrate hook on or off. |
| `api.replicaCount` | `2` | Used only when autoscaling is disabled. |
| `api.autoscaling` | on, min 2, max 5, CPU 70% | HPA for the API. Needs metrics-server. |
| `api.pdb.minAvailable` | `1` | How many API pods must stay up during voluntary disruption. |
| `worker.replicaCount` | `1` | Worker replicas. |
| `worker.env` | poll 5000 ms, processing 3000 ms, failure rate `0.1` | Worker timing and the chance a deployment is marked `failed`. |
| `ingress.enabled` | `false` | Exposes the API through an Ingress when set. |
| `podAnnotations` | `{}` | Extra pod annotations. CI sets `rollme` on upgrade so the pod template changes and Deployments roll. |

[`ci/values-kind.yaml`](ci/values-kind.yaml) is the local and CI overlay: `fullnameOverride` `dp`, `image.owner` `local`, one API replica, HPA min 1, worker processing 500 ms, and failure rate `0`. The failure rate is `0` so a smoke test can require status `succeeded`. Helm merges `worker.env`, so the chart's poll interval stays 5000 ms.

## Probes

Liveness is `GET /health`. That handler returns `{"status":"ok"}` and does not touch the database. Kubernetes restarts the container when liveness fails. A database check on this probe would restart the API every time Postgres is briefly unavailable.

Readiness is `GET /ready`. That handler checks the database and returns 503 when the check fails. Kubernetes drops the pod from Service endpoints and leaves the process running. Traffic resumes when the database accepts connections again.

## Migrations and the database Secret

The migrate Job is a `pre-install,pre-upgrade` hook. Helm runs hooks before it creates the rest of the release, so this Job cannot mount a Secret that the same chart would create. Create the Secret before `helm install` or `helm upgrade`.

The chart stores only the Secret name. The connection string stays out of values and out of git. On AWS that Secret is the one backed by RDS and Secrets Manager. Locally and in CI it is a Kubernetes Secret you create yourself.

`run_migrations.py` takes a Postgres advisory lock, so overlapping hook runs do not apply the same migration twice. The hook delete policy is `before-hook-creation,hook-succeeded`: a successful Job is removed, and the next upgrade removes the previous Job before starting a new one. A failed migration leaves the Job so you can read its logs.

## Run locally with kind

From the repository root. You need Docker, kind, kubectl, Helm, jq, and Python 3.12 with `scripts/requirements.txt` installed.

CI sets `TAG` to the commit SHA and creates the cluster with `helm/kind-action` (`cluster_name: dp`). Locally, pick any tag and create the cluster yourself:

```bash
NS=dp
TAG=dev

kind create cluster --name dp

docker build -t "local/devops-api:${TAG}" ./app
docker build -t "local/devops-worker:${TAG}" ./worker
docker build -t "local/devops-migrate:${TAG}" -f migrate/Dockerfile .

kind load docker-image "local/devops-api:${TAG}" --name dp
kind load docker-image "local/devops-worker:${TAG}" --name dp
kind load docker-image "local/devops-migrate:${TAG}" --name dp
```

The API HPA needs metrics. Kind's kubelet certificate is not one metrics-server trusts, so the install adds `--kubelet-insecure-tls`:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl create namespace "$NS"
kubectl apply -n "$NS" -f k8s/ci/postgres.yaml
kubectl rollout status deployment/postgres -n "$NS" --timeout=3m

kubectl create secret generic dp-db \
  --namespace "$NS" \
  --from-literal=DATABASE_URL=postgres://postgres:postgres@postgres:5432/cloud-native-deployment-platform

helm upgrade --install dp k8s/charts/deployment-platform \
  --namespace "$NS" \
  --values k8s/ci/values-kind.yaml \
  --set "image.tag=${TAG}" \
  --wait \
  --timeout 5m
```

`fullnameOverride` is `dp`, so the Service is `svc/dp-api`. Port-forward and run the same health check CI runs:

```bash
pip install -r scripts/requirements.txt

kubectl port-forward -n "$NS" svc/dp-api 8080:80 &
python scripts/health_check.py --alb-dns localhost:8080 --retries 5 --skip-aws
```

To exercise the worker, create a deployment and wait until it succeeds. CI polls every 2 seconds, up to 30 times, and exits on `failed`:

```bash
id=$(curl -fsS -X POST http://localhost:8080/deployments \
  -H 'Content-Type: application/json' \
  -d "{\"service\":\"smoke\",\"version\":\"${TAG}\"}" | jq -r '.id')

curl -fsS "http://localhost:8080/deployments/${id}"
```

An upgrade with a new pod annotation rolls the API and worker and runs the migrate hook again. CI uses `github.run_id` as `rollme`. Any new string does the same thing locally:

```bash
helm upgrade dp k8s/charts/deployment-platform \
  --namespace "$NS" \
  --values k8s/ci/values-kind.yaml \
  --set "image.tag=${TAG}" \
  --set-string "podAnnotations.rollme=$(date +%s)" \
  --wait \
  --timeout 5m

python scripts/health_check.py --alb-dns localhost:8080 --retries 5 --skip-aws
helm history dp --namespace "$NS"
```

Tear down with `kind delete cluster --name dp`.

## What CI proves

[`.github/workflows/k8s-ci.yml`](../.github/workflows/k8s-ci.yml) runs on pull requests and pushes to `main` when the app, worker, migrate image, migrations, chart, or that workflow change, and on `workflow_dispatch`.

`chart-lint` renders the chart with `image.owner=local` and `image.tag` set to the commit SHA. `helm lint` must pass, and `kubeconform -strict` must accept every manifest.

`kind-smoke` then does the steps above on a real cluster, with `TAG` set to the commit SHA:

- The three images build and the chart becomes ready, which means the migrate hook applied the schema and the API readiness probe reached Postgres.
- `scripts/health_check.py --skip-aws` gets HTTP 200 from `/` and `/health` through the Service.
- `POST /deployments` is stored, the worker claims it, and the row reaches `succeeded`. That is the API, Postgres, and worker on one path. Failure rate is `0` in the Kind values, so a `failed` status fails the job immediately.
- A second `helm upgrade` changes `podAnnotations.rollme`, so pods roll and the migrate hook runs again. The health check passes on the new pods, and `helm history` shows the new revision.

If a step fails, the job prints `kubectl get all`, events sorted by `lastTimestamp`, `kubectl describe pods`, logs for pods labeled `app.kubernetes.io/instance=dp`, and logs for Job `dp-migrate` when that Job is still in the namespace.
