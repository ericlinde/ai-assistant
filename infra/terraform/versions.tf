terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }
  }

  # Uncomment to enable remote state via S3-compatible backend (e.g. Hetzner Object Storage)
  # backend "s3" {
  #   endpoint                    = "https://fsn1.your-objectstorage.com"
  #   bucket                      = "agent-tfstate"
  #   key                         = "terraform.tfstate"
  #   region                      = "us-east-1"   # required by S3 protocol, value ignored
  #   skip_credentials_validation = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   force_path_style            = true
  # }
}
