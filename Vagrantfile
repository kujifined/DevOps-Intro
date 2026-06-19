# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.hostname = "quicknotes-vm"

  config.vm.network "forwarded_port",
                    guest: 8080,
                    host: 18080,
                    host_ip: "127.0.0.1",
                    auto_correct: false

  config.vm.synced_folder "./app",
                          "/home/vagrant/quicknotes/app",
                          type: "virtualbox"

  config.vm.provider "virtualbox" do |vb|
    vb.name = "quicknotes-lab5"
    vb.cpus = 2
    vb.memory = 1024

    # VirtualBox NAT on macOS/ARM may not relay DNS reliably unless it uses
    # the host resolver explicitly.
    vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
    vb.customize ["modifyvm", :id, "--natdnsproxy1", "on"]
  end

  config.vm.provision "shell", privileged: true, inline: <<~'SHELL'
    set -euxo pipefail

    readonly GO_VERSION="1.24.5"

    case "$(dpkg --print-architecture)" in
      amd64) GO_ARCH="amd64" ;;
      arm64) GO_ARCH="arm64" ;;
      *)
        echo "Unsupported guest architecture: $(dpkg --print-architecture)" >&2
        exit 1
        ;;
    esac

    readonly GO_TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    export DEBIAN_FRONTEND=noninteractive

    # Some VirtualBox/macOS ARM combinations advertise an unreachable NAT DNS
    # relay. Keep working DHCP DNS untouched and install public resolvers only
    # when name resolution is actually broken.
    if ! getent hosts go.dev >/dev/null 2>&1; then
      install -d /etc/systemd/resolved.conf.d
      cat >/etc/systemd/resolved.conf.d/quicknotes-dns.conf <<'EOF'
    [Resolve]
    DNS=1.1.1.1 8.8.8.8
    FallbackDNS=1.1.1.1 8.8.8.8
    EOF
      systemctl restart systemd-resolved
    fi

    apt-get update
    apt-get install -y --no-install-recommends ca-certificates curl

    if ! /usr/local/go/bin/go version 2>/dev/null | grep -Fq "go${GO_VERSION}"; then
      curl --fail --location --silent --show-error \
        "https://go.dev/dl/${GO_TARBALL}" \
        --output "/tmp/${GO_TARBALL}"
      rm -rf /usr/local/go
      tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"
      rm -f "/tmp/${GO_TARBALL}"
    fi

    cat >/etc/profile.d/go.sh <<'EOF'
    export PATH=/usr/local/go/bin:$PATH
    EOF
    ln -sfn /usr/local/go/bin/go /usr/local/bin/go
    ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt

    install -d -o vagrant -g vagrant /opt/quicknotes /var/lib/quicknotes
    cd /home/vagrant/quicknotes/app
    sudo -u vagrant /usr/local/go/bin/go build -o /opt/quicknotes/quicknotes .
    install -o vagrant -g vagrant -m 0644 seed.json /opt/quicknotes/seed.json

    cat >/etc/systemd/system/quicknotes.service <<'EOF'
    [Unit]
    Description=QuickNotes web service
    After=network.target

    [Service]
    Type=simple
    User=vagrant
    Group=vagrant
    WorkingDirectory=/var/lib/quicknotes
    Environment=ADDR=:8080
    Environment=DATA_PATH=/var/lib/quicknotes/notes.json
    Environment=SEED_PATH=/opt/quicknotes/seed.json
    ExecStart=/opt/quicknotes/quicknotes
    Restart=on-failure
    RestartSec=2
    NoNewPrivileges=true
    PrivateTmp=true

    [Install]
    WantedBy=multi-user.target
    EOF

    systemctl daemon-reload
    systemctl enable quicknotes.service
    systemctl restart quicknotes.service

    for _ in $(seq 1 20); do
      if curl --fail --silent http://127.0.0.1:8080/health >/dev/null; then
        systemctl --no-pager --full status quicknotes.service
        exit 0
      fi
      sleep 1
    done

    journalctl -u quicknotes.service --no-pager -n 50
    exit 1
  SHELL
end
