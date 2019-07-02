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

# Create a service account with minimal permission, to reduce the
# security risk associated with the default service account.
resource "google_service_account" "serviceaccount" {
  account_id    = var.cluster.service_account
  display_name  = "Kubernetes (cluster ${var.cluster.name})"
}

resource "google_project_iam_member" "iam-logging-logwriter" {
  project = var.platform.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.serviceaccount.email}"
}

resource "google_project_iam_member" "iam-monitoring-metricwriter" {
  project = var.platform.project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.serviceaccount.email}"
}

resource "google_project_iam_member" "iam-monitoring-viewer" {
  project = var.platform.project
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.serviceaccount.email}"
}

resource "google_storage_bucket_iam_member" "iam-gcr" {
  bucket = "eu.artifacts.${var.platform.project}.appspot.com"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.serviceaccount.email}"
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
    "k8s-${var.cluster.name}-node"
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
  resource_labels           = null
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
    cluster_ipv4_cidr_block = var.cluster.ranges.pods.cidr
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

resource "google_container_node_pool" "pool" {
  provider    = "google-beta"
  name       = var.cluster.pool.name
  cluster    = google_container_cluster.cluster.name
  node_count = var.cluster.pool.size

  management {
    auto_repair = true
    auto_upgrade = var.cluster.pool.auto_upgrade
  }

  node_config {
    preemptible  = false
    machine_type = var.cluster.pool.machine_type

    metadata = {
      disable-legacy-endpoints = "true"
    }

    tags = [
        "k8s-drone-${var.cluster.name}-${var.cluster.pool.name}-node",
        "k8s-drone-${var.cluster.name}",
        "k8s-drone"
    ]
    service_account = google_service_account.serviceaccount.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]
  }
}
