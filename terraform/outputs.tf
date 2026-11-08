output "cms_url" {
  description = "URL del servicio Cloud Run; null si enable_gcp=false."
  value       = var.enable_gcp ? google_cloud_run_v2_service.cms[0].uri : null
}

output "uploads_bucket" {
  description = "Bucket de archivos; null si enable_gcp=false."
  value       = var.enable_gcp ? google_storage_bucket.uploads[0].name : null
}
