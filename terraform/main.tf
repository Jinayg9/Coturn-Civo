# ============================================================
# SSH Key — uploaded to Civo so you can log into the VM
# ============================================================
resource "civo_ssh_key" "poc_key" {
  name       = "coturn-poc-rpi5-key"
  public_key = file(var.ssh_public_key_path)
}

# ============================================================
# Firewall — controls which ports are open on the VM
# ============================================================
resource "civo_firewall" "turn_firewall" {
  name                 = "coturn-poc-firewall"
  create_default_rules = false # We define all rules ourselves

  # SSH — open to all (we rely on SSH key auth for security)
  ingress_rule {
    label      = "ssh"
    protocol   = "tcp"
    port_range = "22"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  # TURN/STUN — standard UDP port (open to all, needed for WebRTC)
  ingress_rule {
    label      = "turn-udp"
    protocol   = "udp"
    port_range = "3478"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  # TURN/STUN — TCP fallback
  ingress_rule {
    label      = "turn-tcp"
    protocol   = "tcp"
    port_range = "3478"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  # TURNS (TURN over TLS) — secure WebRTC
  ingress_rule {
    label      = "turns-udp"
    protocol   = "udp"
    port_range = "5349"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "turns-tcp"
    protocol   = "tcp"
    port_range = "5349"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  # WebRTC Media Relay port range — MUST match turnserver.conf
  ingress_rule {
    label      = "webrtc-relay"
    protocol   = "udp"
    port_range = "49152-50151"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  # ICMP (ping) — needed for latency testing
  ingress_rule {
    label    = "icmp-ping"
    protocol = "icmp"
    cidr     = ["0.0.0.0/0"]
    action   = "allow"
  }

  # iperf3 testing port
  ingress_rule {
    label      = "iperf3"
    protocol   = "tcp"
    port_range = "5201"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  ingress_rule {
    label      = "iperf3-udp"
    protocol   = "udp"
    port_range = "5201"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  # Allow all outbound traffic
  egress_rule {
    label      = "all-outbound-tcp"
    protocol   = "tcp"
    port_range = "1-65535"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  egress_rule {
    label      = "all-outbound-udp"
    protocol   = "udp"
    port_range = "1-65535"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  egress_rule {
    label    = "all-outbound-icmp"
    protocol = "icmp"
    cidr     = ["0.0.0.0/0"]
    action   = "allow"
  }
}

# ============================================================
# Cloud-init script — runs automatically when VM first boots
# Installs Docker and sets up Coturn on startup
# ============================================================
locals {
  cloud_init = <<-EOT
    #!/bin/bash
    set -e

    export DEBIAN_FRONTEND=noninteractive

    # --- Kernel tuning for high-concurrency TURN ---
    cat >> /etc/sysctl.conf <<SYSCTL
    fs.file-max = 1000000
    net.ipv4.ip_local_port_range = 1024 65535
    net.core.rmem_max = 26214400
    net.core.wmem_max = 26214400
    net.core.rmem_default = 1048576
    net.core.wmem_default = 1048576
    net.core.netdev_max_backlog = 50000
    SYSCTL
    sysctl -p

    # Raise per-process file descriptor limits
    cat >> /etc/security/limits.conf <<LIMITS
    *    soft    nofile    1000000
    *    hard    nofile    1000000
    root soft    nofile    1000000
    root hard    nofile    1000000
    LIMITS

    # Update and install monitoring tools
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg iperf3 bmon htop mtr-tiny vnstat dstat sysstat

    # Start vnstat for automatic bandwidth monitoring
    systemctl enable vnstat
    systemctl start vnstat

    # Install Docker — official method
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Add civo user to docker group (so it doesn't need sudo)
    usermod -aG docker civo

    # Get the VM's own public IP (needed for Coturn external-ip)
    VM_PUBLIC_IP=$(curl -4s ifconfig.me)

    # Create the coturn config directory
    mkdir -p /home/civo/coturn
    chown civo:civo /home/civo/coturn

    # Write turnserver.conf — uses the VM's real public IP
    cat > /home/civo/coturn/turnserver.conf <<CONF
    listening-ip=0.0.0.0
    external-ip=$VM_PUBLIC_IP
    listening-port=3478
    tls-listening-port=5349
    min-port=49152
    max-port=50151
    lt-cred-mech
    user=poctest:${var.turn_secret}
    realm=turn.poc.coturn
    
    # Bandwidth controls - uncapped for load testing
    # max-bps=250000
    # bps-capacity=0
    total-quota=0
    user-quota=0

    # Security
    # NOTE: denied-peer-ip rules removed for PoC testing.
    # In production, re-add:
    #   denied-peer-ip=0.0.0.0-0.255.255.255
    #   denied-peer-ip=127.0.0.0-127.255.255.255
    #   denied-peer-ip=169.254.0.0-169.254.255.255
    fingerprint
    stale-nonce=600
    allow-loopback-peers
    
    # CLI
    cli-ip=127.0.0.1
    cli-port=5766
    cli-password=${var.turn_cli_password}
    
    # Logging
    log-file=stdout
    simple-log
    
    no-multicast-peers
    CONF

    # Write docker-compose.yml
    cat > /home/civo/coturn/docker-compose.yml <<COMPOSE
    services:
      coturn:
        image: coturn/coturn:4.6
        container_name: coturn-poc
        network_mode: host
        restart: always
        volumes:
          - ./turnserver.conf:/etc/coturn/turnserver.conf:ro
        command: -c /etc/coturn/turnserver.conf
        logging:
          driver: json-file
          options:
            max-size: "10m"
            max-file: "5"
    COMPOSE

    # Start Coturn
    cd /home/civo/coturn
    docker compose up -d

    echo "Setup complete at $(date)" >> /var/log/cloud-init-coturn.log
  EOT
}

# ============================================================
# The Compute Instance (VM) itself
# ============================================================
resource "civo_instance" "turn_server" {
  hostname    = "coturn-poc"
  region      = var.region
  size        = var.instance_size
  disk_image  = element(data.civo_disk_image.ubuntu.diskimages, 0).id
  firewall_id = civo_firewall.turn_firewall.id
  sshkey_id   = civo_ssh_key.poc_key.id
  script      = local.cloud_init

  lifecycle {
    ignore_changes = [script]
  }

  tags = ["turn-poc", "coturn", "mumbai"]
}

# ============================================================
# Data source — look up the Ubuntu 24.04 (Noble) image ID in MUM1
# ============================================================
data "civo_disk_image" "ubuntu" {
  filter {
    key    = "name"
    values = ["ubuntu-noble"]
  }
  region = var.region
}
