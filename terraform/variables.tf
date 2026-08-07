variable "civo_api_key" {
  description = "Your Civo API key — get from https://dashboard.civo.com/security"
  type        = string
  sensitive   = true # Prevents the key from showing in logs
}

variable "region" {
  description = "Civo region to deploy in"
  type        = string
  default     = "MUM1" # Mumbai
}

variable "instance_size" {
  description = "VM size. g4s.kube.medium = 4 vCPU, 8GB RAM"
  type        = string
  default     = "g4s.kube.medium"
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key on your RPi5"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "your_ip" {
  description = "Your public IP to restrict SSH access. Get it from: curl ifconfig.me"
  type        = string
}

variable "turn_secret" {
  description = "Secret for TURN server auth. Generate with: openssl rand -hex 16"
  type        = string
  sensitive   = true
}
