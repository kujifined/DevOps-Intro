# Lab 10 - Cloud Computing: QuickNotes Release and Cloud Deploy

## Summary

This lab ships QuickNotes as a production-style release:

- signed Git tag `v0.1.0`
- GitHub Actions release workflow
- GHCR image with immutable and `latest` tags
- Hugging Face Space deployment from the same release image
- warm/cold latency measurements
- Cloudflare Tunnel bonus comparison

## Task 1 - CI-Automated Push to GHCR

### Release workflow

Path: `.github/workflows/release.yml`

```yaml
name: release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: read
  packages: write

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: false

env:
  REGISTRY: ghcr.io
  IMAGE_SUFFIX: quicknotes

jobs:
  quicknotes-image:
    name: Build and push QuickNotes image
    runs-on: ubuntu-24.04
    timeout-minutes: 15

    steps:
      - name: Check out repository
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Validate release tag and image name
        shell: bash
        run: |
          if [[ ! "${GITHUB_REF_NAME}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Release tag must be semantic version format like v0.1.0"
            exit 1
          fi

          repository="${GITHUB_REPOSITORY,,}"
          echo "IMAGE_NAME=${REGISTRY}/${repository}/${IMAGE_SUFFIX}" >> "$GITHUB_ENV"
          echo "VERSION=${GITHUB_REF_NAME}" >> "$GITHUB_ENV"

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@74a5d142397b4f367a81961eba4e8cd7edddf772 # v3.4.0
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up QEMU
        uses: docker/setup-qemu-action@29109295f81e9208d7d86ff1c6c12d2833863392 # v3.6.0

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@b5ca514318bd6ebac0fb2aedd5d36ec1b5c232a2 # v3.10.0

      - name: Build and push image
        uses: docker/build-push-action@263435318d21b8e681c14492fe198d362a7d2c83 # v6.18.0
        with:
          context: ./app
          platforms: linux/amd64,linux/arm64
          push: true
          provenance: true
          tags: |
            ${{ env.IMAGE_NAME }}:${{ env.VERSION }}
            ${{ env.IMAGE_NAME }}:latest
```

### Release tag

```bash
git tag -a -s v0.1.0 -m "Lab 10 release"
git push origin v0.1.0
```

### Release run

GitHub Actions run:

`PENDING_REAL_EVIDENCE: paste the green release run URL after pushing tag v0.1.0`

### Image

```text
ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
ghcr.io/kujifined/devops-intro/quicknotes:latest
```

### Clean pull evidence

```bash
docker rmi ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0 || true
docker pull ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
docker run --rm -p 8080:8080 ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
curl -v http://localhost:8080/health
```

Result:

```text
PENDING_REAL_EVIDENCE: paste successful unauthenticated pull and /health output.
```

Package visibility note:

```text
PENDING_REAL_EVIDENCE: after the first GHCR push, set the package visibility to public in GitHub Packages if it was created as private. Verify the pull after docker logout ghcr.io.
```

### Design question a - OIDC vs GITHUB_TOKEN

For pushing to GHCR from the same repository, `GITHUB_TOKEN` with `packages: write` is enough. GitHub Actions can authenticate to GitHub Packages without storing a long-lived PAT, and the token is already scoped to the repository workflow context.

I would use OIDC when the workflow needs to cross a trust boundary, for example deploying to AWS, GCP, Azure, or another external platform. OIDC lets the workflow exchange its GitHub identity for short-lived, scoped, auditable cloud credentials. That avoids storing static cloud secrets in GitHub and allows the cloud side to verify claims such as repository, branch, tag, and workflow.

### Design question b - `latest` vs immutable version tag

The immutable tag, such as `v0.1.0`, is the source of truth for reproducible deployments and rollback. It identifies exactly which release artifact is running.

The `latest` tag is still useful as a convenience pointer for humans, demos, local smoke tests, and environments that intentionally track the newest stable release. Production deployments should pin the immutable tag, but publishing `latest` improves discoverability and simple operational workflows.

### Design question c - `packages: write` only

The principle is least privilege: the workflow should receive only the permissions required for its job.

This release workflow only needs to read repository contents and write packages. Granting broad write permissions would allow unnecessary repository mutations if a workflow dependency or build step were compromised. Narrow permissions limit blast radius: the release job can publish the container image, but it cannot freely modify code, pull requests, issues, or unrelated repository resources.

## Task 2 - Hugging Face Spaces

### Space URL

`PENDING_REAL_EVIDENCE: paste the public Hugging Face Space URL, for example https://kujifined-quicknotes-lab10.hf.space`

### Health check

```bash
curl -v "$HF_SPACE_URL/health"
```

Result:

```text
PENDING_REAL_EVIDENCE: paste HTTP 200 response and QuickNotes health JSON.
```

### Notes endpoint

```bash
curl -v "$HF_SPACE_URL/notes"
```

Result:

```text
PENDING_REAL_EVIDENCE: paste HTTP 200 response and QuickNotes notes JSON.
```

### Space Dockerfile

Path in this repository: `cloud/hf/Dockerfile`

```Dockerfile
FROM ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
```

### Space README.md

Path in this repository: `cloud/hf/README.md`

```markdown
---
title: QuickNotes Lab 10
emoji: 📝
colorFrom: blue
colorTo: indigo
sdk: docker
app_port: 8080
pinned: false
---

# QuickNotes Lab 10

QuickNotes deployed to Hugging Face Spaces from the immutable GHCR release image.

Image:

`ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0`
```

