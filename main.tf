variable "platform" {}


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
