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
    	prefix  = "cluster/state"
  }
} 

resource "google_container_cluster" "primary" {
  name     = "csye7125-gke-cluster"
  location = var.region
  network = "gcp-network"
  subnetwork = "gcp-subnetwork"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  master_auth {
    username = "admin"
    password = "adminadminadminadmin"

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "csye7125-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-medium"

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

# resource "null_resource" "disable-master-authorized-networks"{
#   provisioner local-exec {
#     command = "gcloud container clusters update local.cluster_name --no-enable-master-authorized-networks --project var.project"
#   }

#   depends_on = [google_container_cluster.primary]
# }