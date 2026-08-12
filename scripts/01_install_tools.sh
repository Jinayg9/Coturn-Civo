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

export DEBIAN_FRONTEND=noninteractive

# --- System update ---
echo "[1/4] Updating system packages..."
sudo -E apt update -y && sudo -E apt upgrade -y

# --- Network testing tools + Coturn utilities ---
echo "[2/4] Installing network test tools and Coturn utilities..."
sudo -E apt install -y iperf3 mtr netcat-openbsd curl wget htop bmon nmap traceroute coturn

# --- Terraform ---
echo "[3/4] Installing Terraform..."
# Add HashiCorp GPG key and repo (--yes to avoid re-run prompt)
wget -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo -E apt update -y
sudo -E apt install -y terraform

# --- SSH Key (if not already exists) ---
echo "[4/4] Checking SSH key..."
if [ ! -f ~/.ssh/id_ed25519 ]; then
  echo "No SSH key found. Generating one..."
  mkdir -p ~/.ssh
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
echo "Your public SSH key:"
echo ""
cat ~/.ssh/id_ed25519.pub
echo ""
echo "Your public IPv4 address:"
curl -4s ifconfig.me
echo ""
echo ""
echo "Generate a TURN secret with:"
echo "  openssl rand -hex 16"
