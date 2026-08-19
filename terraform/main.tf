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

  # iperf3 testing port
  ingress_rule {
    label      = "iperf3"
    protocol   = "tcp"
    port_range = "5201"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
  }

  # Allow all outbound traffic
  egress_rule {
    label      = "all-outbound"
    protocol   = "tcp"
    port_range = "1-65535"
    cidr       = ["0.0.0.0/0"]
    action     = "allow"
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

    # Update and install monitoring tools
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg iperf3 bmon htop mtr-tiny

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

    # Add ubuntu user to docker group (so it doesn't need sudo)
    usermod -aG docker ubuntu

    # Get the VM's own public IP (needed for Coturn external-ip)
    VM_PUBLIC_IP=$(curl -4s ifconfig.me)

    # Create the coturn config directory
    mkdir -p /home/ubuntu/coturn
    chown ubuntu:ubuntu /home/ubuntu/coturn

    # Write turnserver.conf — uses the VM's real public IP
    cat > /home/ubuntu/coturn/turnserver.conf <<CONF
    listening-ip=0.0.0.0
    external-ip=$VM_PUBLIC_IP
    listening-port=3478
    tls-listening-port=5349
    min-port=49152
    max-port=50151
    lt-cred-mech
    user=poctest:${var.turn_secret}
    realm=turn.poc.coturn
    
    # Bandwidth controls
    max-bps=250000
    bps-capacity=0
    total-quota=1200
    user-quota=6

    # Security / Anti-SSRF (do NOT block 10.x, 192.168.x, 172.16.x as it breaks mobile)
    denied-peer-ip=0.0.0.0-0.255.255.255
    denied-peer-ip=127.0.0.0-127.255.255.255
    denied-peer-ip=169.254.0.0-169.254.255.255
    fingerprint
    stale-nonce=600
    
    # CLI
    cli-ip=127.0.0.1
    cli-port=5766
    cli-password=adminpoc123
    
    # Logging
    log-file=stdout
    simple-log
    
    no-multicast-peers
    CONF

    # Write docker-compose.yml
    cat > /home/ubuntu/coturn/docker-compose.yml <<COMPOSE
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
    cd /home/ubuntu/coturn
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
