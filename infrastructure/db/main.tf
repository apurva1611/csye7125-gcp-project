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
    	prefix  = "db/state"
  }
}

resource "google_compute_network" "db_network" {
  name = "db-network"
}

resource "google_compute_subnetwork" "custom-subnetwork" {
  name          = "db-subnetwork"
  ip_cidr_range = "172.10.0.0/16"
  region        = var.region
  network       = google_compute_network.db_network.id
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_ip_address" {
  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.db_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.db_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "instance" {
  name   = "test4-instance"
  region = "us-east1"
  deletion_protection = false
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-f1-micro"
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.db_network.id
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
