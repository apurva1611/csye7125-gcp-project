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

# // This is allow SSH connection http and https connection
resource "google_compute_firewall" "allow-http-https" {
  name = "allow-http-https"
  project = var.project
  network = google_compute_network.custom_network.id
  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }
  target_tags = ["allow-https","allow-http"]
  depends_on  = [google_compute_network.custom_network]
}

resource "google_compute_firewall" "allow-db" {
  name    = "allow-from-gcp-network-cluster-to-db"
  network = google_compute_network.custom_network.id
  allow {
    protocol = "icmp"
  }
  allow {
    protocol = "tcp"
    ports    = ["3306"]
  }
  source_tags = ["mysql-client"]
  target_tags = ["mysql-server"]
}

# resource "google_compute_firewall" "allow-icmp" {
#   name = "allow-icmp"
#   project = var.project
#   network = google_compute_network.custom_network.id 
#   source_ranges     = ["0.0.0.0/0"]
#   allow {
#     protocol = "icmp"
#   }
#   allow {
#     protocol = "tcp"
#     ports = ["8089","8080","8000","443","80"]
#   }
#   target_tags = ["allow-icmp"]
#   depends_on  = [google_compute_network.custom_network]
# }

# // This is allow SSH connection using IAP
resource "google_compute_firewall" "allow-iap-ssh" {
  name              = "allow-iap-ssh"
  project           = var.project
  network           = google_compute_network.custom_network.id
  source_ranges     = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
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

  private_cluster_config {
    master_ipv4_cidr_block = "10.2.0.0/28"
    enable_private_nodes  = true
    enable_private_endpoint = false
  }

  master_auth {
    username = "admin"
    password = "adminadminadminadmin"

    client_certificate_config {
      issue_client_certificate = false
    }
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.20.0.0/16"
    services_ipv4_cidr_block = "10.40.0.0/16"
  }

}

resource "google_container_node_pool" "primary_preemptible_nodes" {
  name       = "csye7125-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 1
  
  autoscaling {
    min_node_count = "1"
    max_node_count = "3"
  }
  
  node_config {
    preemptible  = true
    machine_type = "e2-standard-2"

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
    tags = ["mysql-client"]
  }

  upgrade_settings {
      max_surge = 5
      max_unavailable = 3
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
// db
resource "google_sql_database_instance" "webapp_instance" {
  name   = var.webappinstance
  region = var.region
  database_version = "MYSQL_8_0"  
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

resource "google_sql_database" "webapp_db" {
  depends_on = [google_sql_database_instance.webapp_instance]

  name      = var.webappdb
  project   = var.project
  instance  = google_sql_database_instance.webapp_instance.name
  # charset   = var.db_charset
  # collation = var.db_collation
}

resource "google_sql_user" "webappuser" {
  depends_on = [google_sql_database.webapp_db]

  project  = var.project
  name     = var.master_user_name
  password = var.master_user_password
  instance = google_sql_database_instance.webapp_instance.name
}

// poller db
resource "google_sql_database_instance" "poller_instance" {
  name   = var.pollerinstance
  region = var.region
  database_version = "MYSQL_8_0"
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

resource "google_sql_database" "poller_db" {
  depends_on = [google_sql_database_instance.poller_instance]

  name      = var.pollerdb
  project   = var.project
  instance  = google_sql_database_instance.poller_instance.name
  # charset   = var.db_charset
  # collation = var.db_collation
}

resource "google_sql_user" "polleruser" {
  depends_on = [google_sql_database.poller_db]

  project  = var.project
  name     = var.master_user_name
  password = var.master_user_password
  instance = google_sql_database_instance.poller_instance.name
}

// notifier db
resource "google_sql_database_instance" "notifier_instance" {
  name   = var.notifierinstance
  region = var.region
  database_version = "MYSQL_8_0"
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

resource "google_sql_database" "notifier_database" {
  depends_on = [google_sql_database_instance.notifier_instance]

  name      = var.notifierdb
  project   = var.project
  instance  = google_sql_database_instance.notifier_instance.name
  # charset   = var.db_charset
  # collation = var.db_collation
}

resource "google_sql_user" "notifieruser" {
  depends_on = [google_sql_database.notifier_database]

  project  = var.project
  name     = var.master_user_name
  password = var.master_user_password
  instance = google_sql_database_instance.notifier_instance.name
}