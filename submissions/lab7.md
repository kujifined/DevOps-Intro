# Lab 7 — Configuration Management: QuickNotes via Ansible

## Environment

- Repository: `https://github.com/kujifined/DevOps-Intro`
- Target VM: Lab 5 Vagrant VM from `feature/lab5` (`bento/ubuntu-24.04`, VM name `quicknotes-lab5`)
- Target service URL from host: `http://localhost:18080/health`
- Ansible inventory: `ansible/inventory.ini`
- Playbook: `ansible/playbook.yaml`

Before running the playbook I verified the Vagrant SSH settings with:

```bash
vagrant ssh-config
```

The inventory uses the Vagrant SSH endpoint:

```ini
[quicknotes_vms]
lab5-vm ansible_host=127.0.0.1 ansible_port=2222 ansible_user=vagrant ansible_ssh_private_key_file=.vagrant/machines/default/virtualbox/private_key ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentitiesOnly=yes -o PubkeyAcceptedKeyTypes=+ssh-rsa -o HostKeyAlgorithms=+ssh-rsa' ansible_python_interpreter=/usr/bin/python3
```

If `vagrant ssh-config` prints a different `Port`, update `ansible_port` before running.

## Static QuickNotes Binary

The required target artifact is:

```text
ansible/files/quicknotes
```

Build command for the final Lab 7 run:

```bash
mkdir -p ansible/files
cd app
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o ../ansible/files/quicknotes .
cd ..
file ansible/files/quicknotes
```

Expected `file` result:

```text
ansible/files/quicknotes: ELF 64-bit LSB executable, ARM aarch64, statically linked
```

This `GOARCH=arm64` matches the Lab 5 VM used in this repository (`go version go1.24.5 linux/arm64`). On an `amd64` VM, rebuild the same source with `GOARCH=amd64`.

## Playbook

```yaml
---
- name: Deploy QuickNotes to Lab 5 VM
  hosts: quicknotes_vms
  become: true
  gather_facts: false

  vars:
    quicknotes_user: quicknotes
    quicknotes_group: quicknotes
    quicknotes_data_dir: /var/lib/quicknotes
    quicknotes_binary_path: /usr/local/bin/quicknotes
    quicknotes_addr: ":8080"
    quicknotes_data_path: /var/lib/quicknotes/quicknotes.json
    quicknotes_seed_path: /var/lib/quicknotes/seed.json
    quicknotes_restart_sec: 3s

    ansible_pull_enabled: false
    ansible_pull_repo_url: https://github.com/kujifined/DevOps-Intro.git
    ansible_pull_branch: feature/lab7
    ansible_pull_workdir: /opt/quicknotes-ansible-pull
    ansible_pull_inventory_path: /etc/ansible/quicknotes-local.ini
    ansible_pull_limit_host: 127.0.0.1

  tasks:
    - name: Ensure QuickNotes system group exists
      ansible.builtin.group:
        name: "{{ quicknotes_group }}"
        system: true

    - name: Ensure QuickNotes system user exists
      ansible.builtin.user:
        name: "{{ quicknotes_user }}"
        group: "{{ quicknotes_group }}"
        system: true
        create_home: false
        shell: /usr/sbin/nologin

    - name: Ensure QuickNotes data directory exists
      ansible.builtin.file:
        path: "{{ quicknotes_data_dir }}"
        state: directory
        owner: "{{ quicknotes_user }}"
        group: "{{ quicknotes_group }}"
        mode: "0750"

    - name: Copy QuickNotes binary
      ansible.builtin.copy:
        src: files/quicknotes
        dest: "{{ quicknotes_binary_path }}"
        owner: root
        group: root
        mode: "0755"
      notify: Restart QuickNotes

    - name: Copy QuickNotes seed data
      ansible.builtin.copy:
        src: ../app/seed.json
        dest: "{{ quicknotes_seed_path }}"
        owner: "{{ quicknotes_user }}"
        group: "{{ quicknotes_group }}"
        mode: "0640"

    - name: Render QuickNotes systemd unit
      ansible.builtin.template:
        src: templates/quicknotes.service.j2
        dest: /etc/systemd/system/quicknotes.service
        owner: root
        group: root
        mode: "0644"
      notify:
        - Reload systemd
        - Restart QuickNotes

    - name: Flush handlers before enabling service
      ansible.builtin.meta: flush_handlers

    - name: Ensure QuickNotes service is enabled and running
      ansible.builtin.systemd_service:
        name: quicknotes.service
        enabled: true
        state: started

  handlers:
    - name: Reload systemd
      ansible.builtin.systemd_service:
        daemon_reload: true

    - name: Restart QuickNotes
      ansible.builtin.systemd_service:
        name: quicknotes.service
        state: restarted
```

