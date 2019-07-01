variable "platform" {}
variable "network" {}


provider "google" {
  project = var.platform.project
  region  = var.platform.region
  zone    = var.platform.zone
}

provider "google-beta" {
  project = var.platform.project
  region  = var.platform.region
  zone    = var.platform.zone
}

data "google_compute_subnetwork" "subnet" {
  name   = var.network.subnet
  region = var.network.region
}
