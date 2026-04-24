output "sql_private_ip" {
  value = google_sql_database_instance.mysql.private_ip_address
}

output "sql_instance_name" {
  value = google_sql_database_instance.mysql.name
}

output "database_name" {
  value = google_sql_database.app_db.name
}
