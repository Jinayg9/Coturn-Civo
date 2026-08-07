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

  # SSH — only from your IP (security best practice)
  ingress_rule {
    label      = "ssh"
    protocol   = "tcp"
    port_range = "22"
    cidr       = ["${var.your_ip}/32"]
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
    port_range = "49152-65535"
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

    # Update and install Docker
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg iperf3 bmon htop mtr-tiny

    # Install Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    # Add ubuntu user to docker group (so it doesn't need sudo)
    usermod -aG docker ubuntu

    # Create the coturn config directory
    mkdir -p /home/ubuntu/coturn
    chown ubuntu:ubuntu /home/ubuntu/coturn

    # Write turnserver.conf
    cat > /home/ubuntu/coturn/turnserver.conf <<'CONF'
    listening-ip=0.0.0.0
    external-ip=$(curl -s ifconfig.me)
    listening-port=3478
    tls-listening-port=5349
    min-port=49152
    max-port=65535
    lt-cred-mech
    user=poctest:${var.turn_secret}
    realm=turn.poc.coturn
    denied-peer-ip=10.0.0.0-10.255.255.255
    denied-peer-ip=192.168.0.0-192.168.255.255
    denied-peer-ip=172.16.0.0-172.31.255.255
    cli-ip=127.0.0.1
    cli-port=5766
    cli-password=adminpoc123
    log-file=/var/log/coturn/turnserver.log
    verbose
    no-multicast-peers
    CONF

    # Write docker-compose.yml
    cat > /home/ubuntu/coturn/docker-compose.yml <<'COMPOSE'
    version: "3.8"
    services:
      coturn:
        image: coturn/coturn:latest
        network_mode: host
        restart: always
        volumes:
          - ./turnserver.conf:/etc/coturn/turnserver.conf:ro
          - coturn-logs:/var/log/coturn
        command: -c /etc/coturn/turnserver.conf
    volumes:
      coturn-logs:
    COMPOSE

    # Start Coturn
    cd /home/ubuntu/coturn
    docker compose up -d

    echo "Setup complete" >> /var/log/cloud-init-coturn.log
  EOT
}

# ============================================================
# The Compute Instance (VM) itself
# ============================================================
resource "civo_instance" "turn_server" {
  hostname    = "coturn-poc"
  region      = var.region
  size        = var.instance_size
  disk_image  = data.civo_disk_image.ubuntu.id
  firewall_id = civo_firewall.turn_firewall.id
  ssh_key_ids = [civo_ssh_key.poc_key.id]
  user_data   = local.cloud_init

  tags = ["poc", "turn", "coturn", "mumbai"]
}

# ============================================================
# Data source — look up the Ubuntu 24.04 image ID in MUM1
# ============================================================
data "civo_disk_image" "ubuntu" {
  filter {
    key    = "name"
    values = ["ubuntu-24-04"]
  }
  region = var.region
}
