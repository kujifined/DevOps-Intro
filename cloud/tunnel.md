# Cloudflare Tunnel Notes

## Image

`ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0`

## Local run

```bash
docker run --rm -p 8080:8080 \
  ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
```

## Quick tunnel

```bash
cloudflared tunnel --url http://localhost:8080
```

## Public URL

`PENDING_REAL_EVIDENCE: paste the ephemeral trycloudflare.com URL from cloudflared`

Quick tunnels are ephemeral. The URL changes after restarting `cloudflared`.

## External verification

Verify from a different network, for example a phone on cellular:

```bash
curl -v "$CLOUDFLARE_URL/health"
```

Expected result: `200 OK` and QuickNotes health JSON.

## Latency

50 warm runs against `/health`:

```bash
for i in $(seq 1 50); do
  curl -o /dev/null -s -w "%{time_total}\n" \
    "$CLOUDFLARE_URL/health"
done | sort -n | tee cloud/cloudflare-times.txt

awk 'NR==25{print "p50 approx:", $1} NR==48{print "p95 approx:", $1}' \
  cloud/cloudflare-times.txt
```

- p50: `PENDING_REAL_EVIDENCE s`
- p95: `PENDING_REAL_EVIDENCE s`
