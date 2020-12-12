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
    	prefix  = "services/state"
  }
} 

resource "google_project_service" "csye7125-gcp-project" {
  for_each = toset(var.services)
  project = var.project
  service = each.value

  disable_dependent_services=true
}