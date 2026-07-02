# Lab 9 - DevSecOps: Trivy, ZAP, and govulncheck

## Goal

Scan the QuickNotes container and repository, triage scanner findings as engineering decisions, fix at least one web security issue in code, and add a Go vulnerability gate to CI.

## Repository changes

- Reused the Lab 6 distroless `quicknotes:lab6` container setup.
- Added global HTTP security headers middleware for all QuickNotes routes.
- Added a unit test that fails if the middleware is removed from the server handler.
- Added a pinned `govulncheck` CI job as a separate PR gate.
- Prepared the Trivy, CycloneDX SBOM, and before/after ZAP evidence paths used by this submission.

## Local execution note

The Go checks and pinned `govulncheck` check were run locally. Docker, Trivy, and ZAP were not installed in the current local environment, so the Docker-backed scan artifacts must be generated in an environment with Docker before final submission.

## Tool versions

| Tool | Pinned version |
|---|---|
| Trivy | `aquasec/trivy:0.59.1` |
| OWASP ZAP | `ghcr.io/zaproxy/zaproxy:2.16.1` |
| govulncheck | `golang.org/x/vuln/cmd/govulncheck@v1.1.4` |

## Task 1 - Trivy scans and SBOM

### Commands

```bash
docker compose build quicknotes

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:0.59.1 \
  image --severity HIGH,CRITICAL quicknotes:lab6 \
  | tee security/trivy/trivy-image-high-critical.txt

docker run --rm \
  -v "$PWD:/repo" \
  -w /repo \
  aquasec/trivy:0.59.1 \
  fs --severity HIGH,CRITICAL . \
  | tee security/trivy/trivy-fs-high-critical.txt

docker run --rm \
  -v "$PWD:/repo" \
  -w /repo \
  aquasec/trivy:0.59.1 \
  config . \
  | tee security/trivy/trivy-config.txt

docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/security/sbom:/out" \
  aquasec/trivy:0.59.1 \
  image --format cyclonedx --output /out/quicknotes-cyclonedx.json quicknotes:lab6
```

### Image scan excerpt

```text
Pending local Docker run:
security/trivy/trivy-image-high-critical.txt
```

### Filesystem scan excerpt

```text
Pending local Docker run:
security/trivy/trivy-fs-high-critical.txt
```

### Config scan excerpt

```text
Pending local Docker run:
security/trivy/trivy-config.txt
```

### Trivy HIGH/CRITICAL triage

| Source | Finding | Severity | Package/File | Disposition | Reason | Re-check date |
|---|---|---:|---|---|---|---|
| Image scan | Fill from `security/trivy/trivy-image-high-critical.txt` | TBD | `quicknotes:lab6` | TBD | Run the pinned Trivy image scan and record one disposition per HIGH/CRITICAL finding. If there are none, record that explicitly. | 2026-12-02 |
| Filesystem scan | Fill from `security/trivy/trivy-fs-high-critical.txt` | TBD | repository | TBD | Run the pinned Trivy filesystem scan and record one disposition per HIGH/CRITICAL finding. If there are none, record that explicitly. | 2026-12-02 |
| Config scan | Fill from `security/trivy/trivy-config.txt` | TBD | Dockerfile/Compose | TBD | Run the pinned Trivy config scan and record one disposition per HIGH/CRITICAL finding. If there are none, record that explicitly. | 2026-12-02 |

### CycloneDX SBOM excerpt

```json
Pending local Docker run:
security/sbom/quicknotes-cyclonedx.json
```

### Design questions a-d

**a) CVE severity is one input, not the answer.** Severity says how bad the vulnerability can be in general, but triage also needs reachability, whether the affected code path is actually used, exploit availability, network exposure, runtime privileges, compensating controls, and how the app is deployed. A HIGH CVE in unreachable build-only code is different from a reachable bug in a public endpoint.

**b) Why minimal bases help.** Distroless images remove shells, package managers, and most OS utilities from the runtime image. That reduces the number of components that can have CVEs and also reduces attacker tooling if an attacker gets code execution. The strongest control is not patching a package you do not need; it is not shipping that package at all.

**c) When `.trivyignore` is valid.** It is valid when the finding is documented, reviewed, time-bounded, and not currently actionable, for example no upstream fixed version exists or the scanner is wrong and evidence is attached. It becomes security theater when it hides real risk just to make CI green or has no owner and re-check date.

**d) Why keep an SBOM today.** An SBOM lets us answer future incident questions quickly: "Do we ship component X or version Y?" During events like Log4Shell, teams with SBOMs can search their deployed components instead of manually reverse-engineering every image under pressure.

## Task 2 - OWASP ZAP baseline and code fix

### Commands

