# Cloudflare Tunnel Notes

## Image

`ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0`

## Local run

```bash
docker run --rm -p 18080:8080 \
  ghcr.io/kujifined/devops-intro/quicknotes:v0.1.0
```

## Quick tunnel

```bash
docker run --rm --name quicknotes-lab10-cloudflared \
  cloudflare/cloudflared:latest tunnel \
  --url http://host.docker.internal:18080
```

## Public URL

`https://those-civilian-distinct-reveals.trycloudflare.com`

Quick tunnels are ephemeral. The URL changes after restarting `cloudflared`.

## External verification

Verify from a different network, for example a phone on cellular:

```bash
curl -v "$CLOUDFLARE_URL/health"
```

Expected result: `200 OK` and QuickNotes health JSON.

Observed result:

```text
GET /health HTTP/2
< HTTP/2 200
{"notes":4,"status":"ok"}
```

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

- p50: `0.386789 s`
- p95: `0.451584 s`
