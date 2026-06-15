# Lab 4 — OS & Networking: Trace, Debug, and Read the Substrate

## Environment

- OS: macOS Darwin 25.2.0 arm64
- App: QuickNotes
- App address: `localhost:8080`
- Branch: `feature/lab4`
- Note: the lab handout uses Linux commands (`ss`, `ip route`, `mtr`, `journalctl`, `iptables`). This run was performed on macOS, so I used the closest macOS equivalents where the Linux tools were not available.

---

# Task 1 — Trace a Request End-to-End

## 1.1 Start QuickNotes and capture traffic

### Command: start QuickNotes

```bash
cd app/
DATA_PATH=/tmp/qn-lab4-notes.json SEED_PATH=seed.json ADDR=:8080 go run .
```

### Output

```text
2026/06/15 16:29:06 quicknotes listening on :8080 (notes loaded: 4)
```

### Command: send request

```bash
curl -v -X POST http://localhost:8080/notes \
  -H 'Content-Type: application/json' \
  -d '{"title":"trace me","body":"in flight"}'
```

### Output

```text
Note: Unnecessary use of -X or --request, POST is already inferred.
* Host localhost:8080 was resolved.
* IPv6: ::1
* IPv4: 127.0.0.1
*   Trying [::1]:8080...
* Connected to localhost (::1) port 8080
> POST /notes HTTP/1.1
> Host: localhost:8080
> User-Agent: curl/8.7.1
> Accept: */*
> Content-Type: application/json
> Content-Length: 39
>
} [39 bytes data]
* upload completely sent off: 39 bytes
< HTTP/1.1 201 Created
< Content-Type: application/json
< Date: Mon, 15 Jun 2026 14:19:08 GMT
< Content-Length: 90
<
{ [90 bytes data]
* Connection #0 to host localhost left intact
{"id":6,"title":"trace me","body":"in flight","created_at":"2026-06-15T14:19:08.898818Z"}
```

### Command: start tcpdump

```bash
sudo tcpdump -i lo0 -nn -s 0 -A 'tcp port 8080' -w lab4-trace.pcap
```

### Output

```text
tcpdump: listening on lo0, link-type NULL (BSD loopback), snapshot length 524288 bytes
```

### Command: decode capture

```bash
sudo tcpdump -r lab4-trace.pcap -nn -A | tee lab4-trace.txt
```

### Output

```text
reading from file lab4-trace.pcap, link-type NULL (BSD loopback), snapshot length 524288
```

### Decision

On macOS, packet capture on the loopback interface uses `lo0` instead of Linux `lo`. The capture was successfully saved to `lab4-trace.pcap` and decoded into `lab4-trace.txt`.

---

## 1.2 Annotated packet capture

### TCP three-way handshake

```text
17:19:08.898356 IP6 ::1.57734 > ::1.8080: Flags [S], seq 2628599922, win 65535, options [mss 16324,nop,wscale 6,nop,nop,TS val 2283602634 ecr 0,sackOK,eol], length 0
17:19:08.898486 IP6 ::1.8080 > ::1.57734: Flags [S.], seq 276034654, ack 2628599923, win 65535, options [mss 16324,nop,wscale 6,nop,nop,TS val 3423950743 ecr 2283602634,sackOK,eol], length 0
17:19:08.898515 IP6 ::1.57734 > ::1.8080: Flags [.], ack 1, win 6372, options [nop,nop,TS val 2283602635 ecr 3423950743], length 0
```

**Decision:** The client opened a TCP connection from `::1:57734` to QuickNotes on `::1:8080`. The server replied with SYN/ACK and the client ACKed it, so L3/L4 connectivity on loopback works.

### HTTP request

```text
POST /notes HTTP/1.1
Host: localhost:8080
User-Agent: curl/8.7.1
Accept: */*
Content-Type: application/json
Content-Length: 39

{"title":"trace me","body":"in flight"}
```

**Decision:** QuickNotes received an HTTP `POST /notes` request with the expected JSON body.

### HTTP response

```text
HTTP/1.1 201 Created
Content-Type: application/json
Date: Mon, 15 Jun 2026 14:19:08 GMT
Content-Length: 90

{"id":6,"title":"trace me","body":"in flight","created_at":"2026-06-15T14:19:08.898818Z"}
```

