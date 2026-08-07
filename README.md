# Civo Coturn PoC

Proof of Concept to validate Civo Cloud Mumbai (MUM1) as a production-grade,
zero-egress TURN relay server for WebRTC video streaming workloads.

## Project Structure

```
civo-poc/
├── terraform/          # Infrastructure as Code — creates Civo VM + firewall
│   ├── provider.tf     # Civo Terraform provider config
│   ├── variables.tf    # All configurable values (region, size, etc.)
│   ├── main.tf         # Main resource definitions (VM, firewall, SSH key)
│   └── outputs.tf      # Outputs the VM IP after creation
│
├── coturn/             # Coturn TURN server configuration
│   ├── docker-compose.yml   # Run Coturn as a Docker container
│   └── turnserver.conf      # Coturn configuration file
│
├── scripts/            # Testing and monitoring scripts
│   ├── 01_install_tools.sh      # Install all test tools on RPi5 / Linux
│   ├── 02_functional_test.sh    # Quick TURN relay verification
│   ├── 03_load_test.sh          # 200 concurrent session load test
│   ├── 04_network_quality.sh    # Jitter, packet loss, latency via iperf3/mtr
│   └── 05_soak_monitor.sh       # 30-day daily monitoring cron script
│
└── results/            # Store test output reports here (gitignored raw data)
    └── .gitkeep
```

## Quick Start

### Prerequisites
- Raspberry Pi 5 (or any Linux machine)
- Civo account with PoC credits activated
- Terraform installed (see `scripts/01_install_tools.sh`)
- Docker + Docker Compose installed

### Step 1 — Install tools on your RPi5
```bash
bash scripts/01_install_tools.sh
```

### Step 2 — Deploy VM via Terraform
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Civo API key
terraform init
terraform plan
terraform apply
```

### Step 3 — Start Coturn via Docker on the Civo VM
```bash
# SSH into your new VM (IP shown after terraform apply)
ssh ubuntu@<VM_IP>
# Then on the VM:
docker compose up -d
```

### Step 4 — Run Tests from your RPi5
```bash
bash scripts/02_functional_test.sh <VM_IP>
bash scripts/03_load_test.sh <VM_IP>
bash scripts/04_network_quality.sh <VM_IP>
```

## Key Evaluation Metrics

| Metric | Pass Threshold |
|---|---|
| UDP Jitter | < 20 ms |
| Packet Loss | < 1% |
| Concurrent Sessions | 200+ sustained |
| CPU at full load | < 60% |
| Port throttling | None detected |
| 30-day uptime | > 99.9% |