The repository version also contains the optional `ansible-pull` timer tasks, guarded by `ansible_pull_enabled: false`.

## Systemd Template

```ini
[Unit]
Description=QuickNotes service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{ quicknotes_user }}
Group={{ quicknotes_group }}
WorkingDirectory={{ quicknotes_data_dir }}

Environment="ADDR={{ quicknotes_addr }}"
Environment="DATA_PATH={{ quicknotes_data_path }}"
Environment="SEED_PATH={{ quicknotes_seed_path }}"

ExecStart={{ quicknotes_binary_path }}
Restart=on-failure
RestartSec={{ quicknotes_restart_sec }}

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths={{ quicknotes_data_dir }}

[Install]
WantedBy=multi-user.target
```

## Task 1 Verification

Local syntax check:

```bash
ansible --version
ansible-playbook -i ansible/inventory.ini ansible/playbook.yaml --syntax-check
```

Result:

```text
ansible [core 2.17.14] from Ansible 10.7.0
playbook: ansible/playbook.yaml
```

Dry run:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yaml --check
```

Real run:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yaml
```

First run PLAY RECAP:

```text
PLAY [Deploy QuickNotes to Lab 5 VM] *******************************************

TASK [Ensure QuickNotes system group exists] ***********************************
changed: [lab5-vm]

TASK [Ensure QuickNotes system user exists] ************************************
changed: [lab5-vm]

TASK [Ensure QuickNotes data directory exists] *********************************
changed: [lab5-vm]

TASK [Copy QuickNotes binary] **************************************************
changed: [lab5-vm]

TASK [Copy QuickNotes seed data] ***********************************************
changed: [lab5-vm]

TASK [Render QuickNotes systemd unit] ******************************************
changed: [lab5-vm]

TASK [Flush handlers before enabling service] **********************************

RUNNING HANDLER [Reload systemd] ***********************************************
ok: [lab5-vm]

RUNNING HANDLER [Restart QuickNotes] *******************************************
changed: [lab5-vm]

TASK [Ensure QuickNotes service is enabled and running] ************************
ok: [lab5-vm]

PLAY RECAP *********************************************************************
lab5-vm                    : ok=9    changed=7    unreachable=0    failed=0    skipped=7    rescued=0    ignored=0
```

Service checks:

```bash
ansible -i ansible/inventory.ini quicknotes_vms -b -m ansible.builtin.systemd_service -a "name=quicknotes.service"
curl -s http://localhost:18080/health
```

Health output:

```json
{"notes":4,"status":"ok"}
```

The deployed systemd unit runs as the dedicated service account:

```text
active
quicknotes
quicknotes
/etc/systemd/system/quicknotes.service
```

## Task 1 Design Questions

**a) `command:` vs dedicated modules.** `command:` runs an arbitrary program and usually cannot know whether the target state already exists. Dedicated modules such as `apt`, `file`, `copy`, `template`, and `systemd_service` model desired state: package present, directory ownership/mode, file checksum, rendered template contents, service enabled/running. They are idempotent because they inspect current state before changing it. That matters because a second deploy should be safe, boring, and report `changed=0` when nothing drifted.

**b) `notify:` and handlers.** A handler is queued only when the notifying task reports `changed`. It does not fire when the task is `ok`, `skipped`, or failed before changing state. If several tasks notify the same handler, Ansible runs it once at the handler flush point. That default is correct because service restarts should happen only after actual config or binary changes, not on every playbook run.

**c) Variable hierarchy for this lab.** I would put role-like safe defaults in `defaults/main.yml` if this became a role, environment-specific values such as host/port in `group_vars/quicknotes_vms.yml`, and temporary demonstration overrides in playbook vars or `-e` extra vars. For this small lab, playbook vars keep the submission self-contained, but `group_vars` would be cleaner once there are staging/prod inventories.

**d) `gather_facts: false`.** This playbook does not need facts: paths, user, ports, and service names are explicit variables, and there is no OS branching. Turning facts off saves the SSH round trip and Python fact collection at the start of every run, which makes repeated idempotency checks faster and less noisy.

