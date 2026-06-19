# Lab 5 — Virtualization: QuickNotes in a Vagrant VM

## Task 1 — Vagrant Up and Run QuickNotes

The implementation is in the repository-root [`Vagrantfile`](../Vagrantfile). It uses the public `bento/ubuntu-24.04` Ubuntu LTS box, installs Go 1.24.5 during provisioning, builds QuickNotes, and manages it as a `systemd` service.

### Verification evidence

The measurements below were captured on an Apple Silicon (`arm64`) host with Vagrant 2.4.9, VirtualBox 7.2.10, and Docker 29.2.1.

```bash
vagrant up 2>&1 | tee vagrant-up.log
head -n 10 vagrant-up.log
```

```text
Bringing machine 'default' up with 'virtualbox' provider...
==> default: Importing base box 'bento/ubuntu-24.04'...
==> default: Matching MAC address for NAT networking...
==> default: Checking if box 'bento/ubuntu-24.04' version '202510.26.0' is up to date...
==> default: Setting the name of the VM: quicknotes-lab5
==> default: Clearing any previously set network interfaces...
==> default: Preparing network interfaces based on configuration...
    default: Adapter 1: nat
==> default: Forwarding ports...
    default: 8080 (guest) => 18080 (host) (adapter 1)
```

```bash
vagrant ssh -c 'go version'
```

```text
go version go1.24.5 linux/arm64
```

```bash
vagrant ssh -c 'systemctl is-active quicknotes.service'
```

```text
active
```

Inside the VM:

```bash
vagrant ssh -c 'curl --fail --silent http://127.0.0.1:8080/health'
```

```json
{"notes":4,"status":"ok"}
```

From the host through the forwarded port:

```bash
curl --fail --silent http://127.0.0.1:18080/health
```

```json
{"notes":4,"status":"ok"}
```

### Design decisions

#### a) Synced folders

I used the `virtualbox` synced-folder provider to mount host `./app` at `/home/vagrant/quicknotes/app` in the guest. It provides two-way, immediately visible changes and requires no separate synchronization command, which is convenient for development. Its trade-offs are dependence on VirtualBox Guest Additions and typically slower metadata and small-file I/O than a native guest filesystem. `rsync` can be faster and more predictable, but host changes are one-way and require `vagrant rsync` or `vagrant rsync-auto`.

#### b) NAT, bridged, and host-only networking

The VM uses Vagrant's default NAT adapter plus a forwarded TCP port. Host `127.0.0.1:18080` maps to guest port `8080`. Binding the host side to loopback means only processes on this host can reach QuickNotes. A bridged adapter would place the VM directly on the local network, making the development service reachable by other machines and increasing unnecessary exposure.

#### c) Provisioning

I used the shell provisioner because this setup is short and self-contained: install a pinned toolchain, build one application, and define one service. It keeps a clean-clone setup reviewable in the `Vagrantfile` without introducing another configuration-management dependency. For a larger fleet, Ansible would provide clearer roles, inventory, reusable handlers, and cross-host state management; that is more appropriate for Lab 7.

#### d) Pinning Go 1.24.5

Pinning the complete version makes builds repeatable and keeps grader and student environments aligned. A moving `1.24` reference could resolve to different patch releases over time, changing compiler behavior, bug fixes, security fixes, or diagnostic output. The provisioner also selects the matching Linux tarball for either `amd64` or `arm64` guests, so the point release stays fixed across host architectures.

## Task 2 — Snapshot: Save, Break, Restore

The deliberate failure moves the Go installation rather than deleting it. This proves that Go is unavailable while avoiding an irreversible command before the snapshot has been verified.

```bash
vagrant snapshot save quicknotes-clean
vagrant snapshot list
vagrant ssh -c 'sudo mv /usr/local/go /usr/local/go.broken'
vagrant ssh -c 'go version'
```

```text
==> default: Snapshotting the machine as 'quicknotes-clean'...
==> default: Snapshot saved! You can restore the snapshot at any time by
==> default: using `vagrant snapshot restore`. You can delete it using
==> default: `vagrant snapshot delete`.

quicknotes-clean
bash: line 1: go: command not found
```

Restore and time the operation:

```bash
time vagrant snapshot restore quicknotes-clean
vagrant ssh -c 'go version'
vagrant ssh -c 'curl --fail --silent http://127.0.0.1:8080/health'
curl --fail --silent http://127.0.0.1:18080/health
```

