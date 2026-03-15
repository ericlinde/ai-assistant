variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key file to upload to Hetzner"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "deployer_ip" {
  description = "IP address allowed to SSH into the server (your machine's public IP)"
  type        = string
}

variable "server_location" {
  description = "Hetzner datacenter location (e.g. nbg1, fsn1, hel1)"
  type        = string
  default     = "nbg1"
}

variable "server_type" {
  description = "Hetzner server type (e.g. cx22, cx32)"
  type        = string
  default     = "cx22"
}
