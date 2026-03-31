# Trusted Supply Chain demo — root module: APIs, Artifact Registry, KMS, Container Analysis,
# Binary Authorization (note + attestor + enforce policy), Secret Manager, GKE Autopilot.

terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  # Default Cloud Build worker for `gcloud builds submit` is often the Compute Engine default service account.
  compute_default_sa = "${data.google_project.current.number}-compute@developer.gserviceaccount.com"
  cloudbuild_sa      = "${data.google_project.current.number}@cloudbuild.gserviceaccount.com"

  cloud_build_worker_project_roles = toset([
    "roles/storage.objectAdmin",
    "roles/artifactregistry.writer",
    "roles/logging.logWriter",
    "roles/ondemandscanning.admin",
    "roles/cloudkms.viewer",
    "roles/binaryauthorization.attestorsViewer",
    "roles/binaryauthorization.policyViewer",
    "roles/containeranalysis.notes.editor",
    "roles/containeranalysis.occurrences.editor",
  ])

  services = toset([
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "containeranalysis.googleapis.com",
    "binaryauthorization.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "container.googleapis.com",
    "run.googleapis.com",
    "compute.googleapis.com",
    "ondemandscanning.googleapis.com",
  ])

  labels = {
    environment = var.environment
    demo        = "trusted-supply-chain"
  }
}

# Enable all APIs the demo touches (Cloud Build, AR, analysis, BinAuthz, SM, KMS, GKE, Run).
resource "google_project_service" "services" {
  for_each = local.services

  project            = var.project_id
  service            = each.key
  disable_on_destroy = false
}

# Docker repository for good-app / bad-app images built in CI.
resource "google_artifact_registry_repository" "supply_chain" {
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_repository_id
  description   = "Trusted supply chain demo — container images"
  format        = "DOCKER"

  labels = local.labels

  depends_on = [google_project_service.services]
}

# KMS key ring and asymmetric signing key used when creating Binary Authorization attestations.
resource "google_kms_key_ring" "binauthz" {
  project  = var.project_id
  name     = var.kms_keyring_name
  location = var.region

  depends_on = [google_project_service.services]
}

resource "google_kms_crypto_key" "signing" {
  name     = var.kms_crypto_key_name
  key_ring = google_kms_key_ring.binauthz.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm        = "RSA_SIGN_PKCS1_4096_SHA512"
    protection_level = "SOFTWARE"
  }

  labels = local.labels

  lifecycle {
    prevent_destroy = false
  }
}

# Read the primary key version so we can register the public key on the BinAuthz attestor.
data "google_kms_crypto_key_version" "signing" {
  crypto_key = google_kms_crypto_key.signing.id
}

# Container Analysis "note" — metadata Binary Authorization associates with your attestor.
resource "google_container_analysis_note" "attestation" {
  project = var.project_id
  name    = var.container_analysis_note_id

  short_description = "Demo attestation authority for pipeline-signed images"

  related_url {
    url   = "https://cloud.google.com/binary-authorization/"
    label = "Binary Authorization"
  }

  attestation_authority {
    hint {
      human_readable_name = "Demo pipeline attestor"
    }
  }

  depends_on = [google_project_service.services]
}

# Attestor ties the note to the KMS-backed public key used to verify signatures.
resource "google_binary_authorization_attestor" "demo" {
  project = var.project_id
  name    = var.attestor_id

  attestation_authority_note {
    note_reference = google_container_analysis_note.attestation.id
    public_keys {
      # Stable id for the KMS-backed public key (must not depend on unknown data during plan).
      id = "kms-signing-primary"
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.signing.public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.signing.public_key[0].algorithm
      }
    }
  }

  depends_on = [
    google_project_service.services,
    google_container_analysis_note.attestation,
  ]
}

# Project policy: require attestation for workloads not matched by system image whitelists below.
# Whitelists keep GKE Autopilot system pulls working; user images from Artifact Registry must be attested.
resource "google_binary_authorization_policy" "demo" {
  project = var.project_id

  global_policy_evaluation_mode = "ENABLE"

  admission_whitelist_patterns {
    name_pattern = "gcr.io/google_containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gcr.io/google-containers/*"
  }
  admission_whitelist_patterns {
    name_pattern = "gke.gcr.io/*"
  }
  admission_whitelist_patterns {
    name_pattern = "registry.k8s.io/*"
  }
  admission_whitelist_patterns {
    name_pattern = "k8s.gcr.io/*"
  }

  default_admission_rule {
    evaluation_mode  = "REQUIRE_ATTESTATION"
    enforcement_mode = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    # Use a plan-time-known name so the provider does not flip require_attestations_by from null mid-apply.
    require_attestations_by = [
      "projects/${var.project_id}/attestors/${var.attestor_id}",
    ]
  }

  depends_on = [
    google_binary_authorization_attestor.demo,
  ]
}

