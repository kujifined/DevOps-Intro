# Lab 9 - DevSecOps: Trivy, ZAP, and govulncheck

## Goal

Scan the QuickNotes image and repository, triage scanner findings as engineering decisions, fix web security issues in code, and add a pinned Go vulnerability gate to CI.

## Repository changes

- Reused the Lab 6 distroless `quicknotes:lab6` container setup.
- Upgraded the image builder and CI Go toolchain from vulnerable Go `1.24.13` to fixed Go `1.25.11`.
- Added global HTTP security headers middleware for all QuickNotes routes.
- Added a unit test that fails if the middleware is removed from `Server.Handler()`.
- Added a pinned `govulncheck` CI job as a separate PR gate.
- Committed Trivy, CycloneDX SBOM, ZAP before/after, and govulncheck evidence under `security/`.

## Tool versions

| Tool | Pinned version |
|---|---|
| Trivy | `aquasec/trivy:0.59.1` |
| OWASP ZAP | `ghcr.io/zaproxy/zaproxy:2.17.0` |
| Go toolchain | `1.25.11` |
| govulncheck | `golang.org/x/vuln/cmd/govulncheck@v1.1.4` |

## Task 1 - Trivy scans and SBOM

### Commands

```bash
docker compose build quicknotes

docker run --rm \
  -v /private/tmp/trivy-cache:/root/.cache/trivy \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.59.1 \
  image --severity HIGH,CRITICAL quicknotes:lab6 \
  > security/trivy/trivy-image-high-critical.txt 2>&1

docker run --rm \
  -v /private/tmp/trivy-cache:/root/.cache/trivy \
  -v "$PWD:/repo" \
  -w /repo \
  aquasec/trivy:0.59.1 \
  fs --scanners vuln --severity HIGH,CRITICAL \
  --skip-dirs .venv --skip-dirs .cache --skip-dirs security . \
  > security/trivy/trivy-fs-high-critical.txt 2>&1

docker run --rm \
  -v /private/tmp/trivy-cache:/root/.cache/trivy \
  -v "$PWD:/repo" \
  -w /repo \
  aquasec/trivy:0.59.1 \
  config --skip-dirs .venv --skip-dirs .cache --skip-dirs security . \
  > security/trivy/trivy-config.txt 2>&1

docker run --rm \
  -v /private/tmp/trivy-cache:/root/.cache/trivy \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/security/sbom:/out" \
  aquasec/trivy:0.59.1 \
  image --format cyclonedx --output /out/quicknotes-cyclonedx.json quicknotes:lab6
```

The local `.venv`, `.cache`, and generated `security/` directories are skipped for repo scans because they are machine artifacts, not QuickNotes source.

### Scan excerpts

Image scan:

```text
quicknotes:lab6 (debian 13.5)
=============================
Total: 0 (HIGH: 0, CRITICAL: 0)
```

Filesystem scan:

```text
INFO [vuln] Vulnerability scanning is enabled
INFO Number of language-specific files num=1
INFO [gomod] Detecting vulnerabilities...
```

Config scan:

```text
ERROR [rego] Error occurred while parsing. Trying to fallback to embedded check
ERROR [rego] Failed to find embedded check, skipping
ERROR [rego] Error occurred while parsing
INFO Detected config files num=1

app/Dockerfile (dockerfile)
===========================
Tests: 28 (SUCCESSES: 27, FAILURES: 1)
Failures: 1 (UNKNOWN: 0, LOW: 1, MEDIUM: 0, HIGH: 0, CRITICAL: 0)

AVD-DS-0026 (LOW): Add HEALTHCHECK instruction in your Dockerfile
```

The `rego` errors come from Trivy's downloaded built-in policy bundle, not from the QuickNotes Dockerfile or Compose file. Trivy fell back/skipped that broken upstream check and still detected one local config file: `app/Dockerfile`. I did not suppress those log lines because they are useful scanner-quality evidence, but they do not change the QuickNotes triage result.

Full artifacts:

