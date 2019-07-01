variable "platform" {}
variable "cluster" {}


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
  name   = var.cluster.network.subnet
  region = var.cluster.network.region
}

data "google_compute_network" "vpc" {
  name = var.cluster.network.name
}

data "google_kms_key_ring" "keyring" {
  name     = var.cluster.key.keyring
  location = var.cluster.key.location
}

data "google_kms_crypto_key" "kubernetes-etcd" {
  name            = var.cluster.key.name
  key_ring        = "${data.google_kms_key_ring.keyring.self_link}"
}

data "google_service_account" "serviceaccount" {
  account_id = var.cluster.service_account
}


# Since we assume a network environment where all network
# traffic to outside hosts is blocked, create a firewall
# rule that allows communication between the nodes and the
# cluster master (which is in a separate VPC).
resource "google_compute_firewall" "allow-cluster-endpoint-egress" {
  name      = "${data.google_compute_network.vpc.name}-${var.cluster.name}-allow-cluster-master"
  network   = "${data.google_compute_network.vpc.name}"
  priority  = 1000
  direction = "EGRESS"

  target_tags = [
    "${var.cluster.name}-node"
  ]

  destination_ranges = [
    var.cluster.endpoint
  ]

  allow {
    protocol  = "tcp"
    ports     = ["443", "10250"]
  }
}


resource "google_container_cluster" "cluster" {
  provider                  = "google-beta"
  name                      = var.cluster.name
  network                   = data.google_compute_network.vpc.name
  subnetwork                = data.google_compute_subnetwork.subnet.name
  location                  = var.cluster.location.master
  remove_default_node_pool  = true
  initial_node_count        = 1
  min_master_version        = "1.13"
  node_locations            = var.cluster.location.nodes

  network_policy {
    enabled = true
  }

  pod_security_policy_config {
    enabled = true
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block = var.cluster.authorized_network.cidr
      display_name = var.cluster.authorized_network.name
    }
  }

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = var.cluster.endpoint
  }

  ip_allocation_policy {
    services_ipv4_cidr_block = var.cluster.ranges.services.cidr
    node_ipv4_cidr_block = var.cluster.ranges.pods.cidr
  }

  addons_config {
    http_load_balancing {
      disabled = true
    }

    network_policy_config {
      disabled = false
    }
  }

  database_encryption {
    state     = "ENCRYPTED"
    key_name  = "${data.google_kms_crypto_key.kubernetes-etcd.self_link}"
  }

  logging_service = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }
}
