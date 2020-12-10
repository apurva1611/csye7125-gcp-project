//provider
provider "google" {
 version = "~> 3.49.0"
 credentials = var.terraformcredentialspath
 project     = var.project
 region      = var.region
}

provider "google-beta" {
  project     = var.project
  credentials = var.terraformcredentialspath
  region      = var.region
}

//setup terraform state in GCS bucket, this bucket resides in CICD1 project
terraform {
    backend "gcs" {
    	bucket  = "csye7125-gcp-myproject-bucket"
    	prefix  = "gcpresource/state"
  }
}

//custom network
resource "google_compute_network" "custom_network" {
  name                    = "my-network"
  routing_mode            = "GLOBAL"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "custom_subnetwork" {
  name          = "my-subnetwork"
  ip_cidr_range = "10.10.0.0/16"
  region        = var.region
  network       = google_compute_network.custom_network.id
  private_ip_google_access = true
}

// This is allow SSH connection http and https connection
resource "google_compute_firewall" "allow-http-https" {
  name = "allow-http-https"
  project = var.project
  network = google_compute_network.custom_network.id
  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }
  target_tags = ["allow-https"]
  depends_on  = [google_compute_network.custom_network]
}

resource "google_compute_firewall" "allow-icmp" {
  name = "allow-icmp"
  project = var.project
  network = google_compute_network.custom_network.id 
  allow {
    protocol = "icmp"
  }
  target_tags = ["allow-icmp"]
  depends_on  = [google_compute_network.custom_network]
}

// This is allow SSH connection using IAP
resource "google_compute_firewall" "allow-iap-ssh" {
  name              = "allow-iap-ssh"
  project           = var.project
  network           = google_compute_network.custom_network.id
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  allow {
    protocol = "icmp"
  }
  target_tags       = ["allow-iap-ssh"]
  depends_on        = [google_compute_network.custom_network]
}

resource "google_compute_router" "router-1" {
  name    = "gcp-router-1"
  project = var.project
  region  = var.region
  network = google_compute_network.custom_network.id 
  depends_on = [google_compute_network.custom_network]
}

# resource "google_compute_address" "address-1" {
#   name           = "nat-external-address-1"
#   project        = var.project
#   region         = var.region
#   address_type   = "INTERNAL"
#   address        = "10.10.0.2"
#   subnetwork     = google_compute_subnetwork.custom_subnetwork.id
#   depends_on     = [google_compute_network.custom_network]
# }

resource "google_compute_router_nat" "simple-nat" {
  name                               = "nat-routing-gateway"
  project                            = var.project
  router                             = google_compute_router.router-1.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  depends_on                         = [google_compute_network.custom_network,google_compute_router.router-1]
  
}

// custom cluster
resource "google_container_cluster" "primary" {
  name                  = "csye7125-gke-cluster"
  location              = var.region
  network               = google_compute_network.custom_network.id
  subnetwork            = google_compute_subnetwork.custom_subnetwork.id
  min_master_version    = "1.16.15-gke.4300"
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

// db
// peering
resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.custom_network.id
  depends_on     = [google_compute_network.custom_network]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.custom_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

// db
resource "google_sql_database_instance" "instance" {
  name   = "test6-instance"
  region = "us-east1"
  deletion_protection = false
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.custom_network.id
    }
  }
}

resource "google_sql_database" "default" {
  depends_on = [google_sql_database_instance.instance]

  name      = var.db_name
  project   = var.project
  instance  = google_sql_database_instance.instance.name
  # charset   = var.db_charset
  # collation = var.db_collation
}

resource "google_sql_user" "default" {
  depends_on = [google_sql_database.default]

  project  = var.project
  name     = var.master_user_name
  password = var.master_user_password
  instance = google_sql_database_instance.instance.name
}