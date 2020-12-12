provider "google" {
 version = "~> 3.49.0"
 credentials = var.terraformcredentialspath
 project     = var.project
 region      = var.region
}

provider "google-beta" {
  project     = var.gcp_project
  credentials = var.terraformcredentialspath
  region      = var.region
  zone        = var.zone
}

//setup terraform state in GCS bucket, this bucket resides in CICD1 project
terraform {
    backend "gcs" {
    	bucket  = "csye7125-gcp-myproject-bucket"
    	prefix  = "cluster/state"
  }
}

resource "google_compute_network" "custom_network" {
  name                    = "gcp-network"
  routing_mode            = "GLOBAL"
  auto_create_subnetworks = false
  delete_default_routes_on_create = false
}

resource "google_compute_subnetwork" "custom_subnetwork" {
  name          = "gcp-subnetwork"
  ip_cidr_range = "10.10.0.0/16"
  region        = var.region
  network       = google_compute_network.custom_network.id
  private_ip_google_access = true
}

resource "google_compute_router" "router-1" {
  name    = "gcp-router-1"
  project = var.project
  region  = var.region
  network = google_compute_network.custom_network.id 
  depends_on = [google_compute_network.custom_network]
}


resource "google_compute_firewall" "project-firewall-allow-ssh" {
  name    = "gcp-allow-ssh"
  network = google_compute_network.custom_network.self_link
  allow {
    protocol = "tcp"
    ports    = ["22"] 
  }
source_ranges = ["72.235.194.73"] #according to cidr notation
}

resource "google_compute_firewall" "allow-db" {
  name    = "allow-from-gcp-network-cluster-to-db"
  network = "db-network"
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }
  source_ranges = ["172.10.0.0/16"]
  # target_tags = ["db-gcp-network"]
}

resource "google_compute_address" "address-1" {
  name           = "nat-external-address-1"
  project        = var.project
  region         = var.region
  address_type   = "INTERNAL"
  address        = "10.10.0.2"
  subnetwork     = google_compute_subnetwork.custom_subnetwork.id
  depends_on     = [google_compute_network.custom_network]
}

resource "google_compute_router_nat" "simple-nat" {
  name                               = "nat-routing-gateway"
  project                            = var.project
  router                             = google_compute_router.router-1.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  depends_on                         = [google_compute_network.custom_network,google_compute_router.router-1,google_compute_address.address-1]
  
}

resource "google_container_cluster" "primary" {
  name     = "csye7125-gke-cluster"
  location = var.region
  network = google_compute_network.custom_network.id
  subnetwork = google_compute_subnetwork.custom_subnetwork.id
  min_master_version = "1.16.15-gke.4300"
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

  # ip_allocation_policy {
  #   cluster_ipv4_cidr_block  = "10.10.144.0/20"
  #   services_ipv4_cidr_block = "10.10.0.0/17"
  # }
}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "csye7125-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1
  
  autoscaling {
    min_node_count = "3"
    max_node_count = "5"
  }
  
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