**Decision:** QuickNotes created the note and returned `201 Created`, so the request reached the application layer and was processed successfully.

### Connection close

```text
17:19:08.899538 IP6 ::1.57734 > ::1.8080: Flags [F.], seq 175, ack 204, win 6369, options [nop,nop,TS val 2283602636 ecr 3423950744], length 0
17:19:08.899574 IP6 ::1.8080 > ::1.57734: Flags [.], ack 176, win 6370, options [nop,nop,TS val 3423950744 ecr 2283602636], length 0
17:19:08.899602 IP6 ::1.8080 > ::1.57734: Flags [F.], seq 204, ack 176, win 6370, options [nop,nop,TS val 3423950744 ecr 2283602636], length 0
17:19:08.899672 IP6 ::1.57734 > ::1.8080: Flags [.], ack 205, win 6369, options [nop,nop,TS val 2283602636 ecr 3423950744], length 0
```

**Decision:** The connection closed gracefully with FIN packets from the client and server. There is no reset in this trace.

---

## 1.3 Debugging commands

### 1. What is listening?

Original Linux command:

```bash
ss -tlnp | grep :8080
```

macOS command used:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

Output:

```text
COMMAND     PID          USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
quicknote 24867 dankhasanshin    5u  IPv6 0xd7ac20fca3fbab31      0t0  TCP *:8080 (LISTEN)
```

**Decision:** QuickNotes is listening on TCP port `8080`, so the local service bind is successful.

### 2. Routes from host

Original Linux command:

```bash
ip route show
```

macOS command used:

```bash
route -n get localhost
```

Output:

```text
   route to: 127.0.0.1
destination: 127.0.0.1
  interface: lo0
      flags: <UP,HOST,DONE,LOCAL>
 recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
   49152     49152         0         3         4         0     16384         0
```

**Decision:** Traffic to `localhost` stays on the local loopback interface `lo0`; no external gateway is needed.

### 3. Reachability to localhost

Original Linux command:

```bash
mtr -rwc 5 localhost
```

Output:

```text
mtr not found
```

Fallback command used:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/health
```

Output:

```text
200
```

Additional ICMP check:

```bash
ping -c 5 localhost
```

Output:

```text
PING localhost (127.0.0.1): 56 data bytes
Request timeout for icmp_seq 0
Request timeout for icmp_seq 1
Request timeout for icmp_seq 2
Request timeout for icmp_seq 3

--- localhost ping statistics ---
5 packets transmitted, 0 packets received, 100.0% packet loss
```

**Decision:** ICMP echo did not receive replies in this macOS environment, but the service itself is reachable over TCP/HTTP and returns `200` from `/health`. For this lab's application path, TCP/HTTP reachability is the relevant signal.

### 4. DNS check

Command:

```bash
dig +short example.com @1.1.1.1
```

Output:

```text
8.6.112.0
8.47.69.0
```

**Decision:** DNS resolution through Cloudflare's resolver works. DNS is not required for `localhost:8080`, but external name resolution is healthy.

### 5. Logs

Original Linux command:

```bash
journalctl --user -u quicknotes -n 20 || true
```

Output:

```text
zsh:1: command not found: journalctl
```

Runtime log from the `go run .` terminal:

```text
2026/06/15 16:29:06 quicknotes listening on :8080 (notes loaded: 4)
```

**Decision:** QuickNotes was started directly with `go run .`, not as a user-level systemd service. On this macOS host, `journalctl` is unavailable, so runtime logs are checked in the terminal where the process is running.

---

## 1.4 What would I check first if QuickNotes returned 502?

If QuickNotes returned `502 Bad Gateway`, I would start outside-in at the gateway or reverse proxy, because a 502 usually means the proxy could not get a valid response from the upstream service. First I would check proxy logs for upstream connection errors, refused connections, timeouts, or malformed responses. Then I would verify that QuickNotes is running and listening on the configured port with `ss -tlnp` on Linux or `lsof -nP -iTCP:8080 -sTCP:LISTEN` on macOS. Next I would run `curl http://localhost:8080/health` from the same host where the proxy runs. If the app is reachable directly but the proxy still returns 502, I would inspect upstream host/port configuration, whether the app binds to `127.0.0.1` versus `0.0.0.0`, firewall rules, and any recent app crashes or restarts.

---