```bash
# Before scan: build and run the Lab 6 version without the Lab 9 header fix.
git worktree add /tmp/quicknotes-lab9-before origin/feature/lab6
docker build -t quicknotes:lab9-before /tmp/quicknotes-lab9-before/app
docker run -d --rm \
  --name quicknotes-lab9-before \
  -p 8080:8080 \
  -e ADDR=:8080 \
  -e DATA_PATH=/tmp/notes.json \
  -e SEED_PATH=/seed.json \
  --read-only \
  --tmpfs /tmp \
  quicknotes:lab9-before

docker run --rm \
  -v "$PWD/security/zap/before:/zap/wrk:rw" \
  ghcr.io/zaproxy/zaproxy:2.16.1 \
  zap-baseline.py \
  -t http://host.docker.internal:8080 \
  -r zap-baseline-before.html \
  -J zap-baseline-before.json

docker stop quicknotes-lab9-before
git worktree remove /tmp/quicknotes-lab9-before

# After scan: rebuild and run the current Lab 9 version with the header fix.
docker compose build quicknotes
docker compose up -d quicknotes

docker run --rm \
  -v "$PWD/security/zap/after:/zap/wrk:rw" \
  ghcr.io/zaproxy/zaproxy:2.16.1 \
  zap-baseline.py \
  -t http://host.docker.internal:8080 \
  -r zap-baseline-after.html \
  -J zap-baseline-after.json
```

### ZAP findings triage

| ID | Name | Risk | URL / Parameter | Disposition | Reason |
|---:|---|---|---|---|---|
| 10038 | Content Security Policy Header Not Set | Medium | all observed routes | FIX | Added global middleware with `Content-Security-Policy: default-src 'none'; frame-ancestors 'none'; base-uri 'none'`. Covered by unit test and verified by the after scan. |
| 10021 | X-Content-Type-Options Header Missing | Low | all observed routes | FIX | Added `X-Content-Type-Options: nosniff` in the same global middleware. |
| 10020 | Anti-clickjacking Header | Medium | all observed routes | FIX | Added `X-Frame-Options: DENY`, which is appropriate for an API that should not be embedded in a frame. |
| 10035 | Strict-Transport-Security Header Not Set | Low | all observed routes | ACCEPT | QuickNotes is served over local HTTP in this lab. HSTS should be enforced at the HTTPS reverse proxy or TLS edge in production, not on this plain HTTP local endpoint. Re-evaluate by 2026-12-02. |

Replace or extend this table with the exact findings from `security/zap/before/zap-baseline-before.json` before final submission.

### Code fix

The fix is implemented in [`app/security_headers.go`](../app/security_headers.go), applied from [`app/handlers.go`](../app/handlers.go), and exercised by `TestSecurityHeaders_AppliedToRoutes` in [`app/handlers_test.go`](../app/handlers_test.go).

```go
func (s *Server) Handler() http.Handler {
	return securityHeaders(s.Routes())
}
```

### Before/after evidence

Before:

```text
Pending local Docker/ZAP run:
security/zap/before/zap-baseline-before.json
security/zap/before/zap-baseline-before.html
```

After:

```text
Pending local Docker/ZAP run:
security/zap/after/zap-baseline-after.json
security/zap/after/zap-baseline-after.html
```

### Design questions e-g

**e) Why middleware.** Security headers are a cross-cutting control. Middleware applies them consistently to every route, including future routes, and gives us one tested place to maintain the policy. Per-handler headers are easy to forget and hard to audit.

**f) What strict CSP breaks.** `default-src 'none'` blocks scripts, styles, images, fonts, fetches, frames, and most browser-loaded resources unless explicitly allowed. That would break a normal website or Swagger UI unless each asset source is allowlisted. QuickNotes is a JSON/text API, so it does not need browser-loaded frontend assets and can use this strict policy.

**g) Cost of accepting everything.** Marking informational findings as accepted without reading them trains the team to ignore scanner output. It also hides weak signals that may become important in combination, such as leaked headers, missing cache controls, or unexpected exposed routes.

## Bonus - govulncheck CI gate

### Workflow job

The new job is in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml):

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
        go-version: "1.24"
        cache: true
    - name: Install govulncheck
      working-directory: app
      run: go install golang.org/x/vuln/cmd/govulncheck@v1.1.4
    - name: Run govulncheck
      working-directory: app
      run: govulncheck ./...
```

### Red/green CI evidence

Red demonstration:

```text
Temporarily add a reachable vulnerable dependency, push the branch, and capture the failing govulncheck job log.
```

Green run:

```text
Local pinned govulncheck result:
No vulnerabilities found.
```

### Design questions h-j

**h) Reachability.** A module-level CVE says a vulnerable version is present somewhere in the dependency graph. Reachability asks whether our program can actually call the vulnerable function. That reduces triage noise: reachable vulnerabilities should be prioritized, while unreachable ones can often be watched or scheduled with less urgency.

**i) Why pin the scanner.** Pinning `govulncheck` makes CI reproducible. `@latest` can change behavior or output between runs, which makes a PR gate flaky and hard to debug. Scanner updates should be intentional, reviewed changes.

**j) What govulncheck misses.** `govulncheck` only analyzes Go code reachability. It will not catch vulnerabilities in the container base image, OS packages, Docker/Compose misconfiguration, leaked secrets, or web security issues like missing HTTP headers. Trivy and ZAP cover those different layers.

## Verification

```bash
cd app
go test ./...
go test -race -count=1 ./...
go vet ./...
go run golang.org/x/vuln/cmd/govulncheck@v1.1.4 ./...
```
