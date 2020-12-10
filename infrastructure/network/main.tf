provider "google" {
 version = "~> 3.49.0"
 credentials = var.terraformcredentialspath
 project     = var.project
 region      = var.region
}

//setup terraform state in GCS bucket, this bucket resides in CICD1 project
terraform {
    backend "gcs" {
      bucket  = "csye7125-gcp-myproject-bucket"
      prefix  = "network/state"
  }
} 

resource "google_compute_subnetwork" "network-with-private-secondary-ip-ranges" {
  name          = "gcp-subnetwork"
  ip_cidr_range = "10.2.0.0/16"
  region        = var.region
  network       = google_compute_network.custom-network.id
  # secondary_ip_range {
  #   range_name    = "tf-network-secondary-range-update1"
  #   ip_cidr_range = "192.168.10.0/24"
  # }
}

resource "google_compute_network" "custom-network" {
  name                    = "gcp-network"
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
}