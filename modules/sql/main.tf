###############################################################
# MODULE: CLOUD SQL
# - MySQL 8.0 (db-f1-micro = cheapest / free trial eligible)
# - Private IP only (no public exposure)
# - Private Services Access peering with VPC
###############################################################

# ── Private Services Access (required for private IP SQL) ─────
resource "google_compute_global_address" "private_ip_range" {
  project       = var.project_id
  name          = "google-managed-services-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.private_network
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.private_network
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# ── Cloud SQL MySQL Instance ───────────────────────────────────
resource "google_sql_database_instance" "mysql" {
  project             = var.project_id
  name                = "ratnapal-mysql3"
  region              = var.region
  database_version    = "MYSQL_8_0"
  deletion_protection = false # set true in production

  settings {
    tier              = "db-f1-micro" # Smallest/cheapest tier
    availability_type = "ZONAL"       # single zone = cheaper (no HA)
    disk_size         = 10            # 10 GB minimum
    disk_type         = "PD_HDD"     # HDD cheaper than SSD

    backup_configuration {
      enabled            = false # disable automated backups to save cost
      binary_log_enabled = false
    }

    ip_configuration {
      ipv4_enabled    = false          # no public IP
      private_network = var.private_network
    }

    database_flags {
      name  = "character_set_server"
      value = "utf8mb4"
    }
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# ── Database ──────────────────────────────────────────────────
resource "google_sql_database" "app_db" {
  project  = var.project_id
  name     = "appdb"
  instance = google_sql_database_instance.mysql.name
}

# ── Root User ─────────────────────────────────────────────────
resource "google_sql_user" "root" {
  project  = var.project_id
  name     = "root"
  instance = google_sql_database_instance.mysql.name
  password = var.db_password
  host     = "%"
}