### Why pull from GHCR?

I chose to pull the already released GHCR image instead of rebuilding the application inside the Space. This makes the Space deployment use exactly the same artifact that CI built and published from the signed release tag. It improves reproducibility and makes debugging simpler: if the image works locally and in GHCR, the Space is only responsible for running that image.

### Warm latency

Five consecutive warm requests:

```bash
for i in 1 2 3 4 5; do
  curl -o /dev/null -s -w "%{time_total}\n" \
    "$HF_SPACE_URL/health"
done
```

Measurements:

```text
PENDING_REAL_EVIDENCE
PENDING_REAL_EVIDENCE
PENDING_REAL_EVIDENCE
PENDING_REAL_EVIDENCE
PENDING_REAL_EVIDENCE
```

Sorted:

```text
PENDING_REAL_EVIDENCE
```

Warm p50:

```text
PENDING_REAL_EVIDENCE s
```

### Cold latency

Each cold measurement was taken after 35+ minutes of inactivity.

```text
Cold #1: PENDING_REAL_EVIDENCE s
Cold #2: PENDING_REAL_EVIDENCE s
Cold #3: PENDING_REAL_EVIDENCE s
```

### Design question d - HF Spaces sleep vs Cloud Run scale to zero

Both systems remove idle capacity, but they optimize for different products. Cloud Run is a production serverless container platform, so it invests heavily in fast scheduling, request routing, image caching, concurrency, and configurable minimum instances. HF Spaces is optimized for simple public demos and ML apps on a free tier. A sleeping Space may need to allocate demo capacity, restore the container environment, pull or prepare the image, and restart the app before the request can complete. That makes wakeups much slower, but the platform stays accessible without a credit card.

### Design question e - Why `app_port: 8080`?

QuickNotes listens on port `8080`. Hugging Face Docker Spaces default to port `7860`, which matches common Gradio demo apps. Without `app_port: 8080`, HF would route traffic to the wrong container port and the Space would look broken even if the process started correctly.

### Design question f - Pulling from GHCR vs building in the Space

Pulling from GHCR makes deployment consume the exact release artifact produced by CI. That is more reproducible and easier to debug because the same immutable image can be tested locally, pulled from a clean machine, and run in the Space.

Building inside the Space can be convenient when the Space repository owns the whole app source, and HF build logs may directly show source-level build failures. The trade-off is weaker release traceability: HF may rebuild at a different time with different cache state or base image state unless everything is pinned carefully.

## Bonus Task - Cloudflare Tunnel

### Tunnel commands

```bash
docker run --rm -p 8080:8080 \
  ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0

cloudflared tunnel --url http://localhost:8080
```

### Public URL

`PENDING_REAL_EVIDENCE: paste the ephemeral trycloudflare.com URL from cloudflared`

### External verification

```bash
curl -v "$CLOUDFLARE_URL/health"
```

Result:

```text
PENDING_REAL_EVIDENCE: verified from phone on cellular or another network; /health returned 200 OK.
```

### Latency

50 warm runs against `/health`.

```text
p50: PENDING_REAL_EVIDENCE s
p95: PENDING_REAL_EVIDENCE s
```

### Comparison table

| Metric | HF Spaces (hosted) | Cloudflare Tunnel (local-via-edge) |
|--------|-------------------:|-----------------------------------:|
| Warm p50 | PENDING_REAL_EVIDENCE s | PENDING_REAL_EVIDENCE s |
| Warm p95 | PENDING_REAL_EVIDENCE s | PENDING_REAL_EVIDENCE s |
| Cold start | PENDING_REAL_EVIDENCE s / PENDING_REAL_EVIDENCE s / PENDING_REAL_EVIDENCE s | N/A, continuously local |
| Public URL stability | stable while Space exists | ephemeral on restart |
| Cost | free | free |

### Design question g - Architectural difference

In HF Spaces, the container runs in Hugging Face infrastructure and users reach an app hosted by the platform. In Cloudflare Tunnel, the container runs on my local machine and Cloudflare proxies public traffic through an outbound tunnel.

HF Spaces is more clearly "cloud hosted" because the workload itself runs in the provider's datacenter. Cloudflare Tunnel still uses cloud networking, but not cloud compute for the application. For users, the distinction matters less than reliability, latency, availability, and operational ownership. For operators, it matters a lot because a laptop-backed service depends on local power, network, and process uptime.

### Design question h - Latency dominator

For HF Spaces warm requests, the dominant cost is normal internet routing plus the hosted container's request handling inside HF's infrastructure. The app itself is tiny, so platform routing and network distance dominate.

For Cloudflare Tunnel, the dominant cost is the proxy path: client to Cloudflare edge, edge through the tunnel connection back to the local machine, then the response back through that same path. The local app is fast, but the extra relay and home/local network conditions dominate.

### Design question i - When Cloudflare Tunnel is the right production pick

Cloudflare Tunnel can be a good production choice for exposing private services without inbound firewall holes: home labs, small on-prem dashboards, internal admin tools, or controlled stakeholder previews. It is especially useful when the application must stay on local or private infrastructure but still needs authenticated external access.

It is not the right pick for public production services that need high availability, independent scaling, stable compute, and predictable operations. If the only running instance is on a laptop or a single local machine, the service inherits that machine's uptime and network reliability.