## Task 2 Verification

Second run command:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yaml
```

Second run PLAY RECAP:

```text
PLAY [Deploy QuickNotes to Lab 5 VM] *******************************************

TASK [Ensure QuickNotes system group exists] ***********************************
ok: [lab5-vm]

TASK [Ensure QuickNotes system user exists] ************************************
ok: [lab5-vm]

TASK [Ensure QuickNotes data directory exists] *********************************
ok: [lab5-vm]

TASK [Copy QuickNotes binary] **************************************************
ok: [lab5-vm]

TASK [Copy QuickNotes seed data] ***********************************************
ok: [lab5-vm]

TASK [Render QuickNotes systemd unit] ******************************************
ok: [lab5-vm]

TASK [Flush handlers before enabling service] **********************************

TASK [Ensure QuickNotes service is enabled and running] ************************
ok: [lab5-vm]

PLAY RECAP *********************************************************************
lab5-vm                    : ok=7    changed=0    unreachable=0    failed=0    skipped=7    rescued=0    ignored=0
```

Selective template change:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yaml -e quicknotes_restart_sec=5s
```

Selective run PLAY RECAP:

```text
PLAY [Deploy QuickNotes to Lab 5 VM] *******************************************

TASK [Ensure QuickNotes system group exists] ***********************************
ok: [lab5-vm]

TASK [Ensure QuickNotes system user exists] ************************************
ok: [lab5-vm]

TASK [Ensure QuickNotes data directory exists] *********************************
ok: [lab5-vm]

TASK [Copy QuickNotes binary] **************************************************
ok: [lab5-vm]

TASK [Copy QuickNotes seed data] ***********************************************
ok: [lab5-vm]

TASK [Render QuickNotes systemd unit] ******************************************
changed: [lab5-vm]

TASK [Flush handlers before enabling service] **********************************

RUNNING HANDLER [Reload systemd] ***********************************************
ok: [lab5-vm]

RUNNING HANDLER [Restart QuickNotes] *******************************************
changed: [lab5-vm]

TASK [Ensure QuickNotes service is enabled and running] ************************
ok: [lab5-vm]

PLAY RECAP *********************************************************************
lab5-vm                    : ok=9    changed=2    unreachable=0    failed=0    skipped=7    rescued=0    ignored=0
```

`--check --diff` preview:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yaml --check --diff -e quicknotes_restart_sec=7s
```

Example diff:

```diff
TASK [Render QuickNotes systemd unit] ******************************************
--- before: /etc/systemd/system/quicknotes.service
+++ after: /Users/kuji/notes/uni/sum2026/IDO/DevOps-Intro/.cache/ansible/local_tmp/ansible-local-4018ywtyyemy/tmp3_pi6fz7/quicknotes.service.j2
@@ -15,7 +15,7 @@

 ExecStart=/usr/local/bin/quicknotes
 Restart=on-failure
-RestartSec=5s
+RestartSec=7s

 NoNewPrivileges=true
 PrivateTmp=true

changed: [lab5-vm]

PLAY RECAP *********************************************************************
lab5-vm                    : ok=9    changed=2    unreachable=0    failed=0    skipped=7    rescued=0    ignored=0
```

## Task 2 Design Questions

**e) Why second run is `changed=0`.** The modules compare current state with desired state. `file` checks path existence, type, owner, group, and mode. `copy` checks the destination file metadata and content checksum. `template` renders the Jinja template locally, compares the rendered content and metadata to the remote file, and changes only if they differ. After the first successful run, those checks all match.

**f) Failure modes with `shell: 'echo ... > quicknotes.service'`.** A shell redirect usually reports changed every time, so the handler would restart QuickNotes on every deploy. Quoting multiline unit content is brittle, file owner/mode may drift, and small escaping mistakes can produce an invalid unit. It also loses Ansible's diff and checksum behavior, making reviews and dry runs much weaker.

**g) What `--check --diff` catches that plain `--check` misses.** Plain `--check` says that a task would change, but not whether the rendered content is correct. `--diff` can reveal that the wrong variable was substituted, a port changed unexpectedly, an environment variable was removed, or a unit hardening option was accidentally deleted before production sees the change.

## Bonus: ansible-pull GitOps Loop

The playbook includes the bonus implementation and the timer is installed/enabled on the VM. It runs `ansible-pull` against `https://github.com/kujifined/DevOps-Intro.git` branch `feature/lab7`.

