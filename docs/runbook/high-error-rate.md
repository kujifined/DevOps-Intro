# Runbook: QuickNotes High Error Rate

## What this alert means

More than 5% of QuickNotes HTTP responses have been 4xx or 5xx for at least 5 minutes, so users may be unable to create, read, or manage notes reliably.

## Triage steps

1. Open the Grafana `QuickNotes Golden Signals` dashboard at `http://localhost:3000` and confirm whether the error ratio is still above 5%, then check whether traffic or stored notes changed at the same time.
2. Check Prometheus target health at `http://localhost:9090/targets` and confirm that the `quicknotes` target is `UP`; if it is down, investigate scraping or container networking before assuming application errors.
3. Inspect recent QuickNotes logs:

   ```bash
   docker compose logs --tail=200 quicknotes
   ```

   Look for repeated bad requests, JSON parsing errors, file persistence errors, restarts, or panics.
4. Reproduce one read path and one write path manually:

   ```bash
   curl -v http://localhost:8080/health
   curl -v http://localhost:8080/notes
   curl -v -X POST http://localhost:8080/notes \
     -H 'Content-Type: application/json' \
     -d '{"title":"runbook test","body":"manual write check"}'
   ```

5. If errors are mostly `400`, identify whether malformed client traffic is causing the alert. If errors are `500` or the container is restarting, inspect storage configuration, mounted volume permissions, and recent deployment changes.

## Mitigations

1. If QuickNotes is unhealthy or wedged, restart only the application service:

   ```bash
   docker compose restart quicknotes
   ```

2. If the latest image or configuration change caused the spike, roll back to the last known good image/configuration and restart the stack.
3. If malformed traffic is driving the error ratio and the source is identifiable, temporarily block or rate-limit the offending client while preserving evidence for follow-up.
4. If persistence is failing, verify the `quicknotes-data` volume and permissions before deleting or recreating any data.

## Post-incident

After the service is stable, write a blameless postmortem using the Lecture 1 guidance in [`lectures/lec1.md`](../../lectures/lec1.md). Include timeline, user impact, detection path, root cause, mitigation, and follow-up actions. Update this runbook if any triage step was missing, slow, or misleading.
