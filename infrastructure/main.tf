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

# resource "google_compute_route" "default" {
#   name        = "gcp-network-route"
#   dest_range  = "0.0.0.0/0"
#   network     = google_compute_network.custom-network.name
#   next_hop_gateway = "default-internet-gateway"
#   priority    = 1000
# }

resource "google_compute_subnetwork" "custom-subnetwork" {
  name          = "gcp-subnetwork"
  ip_cidr_range = "10.10.128.0/16"
  region        = var.region
  network       = google_compute_network.custom-network.id
  private_ip_google_access = true
  # secondary_ip_range = ["services=10.10.11.0/24","pods=10.1.0.0/16"]
  # secondary_ip_range {
  #   range_name    = "services"
  #   ip_cidr_range = "10.10.0.0/17"
  # }
  # secondary_ip_range {
  #   range_name    = "pod"
  #   ip_cidr_range = "10.10.144.0/20"
  # }

  # log_config {
  # // aggregation_interval = "INTERVAL_10_MIN" 
  #   flow_sampling = 0.5
  #   metadata = "INCLUDE_ALL_METADATA"
  # }
}

resource "google_compute_network" "custom-network" {
  name                    = "gcp-network"
  routing_mode            = "GLOBAL"
  auto_create_subnetworks = false
  delete_default_routes_on_create = false
}

resource "google_compute_route" "default" {
  name        = "network-route"
  dest_range  = "15.0.0.0/24"
  network     = google_compute_network.default.name
  next_hop_ip = "10.132.1.5"
  priority    = 100
}
resource "google_compute_router" "router-1" {
  name    = "gcp-router-1"
  project = var.project
  region  = var.region
  network = google_compute_network.custom-network.id
  # bgp {
  #   asn = 64514
  # }  
  depends_on = [google_compute_network.custom-network]
}

# resource "google_compute_address" "address-1" {
#   name           = "nat-external-address-1"
#   project        = var.project
#   region         = var.region
#   address_type   = "INTERNAL"
#   address        = "10.10.128.2"
#   subnetwork     = google_compute_subnetwork.custom-subnetwork.id
#   depends_on     = [google_compute_network.custom-network]
# }

# resource "google_compute_address" "address-2" {
#   name          = "nat-external-address-2"
#   project       = var.project
#   region        = var.region
#   address_type  = "INTERNAL"
#   address       = "10.10.128.3"
#   subnetwork    = google_compute_subnetwork.custom-subnetwork.id
#   depends_on    = [google_compute_network.custom-network]
# } 

# resource "google_compute_router_nat" "simple-nat" {
#   name                               = "nat-routing-gateway"
#   project                            = var.project
#   router                             = google_compute_router.router-1.name
#   region                             = var.region
#   nat_ip_allocate_option             = "AUTO_ONLY"
#   source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
#   depends_on                         = [google_compute_network.custom-network,google_compute_router.router-1]
  
# }

# //VPC Peering setup

# resource "google_compute_network_peering" "insight-peering1" {
#   name = "insight-${var.project}-peering1"
#   network = "projects/${var.project}/global/networks/${local.vpc_network}"
#   peer_network = "projects/rmaas-ci-cd-1/global/networks/insight-deployment-vpc"
#   depends_on               = ["google_compute_network.custom-network"]
# }


resource "google_container_cluster" "primary" {
  name     = "csye7125-gke-cluster"
  location = var.region
  network = google_compute_network.custom-network.id
  subnetwork = google_compute_subnetwork.custom-subnetwork.id

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