- `security/trivy/trivy-image-high-critical.txt`
- `security/trivy/trivy-fs-high-critical.txt`
- `security/trivy/trivy-config.txt`
- `security/sbom/quicknotes-cyclonedx.json`

### Trivy HIGH/CRITICAL triage

| Source | Finding | Severity | Package/File | Disposition | Reason | Re-check date |
|---|---|---:|---|---|---|---|
| Image scan | No HIGH/CRITICAL findings after Go toolchain upgrade | - | `quicknotes:lab6` | FIX | The initial Go `1.24.13` build produced HIGH Go stdlib findings. Upgrading the builder to `golang:1.25.11-alpine` removed them from the final image scan. | - |
| Filesystem scan | No HIGH/CRITICAL findings | - | repository Go module | ACCEPT | Trivy did not report HIGH/CRITICAL dependency vulnerabilities in the source repository. | 2026-12-02 |
| Config scan | No HIGH/CRITICAL findings | - | `app/Dockerfile` | ACCEPT | The only QuickNotes config finding is LOW `AVD-DS-0026`; the Compose file already defines the runtime healthcheck because the distroless image has no shell. Trivy also logged upstream policy-bundle `rego` errors, documented above, but they are scanner-policy parse errors rather than repo misconfigurations. | 2026-12-02 |

### CycloneDX SBOM excerpt

```json
{
  "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
  "bomFormat": "CycloneDX",
  "specVersion": "1.6",
  "serialNumber": "urn:uuid:876a11ee-e9ac-4b1a-a4de-d3ac8af12769",
  "version": 1,
  "metadata": {
    "timestamp": "2026-07-02T21:10:39+00:00",
    "tools": {
      "components": [
        {
          "type": "application",
          "group": "aquasecurity",
          "name": "trivy",
          "version": "0.59.1"
        }
      ]
    },
    "component": {
      "bom-ref": "pkg:oci/quicknotes@sha256%3A90aff5d2eb6b4551a2e41f96874007dac5c2004be0f219155cb7b0f13f5c8906?arch=arm64&repository_url=index.docker.io%2Flibrary%2Fquicknotes",
      "type": "container",
      "name": "quicknotes:lab6",
      "purl": "pkg:oci/quicknotes@sha256%3A90aff5d2eb6b4551a2e41f96874007dac5c2004be0f219155cb7b0f13f5c8906?arch=arm64&repository_url=index.docker.io%2Flibrary%2Fquicknotes",
      "properties": [
        {
          "name": "aquasecurity:trivy:DiffID",
          "value": "sha256:187cfc6d1e3e8a40a5e64653bcd3239c140807dcf1c09e48021178705a5a6139"
        },
        {
```

### Design questions a-d

**a) CVE severity is one input, not the answer.** Severity says how bad the vulnerability can be in general, but triage also needs reachability, exploit availability, network exposure, runtime privileges, deployment topology, and compensating controls. A HIGH CVE in unreachable build-only code is not the same decision as a reachable bug in a public request path.

**b) Why minimal bases help.** Distroless images remove shells, package managers, and most OS utilities from the runtime image. That reduces both the number of components that can have CVEs and the tooling available after a compromise. The strongest control is not patching a package the app does not need; it is not shipping that package at all.

**c) When `.trivyignore` is valid.** It is valid for documented, reviewed, time-bounded exceptions: no upstream fix exists, the scanner is demonstrably wrong, or a risk is accepted with an owner and re-check date. It is security theater when it hides real risk only to make CI green.

**d) Why keep an SBOM today.** An SBOM lets us answer future incident questions quickly: "Do we ship component X or version Y?" During events like Log4Shell, teams with SBOMs can search deployed components instead of manually reverse-engineering every image under pressure.

## Task 2 - OWASP ZAP baseline and code fix

### Commands

The host already had another QuickNotes container bound to port `8080`, so ZAP was run against temporary containers through Docker's `--network container:<name>` mode. I used `http://127.0.0.1:8080/health` as the baseline seed URL because QuickNotes has no home page and `/` intentionally returns 404; the generated reports still show the same local app origin, `http://127.0.0.1:8080`, and ZAP also probed `/`, `/robots.txt`, and `/sitemap.xml`.

