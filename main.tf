provider "google" {
  credentials = file(var.service_key_path)
  project     = var.project_name
  region      = var.region
}

resource "google_compute_network" "vpc_network" {
  name                            = var.vpc_name
  auto_create_subnetworks         = false
  routing_mode                    = var.routing_mode
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "webapp_subnet" {
  name          = "webapp"
  region        = var.region
  ip_cidr_range = var.webapp_subnet_cidr
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_subnetwork" "db_subnet" {
  name          = "db"
  region        = var.region
  ip_cidr_range = var.db_subnet_cidr
  network       = google_compute_network.vpc_network.self_link
}

resource "google_compute_route" "webapp_route" {
  name             = var.route_name
  dest_range       = var.dest_range
  network          = google_compute_network.vpc_network.self_link
  next_hop_gateway = var.next_hop_gateway
}

resource "google_compute_global_address" "default" {
  provider      = google
  project       = var.project_name
  name          = var.global_address_name
  address_type  = var.address_type
  purpose       = var.address_purpose
  prefix_length = var.prefix_length
  network       = google_compute_network.vpc_network.id
}

# Random Password Generation
resource "random_password" "database_password" {
  length           = 16
  special          = true
  override_special = "_%@"
}

resource "google_service_networking_connection" "my_service_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = var.service
  reserved_peering_ranges = [google_compute_global_address.default.name]
}

resource "google_compute_instance" "my-web-server" {
  name                      = var.vm_name
  zone                      = var.zone
  machine_type              = var.machine_type
  tags                      = ["web-server"]
  allow_stopping_for_update = true

  metadata = {
    db_host     = google_sql_database_instance.primary_instance.ip_address[0].ip_address
    db_user     = google_sql_user.webapp_user.name
    db_password = random_password.database_password.result
  }
  metadata_startup_script = file("startup.sh")

  boot_disk {
    auto_delete = true
    device_name = var.vm_name
    initialize_params {
      image = var.image
      size  = var.boot_disk_size
      type  = var.boot_disk_type
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.webapp_subnet.name
    access_config {
      network_tier = "PREMIUM"
    }
  }

  service_account {
    email  = google_service_account.app_service_account.email
    scopes = ["https://www.googleapis.com/auth/logging.admin", "https://www.googleapis.com/auth/monitoring.write"]
  }
}

resource "google_sql_database_instance" "primary_instance" {
  name                = var.sql_instance_name
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = false
  depends_on          = [google_service_networking_connection.my_service_connection]

  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }
  }
}

resource "google_sql_database" "webapp_database" {
  name     = var.sql_db_name
  instance = google_sql_database_instance.primary_instance.name
}

resource "google_sql_user" "webapp_user" {
  name     = var.user_name
  instance = google_sql_database_instance.primary_instance.name
  password = random_password.database_password.result
  host     = "%"
}

resource "google_compute_firewall" "allow-web-traffic" {
  name        = var.firewall_name
  network     = google_compute_network.vpc_network.name
  description = "Allow HTTP traffic to instances with the 'web-server' tag"

  allow {
    protocol = "tcp"
    ports    = var.http_ports
  }

  target_tags   = ["web-server"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_dns_record_set" "your_domain_a_record" {
  name         = "ns1.csye6225-vakiti.me."
  managed_zone = "csye6225-vakiti"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_instance.my-web-server.network_interface[0].access_config[0].nat_ip]
}

# resource "google_dns_managed_zone" "your_dns_zone" {
#   name     = "csye6225-vakiti"
#   dns_name = "csye6225-vakiti.me."
# }

resource "google_service_account" "app_service_account" {
  account_id   = "app-service-account"
  display_name = "Service Account for my Application"
}

resource "google_project_iam_member" "logging_admin_role" {
  project = google_service_account.app_service_account.project
  role    = "roles/logging.admin"
  member  = "serviceAccount:${google_service_account.app_service_account.email}"
}

resource "google_project_iam_member" "monitoring_metric_writer_role" {
  project = google_service_account.app_service_account.project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.app_service_account.email}"
}

