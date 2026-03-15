provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "deployer" {
  name       = "deployer"
  public_key = file(var.ssh_public_key_path)
}

resource "hcloud_firewall" "agent" {
  name = "agent-firewall"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${var.deployer_ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "agent" {
  name        = "agent"
  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = var.server_location
  ssh_keys    = [hcloud_ssh_key.deployer.id]

  firewall_ids = [hcloud_firewall.agent.id]

  labels = {
    role = "agent"
  }
}

# Uncomment to attach a persistent volume (Phase 2+)
# resource "hcloud_volume" "agent_data" {
#   name      = "agent-data"
#   size      = 20
#   server_id = hcloud_server.agent.id
#   automount = true
#   format    = "ext4"
# }