```bash
# Before: Lab 6 image without Lab 9 security header middleware.
docker run -d --rm --name quicknotes-lab9-before \
  -e ADDR=:8080 -e DATA_PATH=/tmp/notes.json -e SEED_PATH=/seed.json \
  --read-only --tmpfs /tmp quicknotes:lab9-before

docker run --rm \
  --network container:quicknotes-lab9-before \
  -v "$PWD/security/zap/before:/zap/wrk:rw" \
  ghcr.io/zaproxy/zaproxy:2.17.0 \
  zap-baseline.py -t http://127.0.0.1:8080/health \
  -r zap-baseline-before.html -J zap-baseline-before.json

# After: current Lab 9 image with middleware.
docker run -d --rm --name quicknotes-lab9-after \
  -e ADDR=:8080 -e DATA_PATH=/tmp/notes.json -e SEED_PATH=/seed.json \
  --read-only --tmpfs /tmp quicknotes:lab6

docker run --rm \
  --network container:quicknotes-lab9-after \
  -v "$PWD/security/zap/after:/zap/wrk:rw" \
  ghcr.io/zaproxy/zaproxy:2.17.0 \
  zap-baseline.py -t http://127.0.0.1:8080/health \
  -r zap-baseline-after.html -J zap-baseline-after.json
```

### ZAP findings triage

| ID | Name | Risk | URL / Parameter | Disposition | Reason |
|---:|---|---|---|---|---|
| 10021 | X-Content-Type-Options Header Missing | Low | `GET /health`, `x-content-type-options` | FIX | Added global middleware setting `X-Content-Type-Options: nosniff`. The after scan reports this rule as PASS. |
| 90004 | Cross-Origin-Resource-Policy Header Missing or Invalid | Low | `GET /health`, `Cross-Origin-Resource-Policy` | FIX | Added `Cross-Origin-Resource-Policy: same-origin` in the same global middleware. The after scan reports this rule as PASS. |
| 10049 | Storable and Cacheable Content | Informational | `/`, `/health`, `/robots.txt` before scan | FIX | Added `Cache-Control: no-store`. This removed the storable-content warning. |
| 10049 | Non-Storable Content | Informational | `/`, `/health`, `/sitemap.xml` after scan | ACCEPT | QuickNotes is a small API and may return note data on other routes, so the conservative no-store default is acceptable. The performance cost is negligible for this lab app. Re-evaluate by 2026-12-02. |

The affected URL column lists the exact URLs reported in the ZAP JSON, not the full route surface. The middleware is applied at `Server.Handler()`, so the fix covers all QuickNotes routes, including routes that ZAP did not crawl from the `/health` seed.

### Code fix

The fix is implemented in `app/security_headers.go`, applied from `app/handlers.go`, and guarded by `TestSecurityHeaders_AppliedToRoutes` in `app/handlers_test.go`.

```go
func (s *Server) Handler() http.Handler {
	return securityHeaders(s.Routes())
}
```

Headers added by the middleware:

```text
Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: no-referrer
Cache-Control: no-store
Cross-Origin-Resource-Policy: same-origin
```

### Before/after ZAP evidence

Before:

```text
WARN-NEW: X-Content-Type-Options Header Missing [10021] x 1
WARN-NEW: Storable and Cacheable Content [10049] x 3
WARN-NEW: Cross-Origin-Resource-Policy Header Missing or Invalid [90004] x 1
```

After:

```text
PASS: X-Content-Type-Options Header Missing [10021]
PASS: Insufficient Site Isolation Against Spectre Vulnerability [90004]
WARN-NEW: Non-Storable Content [10049] x 3
```

Full reports:

- `security/zap/before/zap-baseline-before.html`
- `security/zap/before/zap-baseline-before.json`
- `security/zap/after/zap-baseline-after.html`
- `security/zap/after/zap-baseline-after.json`

### Design questions e-g

**e) Why middleware.** Security headers are a cross-cutting control. Middleware applies them consistently to every route, including future routes, and gives us one tested place to maintain the policy. Per-handler headers are easy to forget and hard to audit.

