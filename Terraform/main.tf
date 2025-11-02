terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}



# ==================== VPC NETWORK ====================

resource "google_compute_network" "vpc" {
  name                    = "gcp-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# ==================== MANAGEMENT SUBNET ====================

resource "google_compute_subnetwork" "management_subnet" {
  name          = "management-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
  }
}

# ==================== RESTRICTED SUBNET ====================

resource "google_compute_subnetwork" "restricted_subnet" {
  name          = "restricted-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
  }
}

# ==================== CLOUD ROUTER ====================

resource "google_compute_router" "router" {
  name    = "nat-router"
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

# ==================== NAT GATEWAY ====================

resource "google_compute_router_nat" "nat" {
  name                               = "nat-gateway"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.management_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  subnetwork {
    name                    = google_compute_subnetwork.restricted_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ==================== FIREWALL RULES ====================

# Allow SSH from management subnet
resource "google_compute_firewall" "allow_ssh_management" {
  name    = "allow-ssh-management"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["10.0.1.0/24","35.235.240.0/20"]
  target_tags   = ["ssh-enabled"]
}
# Allow restricted subnet to pull from Google Artifact Registry via NAT
resource "google_compute_firewall" "allow_restricted_to_gar" {
  name      = "allow-restricted-to-gar-nat"
  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 700  # Higher priority than deny rule (1000)

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  # Allow to any destination (traffic goes through NAT)
  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["restricted"]
}
resource "google_compute_firewall" "allow_restricted_to_master" {
  name      = "allow-restricted-to-master"
  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 800

  allow {
    protocol = "tcp"
    ports    = ["443", "6443"]
  }

  destination_ranges = ["172.16.0.0/28"]     # master_ipv4_cidr_block in your cluster
  target_tags        = ["restricted"]
}
# Allow health checks for load balancer
resource "google_compute_firewall" "allow_health_checks" {
  name    = "allow-health-checks"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["8080"]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["load-balanced", "health-check"]
}

# Allow internal communication
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.0.0/16"]
}

# Allow Kubelet API
resource "google_compute_firewall" "allow_kubelet" {
  name    = "allow-kubelet-api"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["10250"]
  }

  source_ranges = ["10.0.2.0/24"]
  target_tags   = ["gke-node"]
}

# Allow K8s API
resource "google_compute_firewall" "allow_k8s_api" {
  name    = "allow-k8s-api"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["443", "6443"]
  }

  source_ranges = ["10.0.1.0/24"]
  target_tags   = ["gke-node"]
}

# Deny all outbound from restricted subnet (except Google APIs)
resource "google_compute_firewall" "deny_restricted_internet" {
  name      = "deny-restricted-internet"
  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 1000

  deny {
    protocol = "tcp"
  }

  deny {
    protocol = "udp"
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = ["restricted"]
}

# Allow restricted to Google APIs (Private Google Access)
resource "google_compute_firewall" "allow_google_apis" {
  name      = "allow-google-apis"
  network   = google_compute_network.vpc.id
  direction = "EGRESS"
  priority  = 900

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = ["199.36.153.4/30"]

  target_tags        = ["restricted"]
}

# Allow management VM to GKE
resource "google_compute_firewall" "allow_mgmt_to_gke" {
  name    = "allow-management-to-gke"
  network = google_compute_network.vpc.id

  allow {
    protocol = "tcp"
    ports    = ["443", "6443"]
  }

  source_ranges = ["10.0.1.0/24"]
  target_tags   = ["gke-node"]
}

# ==================== SERVICE ACCOUNT ====================

resource "google_service_account" "gke_node_sa" {
  account_id   = "gke-node-sa"
  display_name = "GKE Node Service Account"
}

# ==================== IAM ROLES ====================

resource "google_project_iam_member" "gke_node_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

resource "google_project_iam_member" "gke_node_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}

# ==================== GKE CLUSTER ====================

resource "google_container_cluster" "primary" {
  name     = var.gke_cluster_name
  location = "${var.region}-b"

  remove_default_node_pool = true
  deletion_protection = false
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.restricted_subnet.name

  # Private cluster configuration
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Authorized networks - only management subnet
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.1.0/24"
      display_name = "management-subnet"
    }
    cidr_blocks {
        cidr_block   = "10.0.2.0/24"
        display_name = "restricted-subnet"
    }
  }

  resource_labels = {
    environment = "production"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    horizontal_pod_autoscaling {
      disabled = false
    }
  }
}

# ==================== GKE NODE POOL ====================

resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  location   = "${var.region}-b"
  cluster    = google_container_cluster.primary.name
  node_count = 1

  autoscaling {
    min_node_count = 1
    max_node_count = 2
  }

  node_config {
    preemptible  = true
    machine_type = "e2-medium"
    disk_size_gb = 30
    disk_type    = "pd-standard"

    service_account = google_service_account.gke_node_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]

    tags = ["restricted", "gke-node", "load-balanced"]

    shielded_instance_config {
      enable_secure_boot = true
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# ==================== MANAGEMENT VM ====================

resource "google_compute_instance" "management_vm" {
  name         = "management-vm"
  machine_type = "e2-medium"
  zone         = "${var.region}-b"
  allow_stopping_for_update = true
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.management_subnet.name
  }

  service_account {
    email = "default"
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  tags = ["management", "ssh-enabled"]

  metadata = {
    enable-oslogin = "true"
  }
}

# ==================== ARTIFACT REGISTRY ====================

data "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "gcp-docker-repo"
  depends_on    = [google_artifact_registry_repository.docker_repo_create]
}

resource "google_artifact_registry_repository" "docker_repo_create" {
  count         = 0
  location      = var.region
  repository_id = "gcp-docker-repo"
  description   = "Private Docker repository for GCP infrastructure"
  format        = "DOCKER"

  docker_config {
    immutable_tags = false
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes = all  
  }
}
