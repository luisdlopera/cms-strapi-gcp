locals {
  apis = [
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ]
  secret_names = [
    "APP_KEYS",
    "API_TOKEN_SALT",
    "ADMIN_JWT_SECRET",
    "TRANSFER_TOKEN_SALT",
    "JWT_SECRET",
    "ENCRYPTION_KEY",
    "DB_PASSWORD",
  ]
}

resource "google_project_service" "apis" {
  for_each           = var.enable_gcp ? toset(local.apis) : toset([])
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "cms" {
  count         = var.enable_gcp ? 1 : 0
  project       = var.project_id
  location      = var.region
  repository_id = "cms"
  description   = "Imágenes de contenedor del CMS Strapi"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

resource "google_storage_bucket" "uploads" {
  count                       = var.enable_gcp ? 1 : 0
  project                     = var.project_id
  name                        = "${var.project_id}-cms-uploads"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false
  depends_on                  = [google_project_service.apis]
}

resource "google_sql_database_instance" "cms" {
  count               = var.enable_gcp ? 1 : 0
  project             = var.project_id
  name                = "cms-postgres"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"
    disk_type         = "PD_HDD"
    disk_size         = 10
    disk_autoresize   = false

    backup_configuration {
      enabled                        = false
      point_in_time_recovery_enabled = false
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_sql_database" "cms" {
  count    = var.enable_gcp ? 1 : 0
  project  = var.project_id
  name     = var.database_name
  instance = google_sql_database_instance.cms[0].name
}

resource "google_sql_user" "cms" {
  count    = var.enable_gcp ? 1 : 0
  project  = var.project_id
  name     = var.database_user
  instance = google_sql_database_instance.cms[0].name
  password = var.secret_values["DB_PASSWORD"]
}

resource "google_secret_manager_secret" "cms" {
  for_each  = var.enable_gcp ? toset(local.secret_names) : toset([])
  project   = var.project_id
  secret_id = "cms-${lower(replace(each.value, "_", "-"))}"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "cms" {
  for_each    = var.enable_gcp ? toset(local.secret_names) : toset([])
  secret      = google_secret_manager_secret.cms[each.value].id
  secret_data = var.secret_values[each.value]
}

resource "google_service_account" "cms" {
  count        = var.enable_gcp ? 1 : 0
  project      = var.project_id
  account_id   = "strapi-cms"
  display_name = "Identidad de ejecución de Strapi"
}

resource "google_project_iam_member" "cloud_sql_client" {
  count   = var.enable_gcp ? 1 : 0
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cms[0].email}"
}

resource "google_storage_bucket_iam_member" "uploads_writer" {
  count  = var.enable_gcp ? 1 : 0
  bucket = google_storage_bucket.uploads[0].name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.cms[0].email}"
}

resource "google_secret_manager_secret_iam_member" "cms_access" {
  for_each  = var.enable_gcp ? toset(local.secret_names) : toset([])
  project   = var.project_id
  secret_id = google_secret_manager_secret.cms[each.value].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cms[0].email}"
}

resource "google_cloud_run_v2_service" "cms" {
  count               = var.enable_gcp ? 1 : 0
  project             = var.project_id
  name                = "cms-strapi"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.cms[0].email

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.cms[0].connection_name]
      }
    }

    volumes {
      name = "uploads"
      gcs {
        bucket    = google_storage_bucket.uploads[0].name
        read_only = false
      }
    }

    containers {
      image = var.container_image

      ports {
        container_port = 1337
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "HOST"
        value = "0.0.0.0"
      }
      env {
        name  = "DATABASE_CLIENT"
        value = "postgres"
      }
      env {
        name  = "DATABASE_HOST"
        value = "/cloudsql/${google_sql_database_instance.cms[0].connection_name}"
      }
      env {
        name  = "DATABASE_NAME"
        value = var.database_name
      }
      env {
        name  = "DATABASE_USERNAME"
        value = var.database_user
      }
      env {
        name = "DATABASE_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.cms["DB_PASSWORD"].secret_id
            version = "latest"
          }
        }
      }

      dynamic "env" {
        for_each = setsubtract(toset(local.secret_names), toset(["DB_PASSWORD"]))
        content {
          name = env.value
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.cms[env.value].secret_id
              version = "latest"
            }
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      volume_mounts {
        name       = "uploads"
        mount_path = "/opt/app/public/uploads"
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_sql_user.cms,
    google_secret_manager_secret_version.cms,
    google_project_iam_member.cloud_sql_client,
    google_storage_bucket_iam_member.uploads_writer,
    google_secret_manager_secret_iam_member.cms_access,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.enable_gcp ? 1 : 0
  project  = var.project_id
  location = google_cloud_run_v2_service.cms[0].location
  name     = google_cloud_run_v2_service.cms[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
