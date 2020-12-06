provider "google" {
 version = "~> 3.49.0"
 credentials = var.terraformcredentialspath
 project     = var.project
 region      = "us-east1"
}

//setup terraform state in GCS bucket, this bucket resides in CICD1 project
terraform {
    backend "gcs" {
      bucket  = "csye7125-gcp-project-bucket"
      prefix  = "network/state"
  }
} 

resource "google_compute_subnetwork" "network-with-private-secondary-ip-ranges" {
  name          = "test-subnetwork"
  ip_cidr_range = "10.2.0.0/16"
  region        = "us-east1"
  network       = google_compute_network.custom-test.id
  secondary_ip_range {
    range_name    = "tf-test-secondary-range-update1"
    ip_cidr_range = "192.168.10.0/24"
  }
}

resource "google_compute_network" "custom-test" {
  name                    = "test-network"
  auto_create_subnetworks = false
}