# Task 2 — Outside-In Debugging on a Broken Deploy

## 2.1 Reproduce broken instance

QuickNotes was already running on `:8080`. I started a second instance on the same address.

### Command

```bash
cd app/
DATA_PATH=/tmp/qn-lab4-broken.json SEED_PATH=seed.json ADDR=:8080 go run . 2>&1 | tee /tmp/qn-broken.log
```

### Output

```text
2026/06/15 16:30:39 quicknotes listening on :8080 (notes loaded: 4)
2026/06/15 16:30:39 listen: listen tcp :8080: bind: address already in use
exit status 1
```

### Decision

The second QuickNotes instance failed because port `8080` was already occupied by the first instance.

Root cause:

```text
bind: address already in use
```

---

## 2.2 Outside-in debugging chain

### Step 1 — Is the process running?

Original command:

```bash
ps -ef | grep quicknotes
```

macOS command used:

```bash
ps -ef | grep quicknote | grep -v grep
```

Output:

```text
  501 24867 24862   0  4:29PM ttys005    0:00.01 /Users/dankhasanshin/Library/Caches/go-build/5e/5e6cee83cfe5e2dde6761bdc2211e54c44a6b33572cad49b571abff8ab437641-d/quicknotes
```

**Decision:** One QuickNotes process is running. The second instance failed to start.

### Step 2 — Is anything listening on port 8080?

Original Linux command:

```bash
ss -tlnp | grep 8080
```

macOS command used:

```bash
lsof -nP -iTCP:8080 -sTCP:LISTEN
```

Output:

```text
COMMAND     PID          USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
quicknote 24867 dankhasanshin    5u  IPv6 0xd7ac20fca3fbab31      0t0  TCP *:8080 (LISTEN)
```

**Decision:** Port `8080` is already occupied by the first QuickNotes process. This explains why the second instance cannot bind to the same address.

### Step 3 — Is the service reachable from host?

Command:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/health
```

Output:

```text
200
```

**Decision:** The first instance is reachable from the host. The problem is not network reachability; the problem is that the second deployment cannot start because of a port conflict.

### Step 4 — Is firewall blocking traffic?

Original Linux command:

```bash
sudo iptables -L -n -v 2>/dev/null || sudo nft list ruleset 2>/dev/null || true
```

macOS command attempted:

```bash
pfctl -s info
```

Output:

```text
pfctl: /dev/pf: Permission denied
```

**Decision:** I could not inspect Packet Filter rules without elevated privileges. However, firewall blocking is unlikely to be the root cause because `curl http://localhost:8080/health` returned `200`; the service is reachable locally.

### Step 5 — DNS

Command:

```bash
dig +short localhost
```

Output:

```text
127.0.0.1
```

**Decision:** `localhost` resolves correctly. DNS is not the cause of the failure.

---

## 2.3 Repair and re-verify

### Commands

```bash
kill 24867
DATA_PATH=/tmp/qn-lab4-repair.json SEED_PATH=seed.json ADDR=:8080 go run .
curl -s http://localhost:8080/health
```

### Output

```text
2026/06/15 16:31:23 quicknotes listening on :8080 (notes loaded: 4)
{"notes":4,"status":"ok"}
```

### Decision

After killing the conflicting process and starting QuickNotes again, the health endpoint responds successfully. The repair confirms that the root cause was the port conflict.

---

## 2.4 Root cause

The broken deployment was caused by two QuickNotes instances trying to bind to the same address, `:8080`. The first instance already owned the port, so the second instance failed with:

```text
listen tcp :8080: bind: address already in use
```

---

## 2.5 Mini-postmortem

This failure was caused by a port ownership conflict, not by a bad request handler or a DNS issue. Systemically, this can happen when a deploy starts a new process before the old process has stopped, or when multiple services share a static port without ownership checks. The outside-in chain separated symptoms from cause: one QuickNotes process was running, port `8080` was already listening, `/health` returned `200`, and DNS resolved correctly. To prevent this class of failure, deployments should run under a supervisor such as systemd or launchd, use explicit stop/start or zero-downtime handoff logic, and include smoke tests that verify both bind success and `/health` after every deploy.

---

# Artifacts

- `submissions/lab4.md`
- `lab4-trace.pcap`
- `lab4-trace.txt`
- `/tmp/qn-broken.log`
