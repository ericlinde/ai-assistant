terraform {
  required_version = ">= 1.6.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.47"
    }
  }

  backend "s3" {
    endpoint                    = "https://13f543ea961e0c42234d00af783c18f9.eu.r2.cloudflarestorage.com"
    bucket                      = "agent-terraform-state"
    key                         = "terraform.tfstate"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