Enable the bonus path with:

```bash
ansible-playbook -i ansible/inventory.ini ansible/playbook.yaml -e ansible_pull_enabled=true
```

The playbook installs `ansible` and `git`, renders a local inventory for `127.0.0.1` with `ansible_connection=local`, and creates:

- `/etc/systemd/system/quicknotes-ansible-pull.service`
- `/etc/systemd/system/quicknotes-ansible-pull.timer`
- `/etc/ansible/quicknotes-local.ini`

Local pull inventory:

```ini
[quicknotes_vms]
127.0.0.1 ansible_connection=local ansible_python_interpreter=/usr/bin/python3
```

Timer proof:

```bash
vagrant ssh -c 'systemctl list-timers | grep quicknotes-ansible-pull'
```

Output:

```text
Sun 2026-06-28 13:28:49 UTC 3min 18s Sun 2026-06-28 13:22:47 UTC 2min 43s ago quicknotes-ansible-pull.timer quicknotes-ansible-pull.service
```

Convergence timeline:

```text
Git commit:            960a17fb5f071d2b9a04c0ae99c2199324b5f457
Timer fire in VM log:  2026-06-28 13:22:47 UTC
State reconciled:      2026-06-28 13:22:56 UTC in VM journal
Pulled state:          /opt/quicknotes-ansible-pull HEAD = 960a17fb5f071d2b9a04c0ae99c2199324b5f457
```

The sequence in the VM journal proves convergence: after the clean `feature/lab7` branch was pushed, the pull loop updated the VM work tree from the previous Lab 7 commit `e13580d43f43bb77ec767e4442735beb190697b3` to the clean branch commit `960a17fb5f071d2b9a04c0ae99c2199324b5f457`.

Successful pull evidence:

```text
Jun 28 13:22:56 quicknotes-vm ansible-pull[12101]: quicknotes-vm | CHANGED => {
Jun 28 13:22:56 quicknotes-vm ansible-pull[12101]:     "after": "960a17fb5f071d2b9a04c0ae99c2199324b5f457",
Jun 28 13:22:56 quicknotes-vm ansible-pull[12101]:     "before": "e13580d43f43bb77ec767e4442735beb190697b3",
Jun 28 13:22:56 quicknotes-vm ansible-pull[12101]: PLAY RECAP *********************************************************************
Jun 28 13:22:56 quicknotes-vm ansible-pull[12101]: quicknotes-vm              : ok=14   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
Jun 28 13:23:57 quicknotes-vm ansible-pull[13601]: 127.0.0.1                  : ok=14   changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
Jun 28 13:23:57 quicknotes-vm ansible-pull[13601]: /usr/bin/ansible-pull -U https://github.com/kujifined/DevOps-Intro.git -C feature/lab7 -d /opt/quicknotes-ansible-pull -i /etc/ansible/quicknotes-local.ini --limit 127.0.0.1 ansible/playbook.yaml -e ansible_pull_enabled=true
Jun 28 13:23:57 quicknotes-vm systemd[1]: Finished quicknotes-ansible-pull.service - Converge QuickNotes from Git with ansible-pull.
```

Final state check:

```text
User=quicknotes
Group=quicknotes
Environment="ADDR=:8080"
Environment="DATA_PATH=/var/lib/quicknotes/quicknotes.json"
Environment="SEED_PATH=/var/lib/quicknotes/seed.json"
ExecStart=/usr/local/bin/quicknotes
RestartSec=3s
{"notes":4,"status":"ok"}
```

Useful commands:

```bash
vagrant ssh -c 'sudo systemctl status quicknotes-ansible-pull.timer --no-pager'
vagrant ssh -c 'sudo journalctl -u quicknotes-ansible-pull.service -n 80 --no-pager'
vagrant ssh -c 'sudo systemctl cat quicknotes.service'
```

## Bonus Design Questions

**h) Security benefit of pull mode.** In push mode, a control node needs SSH reachability and credentials for every VM. In pull mode, the VM only needs outbound Git access and local privilege to converge itself. That reduces exposed inbound attack surface and avoids keeping broad SSH access on a central deploy machine.

**i) Kubernetes equivalent.** At the Kubernetes layer this pattern is GitOps, commonly implemented with Argo CD or Flux. `ansible-pull` is a fair VM-layer simulator because the desired state lives in Git, an agent periodically fetches it, compares it to local state, and reconciles drift without a human SSHing in from a control node.
