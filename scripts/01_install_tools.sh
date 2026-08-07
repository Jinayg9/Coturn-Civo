#!/bin/bash
# ==========================================================
# Script 01: Install all required tools on Raspberry Pi 5
# Run this ONCE on your RPi5 before starting the PoC
# Usage: bash 01_install_tools.sh
# ==========================================================

set -e  # Stop if any command fails

echo "================================================"
echo " Civo Coturn PoC — Tool Installer (Raspberry Pi 5)"
echo "================================================"

# --- System update ---
echo "[1/5] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
sudo -E apt update -y && sudo -E apt upgrade -y

# --- Network testing tools ---
echo "[2/5] Installing network test tools..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y iperf3 mtr netcat-openbsd curl wget htop bmon nmap traceroute coturn

# --- Terraform ---
echo "[4/5] Installing Terraform..."
# Add HashiCorp GPG key and repo
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update -y
sudo apt install -y terraform

# --- SSH Key (if not already exists) ---
echo "[5/5] Checking SSH key..."
if [ ! -f ~/.ssh/id_ed25519 ]; then
  echo "No SSH key found. Generating one..."
  ssh-keygen -t ed25519 -C "coturn-poc" -f ~/.ssh/id_ed25519 -N ""
  echo "SSH key created at ~/.ssh/id_ed25519"
else
  echo "SSH key already exists at ~/.ssh/id_ed25519 ✓"
fi

echo ""
echo "================================================"
echo " All tools installed successfully!"
echo "================================================"
echo ""
echo "Your public SSH key (copy this to terraform.tfvars):"
echo ""
cat ~/.ssh/id_ed25519.pub
echo ""
echo "Your public IP (copy this to terraform.tfvars as your_ip):"
curl -s ifconfig.me
echo ""
echo ""
echo "Generate a TURN secret with:"
echo "  openssl rand -hex 16"