**f) What strict CSP breaks.** `default-src 'none'` blocks scripts, styles, images, fonts, fetches, frames, and most browser-loaded resources unless explicitly allowed. That would break a normal website or Swagger UI unless each asset source is allowlisted. QuickNotes is a JSON/text API, so it does not need browser-loaded frontend assets and can use this strict policy.

**g) Cost of accepting everything.** Marking informational findings as accepted without reading them trains the team to ignore scanner output. It also hides weak signals that may become important in combination, such as cache policy, leaked headers, or unexpected exposed routes.

## Bonus - govulncheck CI gate

### Workflow job

The new job is in `.github/workflows/ci.yml`:

```yaml
govulncheck:
  name: govulncheck
  runs-on: ubuntu-24.04
  timeout-minutes: 5
  steps:
    - name: Check out repository
      uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      with:
        persist-credentials: false
    - name: Set up Go
      uses: actions/setup-go@d35c59abb061a4a6fb18e82ac0862c26744d6ab5 # v5.5.0
      with:
        go-version: "1.25.11"
        cache: true
        cache-dependency-path: app/go.mod
    - name: Install govulncheck
      working-directory: app
      run: go install golang.org/x/vuln/cmd/govulncheck@v1.1.4
    - name: Run govulncheck
      working-directory: app
      run: govulncheck ./...
```

I intentionally moved the CI toolchain to `1.25.11` because the original Go `1.24.13` runtime is now vulnerable and causes `govulncheck` to fail on reachable standard-library paths. Keeping `1.24` would make the PR gate permanently red.

This is a deliberate security update beyond the original lab text, which mentioned Go `1.24`. The course requirement was written before these 2026 standard-library vulnerabilities were present in the vulnerability database. In the current date/context, using fixed Go `1.25.11` is the safer DevSecOps decision and keeps the PR gate meaningful.

### Red/green evidence

Red pre-fix gate evidence:

```text
security/govulncheck/govulncheck-red-go124.txt

Your code is affected by 8 vulnerabilities from the Go standard library.
Found in: net/textproto@go1.24.13
Fixed in: net/textproto@go1.25.11
```

This red evidence demonstrates the gate catching a real reachable vulnerable runtime before the Go toolchain fix. It is not the optional "temporarily add a known-vulnerable dependency, push, observe red, revert" CI exercise. To claim the full bonus exactly as written, I would still push a short-lived commit that adds a known vulnerable dependency or runtime pin, capture the red GitHub Actions job, then revert and capture the green job.

Green final gate evidence:

```text
security/govulncheck/govulncheck-green.txt

No vulnerabilities found.
```

### Design questions h-j

**h) Reachability.** A module-level CVE says a vulnerable version is present somewhere in the dependency graph. Reachability asks whether our program can actually call the vulnerable function. That reduces triage noise: reachable vulnerabilities should be prioritized, while unreachable ones can often be watched or scheduled with less urgency.

**i) Why pin the scanner.** Pinning `govulncheck` makes CI reproducible. `@latest` can change behavior or output between runs, which makes a PR gate flaky and hard to debug. Scanner updates should be intentional, reviewed changes.

**j) What govulncheck misses.** `govulncheck` only analyzes Go code reachability. It will not catch vulnerabilities in the container base image, OS packages, Docker/Compose misconfiguration, leaked secrets, or web security issues like missing HTTP headers. Trivy and ZAP cover those different layers.

## Verification

All checks were run in Docker with the pinned Go `1.25.11` toolchain:

```bash
go test ./...
go test -race -count=1 ./...
go vet ./...
go install golang.org/x/vuln/cmd/govulncheck@v1.1.4
govulncheck ./...
golangci-lint run
docker compose build quicknotes
```

Results:

```text
go test ./...                         ok
go test -race -count=1 ./...          ok
go vet ./...                          ok
govulncheck ./...                     No vulnerabilities found.
golangci-lint run                     0 issues.
docker compose build quicknotes        built quicknotes:lab6
```