# Demo secret consumed by good-app on Cloud Run via --set-secrets (value is non-production dummy).
resource "google_secret_manager_secret" "db_credentials" {
  project   = var.project_id
  secret_id = "db-credentials"

  replication {
    auto {}
  }

  labels = local.labels

  depends_on = [google_project_service.services]
}

resource "google_secret_manager_secret_version" "db_credentials_v1" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = "super-secret-db-password"
}

# -----------------------------------------------------------------------------
# IAM: Cloud Build / `gcloud builds submit` (see variable grant_cloud_build_iam)
# -----------------------------------------------------------------------------

# Project-level roles for the default Compute Engine SA (typical build worker when submitting from gcloud).
resource "google_project_iam_member" "cloud_build_worker" {
  for_each = var.grant_cloud_build_iam ? local.cloud_build_worker_project_roles : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.compute_default_sa}"

  depends_on = [
    google_project_service.services["cloudbuild.googleapis.com"],
    google_project_service.services["compute.googleapis.com"],
  ]
}

# Lets the Cloud Build SA read/write Cloud Build source buckets used by `gcloud builds submit`.
resource "google_project_iam_member" "cloudbuild_storage_admin" {
  count = var.grant_cloud_build_iam ? 1 : 0

  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${local.cloudbuild_sa}"

  depends_on = [google_project_service.services["cloudbuild.googleapis.com"]]
}

# Least-privilege KMS: sign + view public key for attestations (in addition to project roles.cloudkms.viewer).
resource "google_kms_crypto_key_iam_member" "build_worker_kms_signer" {
  count = var.grant_cloud_build_iam ? 1 : 0

  crypto_key_id = google_kms_crypto_key.signing.id
  role          = "roles/cloudkms.signer"
  member        = "serviceAccount:${local.compute_default_sa}"
}

resource "google_kms_crypto_key_iam_member" "build_worker_kms_public_key" {
  count = var.grant_cloud_build_iam ? 1 : 0

  crypto_key_id = google_kms_crypto_key.signing.id
  role          = "roles/cloudkms.publicKeyViewer"
  member        = "serviceAccount:${local.compute_default_sa}"
}

# Cloud Run (default runtime SA) reads db-credentials when using --set-secrets without a custom service account.
resource "google_secret_manager_secret_iam_member" "compute_sa_db_credentials_accessor" {
  count = var.grant_cloud_build_iam ? 1 : 0

  secret_id = google_secret_manager_secret.db_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.compute_default_sa}"
}

# VPC for Autopilot (many projects omit the legacy default network).
resource "google_compute_network" "demo" {
  project                 = var.project_id
  name                    = var.vpc_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [google_project_service.services["compute.googleapis.com"]]
}

resource "google_compute_subnetwork" "demo" {
  project                    = var.project_id
  name                       = var.subnet_name
  region                     = var.region
  network                    = google_compute_network.demo.id
  ip_cidr_range              = "10.10.0.0/16"
  private_ip_google_access   = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.20.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.30.0.0/20"
  }
}

# GKE Autopilot: BinAuthz evaluates the project singleton policy above.
resource "google_container_cluster" "demo" {
  project  = var.project_id
  name     = var.gke_cluster_name
  location = var.region

  enable_autopilot = true

  network    = google_compute_network.demo.name
  subnetwork = google_compute_subnetwork.demo.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Private nodes avoid external IPs on worker VMs (required when org policy blocks vmExternalIpAccess).
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  binary_authorization {
    evaluation_mode = "PROJECT_SINGLETON_POLICY_ENFORCE"
  }

  deletion_protection = false

  depends_on = [
    google_project_service.services["container.googleapis.com"],
    google_binary_authorization_policy.demo,
    google_compute_subnetwork.demo,
  ]

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }
}