```text
==> default: Forcing shutdown of VM...
==> default: Restoring the snapshot 'quicknotes-clean'...
==> default: Resuming suspended VM...
==> default: Booting VM...
==> default: Machine booted and ready!
real 13.20
user 1.36
sys 0.88
go version go1.24.5 linux/arm64
{"notes":4,"status":"ok"}
{"notes":4,"status":"ok"}
```

### Snapshot design questions

#### e) Why snapshots are not backups

A snapshot normally depends on the original virtual disk and its snapshot chain on the same host storage. Host disk failure, deletion of the VM directory, or corruption of the base disk can destroy both the VM and its snapshots. A backup is an independent copy stored in a separate failure domain and tested for restoration.

#### f) Copy-on-write disk use

Creating a snapshot does not immediately copy the complete virtual disk. VirtualBox preserves the prior state and writes subsequent changed blocks to a differencing image. Ten snapshots therefore do not inherently consume ten full-disk copies, but each layer grows with changed blocks, and repeated rewrites can be represented in multiple layers.

#### g) When snapshotting is an antipattern

Snapshots are an antipattern when they become long-lived backups, deployment artifacts, or a substitute for reproducible provisioning. Long chains consume storage, increase dependency on intermediate differencing disks, complicate state tracking, and can make consolidation or recovery slower and more fragile. Disposable systems should normally be rebuilt from version-controlled configuration; snapshots are best kept short-lived for controlled rollback points.

## Bonus — VM vs Container Resource Baseline

Measurements must come from the same host and session. The Docker daemon and the VM should otherwise be idle.

### Commands

```bash
vagrant halt
time vagrant up --no-provision
vagrant ssh -c 'free -h'
vagrant ssh -c 'ps -A --no-headers | wc -l'
VBoxManage showvminfo quicknotes-lab5 | grep -i 'Config file'
du -sh "$HOME/VirtualBox VMs/quicknotes-lab5"
```

```bash
docker run -d --name quicknotes-docker-lab5 \
  -p 28080:8080 -e DATA_PATH=/tmp/notes.json \
  -v "$PWD/app:/src:ro" -w /src golang:1.24 \
  sh -c 'go build -o /tmp/qn && /tmp/qn'
curl --fail --silent http://127.0.0.1:28080/health
docker stop quicknotes-docker-lab5
time docker start quicknotes-docker-lab5
docker stats --no-stream quicknotes-docker-lab5
docker top quicknotes-docker-lab5
docker image inspect golang:1.24 --format '{{.Size}} bytes'
```

### Raw measurement output

```text
# VM cold start
real 21.19
user 1.93
sys 1.41

# VM memory
               total        used        free      shared  buff/cache   available
Mem:           824Mi       237Mi       433Mi       4.8Mi       234Mi       586Mi
Swap:          3.7Gi          0B       3.7Gi

# VM process count and directory size
106
3.6G    /Users/kuji/VirtualBox VMs/quicknotes-lab5

# Container health and cold start
{"notes":4,"status":"ok"}
real 0.13
user 0.00
sys 0.00

# Container memory
7.961MiB / 7.653GiB | 0.10%

# docker top (two process rows)
root  2401  2378  0  10:12  ?  00:00:00  sh -c go build -o /tmp/qn && /tmp/qn
root  2500  2401  0  10:12  ?  00:00:00  /tmp/qn

# golang:1.24 image size
315934193 bytes
```

### Results

| Dimension | Vagrant VM | Docker container |
|---|---:|---:|
| Cold start | 21.19 s | 0.13 s |
| Idle RAM | 237 MiB used | 7.961 MiB |
| On-disk size | 3.6 GiB | 315,934,193 B (301 MiB) |
| Process count | 106 | 2 |

### Analysis

The size of the difference was more striking than the direction: the VM took about 163 times longer to start and used about 30 times more idle memory than the container. The VM also ran 106 processes because it includes a complete guest operating system, while the container had only its shell and QuickNotes process. A VM remains appropriate when a workload needs a separate kernel, a different operating system, stronger isolation boundaries, or full-machine lifecycle testing. Containers are a better fit for stateless services such as QuickNotes because their low startup and memory overhead allows substantially higher workload density and faster replacement. These measurements help explain container adoption for microservices, but containers are not equivalent to VM isolation because they share the host kernel.

## Cleanup after evidence is recorded

```bash
vagrant snapshot delete quicknotes-clean
docker rm -f quicknotes-docker-lab5
```
