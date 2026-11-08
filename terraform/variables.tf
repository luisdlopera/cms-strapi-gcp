variable "project_id" {
  description = "ID del proyecto de Google Cloud. Solo se consulta; no se crea el proyecto."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_gcp || length(var.project_id) >= 6
    error_message = "Define un project_id válido antes de habilitar recursos de GCP."
  }
}

variable "region" {
  description = "Región para Cloud Run, Cloud SQL y Cloud Storage."
  type        = string
  default     = "us-central1"
}

variable "enable_gcp" {
  description = "Opt-in explícito. Activarlo crea recursos facturables; dejar false para costo cero."
  type        = bool
  default     = false
}

variable "container_image" {
  description = "Imagen de Strapi en Artifact Registry, construida antes del despliegue."
  type        = string
  default     = "us-central1-docker.pkg.dev/PROJECT_ID/cms/strapi:latest"

  validation {
    condition     = !var.enable_gcp || !strcontains(var.container_image, "PROJECT_ID")
    error_message = "Al habilitar GCP, container_image debe apuntar a la imagen real de Strapi en Artifact Registry."
  }
}

variable "database_name" {
  type    = string
  default = "strapi"
}

variable "database_user" {
  type    = string
  default = "strapi_app"
}

variable "secret_values" {
  description = "Secretos de Strapi. Terraform state contendrá sus valores; no usar con state local compartido."
  type        = map(string)
  sensitive   = true
  default     = {}

  validation {
    condition = length(var.secret_values) == 0 || alltrue([
      for key in ["APP_KEYS", "API_TOKEN_SALT", "ADMIN_JWT_SECRET", "TRANSFER_TOKEN_SALT", "JWT_SECRET", "ENCRYPTION_KEY", "DB_PASSWORD"] : contains(keys(var.secret_values), key)
    ])
    error_message = "secret_values debe contener los seis secretos de Strapi y DB_PASSWORD, o permanecer vacío."
  }
}
