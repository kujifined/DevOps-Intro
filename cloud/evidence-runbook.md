# Lab 10 Evidence Runbook

Use this checklist after committing the lab files. Do not submit while the lab
report still contains evidence placeholders.

## 1. Release image to GHCR

```bash
git status --short
git tag -a -s v0.1.0 -m "Lab 10 release"
git push origin v0.1.0
```

Wait for the `release` workflow to finish green, then copy the GitHub Actions
run URL into `submissions/lab10.md`.

If the tag already exists and must be recreated before submission:

```bash
git tag -d v0.1.0
git push origin :refs/tags/v0.1.0
git tag -a -s v0.1.0 -m "Lab 10 release"
git push origin v0.1.0
```

## 2. Verify unauthenticated GHCR pull

If GitHub Packages created the image as private after the first push, change
the package visibility to public in the GitHub UI.

```bash
docker logout ghcr.io
docker rmi ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0 || true
docker pull ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
docker run --rm -p 8080:8080 ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
```

In another terminal:

```bash
curl -v http://localhost:8080/health
curl -v http://localhost:8080/notes
```

Paste the relevant `docker pull`, `/health`, and `/notes` output into
`submissions/lab10.md`.

## 3. Deploy Hugging Face Space

Create a public Docker Space named `quicknotes-lab10`, then push the contents
of `cloud/hf/` to the Space repository root:

```bash
cp cloud/hf/Dockerfile /path/to/hf-space/Dockerfile
cp cloud/hf/README.md /path/to/hf-space/README.md
cd /path/to/hf-space
git add Dockerfile README.md
git commit -m "Deploy QuickNotes from GHCR image"
git push
```

After the Space build is green:

```bash
export HF_SPACE_URL="https://kujifined-quicknotes-lab10.hf.space"
curl -v "$HF_SPACE_URL/health"
curl -v "$HF_SPACE_URL/notes"
```

Paste the real Space URL and both outputs into `submissions/lab10.md`.

## 4. Measure Hugging Face warm latency

```bash
for i in 1 2 3 4 5; do
  curl -o /dev/null -s -w "%{time_total}\n" "$HF_SPACE_URL/health"
done
```

Sort the five values. The p50 is the third value after sorting.

## 5. Measure Hugging Face cold latency

Repeat three times:

1. Leave the Space idle for at least 35 minutes.
2. Run one cold request:

```bash
curl -o /dev/null -s -w "%{time_total}\n" "$HF_SPACE_URL/health"
```

Paste all three cold measurements into `submissions/lab10.md`.

## 6. Run Cloudflare Tunnel bonus

```bash
docker run --rm -p 8080:8080 \
  ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
```

In another terminal:

```bash
cloudflared tunnel --url http://localhost:8080
```

Export the generated URL:

```bash
export CLOUDFLARE_URL="https://something-random.trycloudflare.com"
curl -v "$CLOUDFLARE_URL/health"
```

Verify the same URL from a different network, for example a phone on cellular.

## 7. Measure Cloudflare Tunnel latency

```bash
for i in $(seq 1 50); do
  curl -o /dev/null -s -w "%{time_total}\n" "$CLOUDFLARE_URL/health"
done | sort -n | tee cloud/cloudflare-times.txt

awk 'NR==25{print "p50 approx:", $1} NR==48{print "p95 approx:", $1}' \
  cloud/cloudflare-times.txt
```

Paste p50, p95, and the external verification note into
`submissions/lab10.md` and `cloud/tunnel.md`.

## 8. Final checks

```bash
marker="PENDING_REAL""_EVIDENCE"
grep -RIn "$marker" submissions/lab10.md cloud/tunnel.md || true
git status --short
git log --show-signature -1
```

The grep command must produce no matches before final submission.
