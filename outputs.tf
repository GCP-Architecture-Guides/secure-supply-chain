output "artifact_registry_repository" {
  description = "Artifact Registry repository id (Docker)."
  value       = google_artifact_registry_repository.supply_chain.repository_id
}

output "artifact_registry_location" {
  description = "Region where the Artifact Registry repository lives."
  value       = google_artifact_registry_repository.supply_chain.location
}

output "artifact_registry_docker_url_prefix" {
  description = "Prefix for docker push/pull: LOCATION-docker.pkg.dev/PROJECT/REPO/IMAGE:TAG"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.supply_chain.repository_id}"
}

output "kms_key_ring_id" {
  description = "Fully qualified KMS key ring resource id."
  value       = google_kms_key_ring.binauthz.id
}

output "kms_crypto_key_id" {
  description = "Fully qualified KMS crypto key id (signing)."
  value       = google_kms_crypto_key.signing.id
}

output "kms_crypto_key_version" {
  description = "Primary crypto key version number (usually 1 after create)."
  value       = data.google_kms_crypto_key_version.signing.version
}

output "container_analysis_note_id" {
  description = "Container Analysis note resource id."
  value       = google_container_analysis_note.attestation.id
}

output "binary_authorization_attestor_id" {
  description = "Full attestor resource name for gcloud and policies."
  value       = google_binary_authorization_attestor.demo.id
}

output "binary_authorization_attestor_name" {
  description = "Short attestor name (substitution _ATTESTOR)."
  value       = google_binary_authorization_attestor.demo.name
}

output "secret_db_credentials_id" {
  description = "Secret Manager secret id for db-credentials (not the value)."
  value       = google_secret_manager_secret.db_credentials.secret_id
}

output "gke_cluster_name" {
  description = "GKE Autopilot cluster name."
  value       = google_container_cluster.demo.name
}

output "gke_cluster_location" {
  description = "GKE cluster location (region)."
  value       = google_container_cluster.demo.location
}

output "gke_cluster_endpoint" {
  description = "GKE control plane endpoint (sensitive)."
  value       = google_container_cluster.demo.endpoint
  sensitive   = true
}

output "cloud_build_substitutions_hint" {
  description = "Suggested Cloud Build substitution values (copy into trigger or cloudbuild.yaml defaults)."
  value = {
    _AR_LOCATION   = var.region
    _REPOSITORY    = var.artifact_repository_id
    _KMS_LOCATION  = var.region
    _KEYRING       = var.kms_keyring_name
    _CRYPTO_KEY    = var.kms_crypto_key_name
    _KEY_VERSION   = try(tostring(data.google_kms_crypto_key_version.signing.version), "1")
    _ATTESTOR      = google_binary_authorization_attestor.demo.name
    _SCAN_LOCATION = "us"
  }
}

output "compute_default_service_account" {
  description = "Default Compute Engine SA email (typical worker for `gcloud builds submit`). IAM bound when grant_cloud_build_iam is true."
  value       = local.compute_default_sa
}

output "cloud_build_service_account" {
  description = "Cloud Build service account email (storage.admin for source buckets when grant_cloud_build_iam is true)."
  value       = local.cloudbuild_sa
}

output "grant_cloud_build_iam_enabled" {
  description = "Whether Terraform applied Cloud Build–related IAM bindings."
  value       = var.grant_cloud_build_iam
}
