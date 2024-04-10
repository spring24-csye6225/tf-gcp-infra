provider "google" {
  credentials = file(var.service_key_path)
  project     = var.project_name
  region      = var.region
}

provider "google-beta" {
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

resource "google_kms_key_ring" "my_key_ring1" {
  name     = "my-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "my_vm_cmek" {
  name            = "my-vm-key"
  key_ring        = google_kms_key_ring.my_key_ring1.id
  rotation_period = "2592000s"
}

resource "google_kms_crypto_key" "cloudsql_key" {
  name            = "cloudsql-key"
  key_ring        = google_kms_key_ring.my_key_ring1.id
  rotation_period = "2592000s"
}

resource "google_kms_crypto_key" "storage_bucket_key" {
  name            = "storage-bucket-key"
  key_ring        = google_kms_key_ring.my_key_ring1.id
  rotation_period = "2592000s"
}

resource "google_compute_region_instance_template" "webapp_template" {
  name_prefix  = "webapp-template-"
  machine_type = var.machine_type

  metadata = {
    db_host     = google_sql_database_instance.primary_instance.ip_address[0].ip_address
    db_user     = google_sql_user.webapp_user.name
    db_password = random_password.database_password.result
  }
  metadata_startup_script = file("startup.sh")

  disk {
    source_image = var.image
    auto_delete  = true
    boot         = true
    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.my_vm_cmek.id
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.webapp_subnet.name
  }

  service_account {
    email = google_service_account.app_service_account.email
    scopes = [
      "https://www.googleapis.com/auth/logging.admin",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/pubsub",
      "https://www.googleapis.com/auth/cloudkms"
    ]
  }


  tags = ["web-server"]
}

data "google_project" "project" {}


resource "google_kms_crypto_key_iam_binding" "kms_vm_binding" {
  crypto_key_id = google_kms_crypto_key.my_vm_cmek.id
  role          = "roles/owner"

  members = [
    "serviceAccount:service-${data.google_project.project.number}@compute-system.iam.gserviceaccount.com"
  ]
}

resource "google_kms_crypto_key_iam_binding" "kms_storage_binding" {
  crypto_key_id = google_kms_crypto_key.storage_bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
  ]
}

resource "google_kms_crypto_key_iam_binding" "kms_sql_binding" {
  crypto_key_id = google_kms_crypto_key.cloudsql_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"

  members = [
    "serviceAccount:${google_project_service_identity.cloudsql_sa.email}"
  ]
}


resource "google_kms_key_ring_iam_binding" "key_ring_binding" {
  key_ring_id = google_kms_key_ring.my_key_ring1.id
  role        = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  members = [
    "serviceAccount:${google_project_service_identity.cloudsql_sa.email}",
    "serviceAccount:${google_service_account.app_service_account.email}",
    "serviceAccount:${data.google_storage_project_service_account.gcs_account.email_address}"
  ]
}

resource "google_sql_database_instance" "primary_instance" {
  name                = var.sql_instance_name
  database_version    = "MYSQL_8_0"
  region              = var.region
  deletion_protection = false
  depends_on          = [google_service_networking_connection.my_service_connection]
  encryption_key_name = google_kms_crypto_key.cloudsql_key.id
  settings {
    tier = "db-f1-micro"

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc_network.id
    }

  }
}

resource "google_project_service_identity" "cloudsql_sa" {
  provider = google-beta
  project  = var.project_name
  service  = "sqladmin.googleapis.com"
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
  source_ranges = [google_compute_global_forwarding_rule.webapp_forwarding_rule.ip_address, "35.191.0.0/16", "130.211.0.0/22"]
}

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

resource "google_project_iam_member" "pubsub_publisher_role" {
  project = google_service_account.app_service_account.project
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.app_service_account.email}"
}


resource "google_pubsub_topic" "user_verification" {
  name = "verify_email"
}


resource "google_pubsub_subscription" "user_verification_subscription" {
  name  = "user-verification-subscription"
  topic = google_pubsub_topic.user_verification.name

  ack_deadline_seconds       = 20
  message_retention_duration = "604800s" # 7 days
}

resource "google_storage_bucket" "function_code_bucket" {
  name          = "my-function-code-bucket-vakiti"
  location      = var.region
  force_destroy = true
  encryption {
    default_kms_key_name = google_kms_crypto_key.storage_bucket_key.id
  }


}

resource "google_storage_bucket_object" "function_code" {
  name   = "user_verification_function.zip"
  source = "function.zip"
  bucket = google_storage_bucket.function_code_bucket.name
}

resource "google_vpc_access_connector" "my_connector" {
  name          = "my-vpc-connector"
  region        = var.region
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = "10.8.0.0/28"
}


resource "google_cloudfunctions_function" "user_verification" {
  name                  = "verify_email"
  region                = var.region
  source_archive_bucket = google_storage_bucket.function_code_bucket.name
  source_archive_object = google_storage_bucket_object.function_code.name
  runtime               = "python39"
  available_memory_mb   = 128
  vpc_connector         = google_vpc_access_connector.my_connector.name

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.user_verification.id
  }

  environment_variables = {
    DB_USER            = google_sql_user.webapp_user.name
    DB_PASSWORD        = random_password.database_password.result
    DB_NAME            = google_sql_database.webapp_database.name
    DB_HOST            = google_sql_database_instance.primary_instance.ip_address[0].ip_address
    MAILGUN_API_KEY    = var.mailgun_api_key
    MAILGUN_DOMAIN     = var.mailgun_domain
    DB_CONNECTION_NAME = google_sql_database_instance.primary_instance.connection_name
  }
}

# Existing resources like VPC, subnets, database, and others remain the same.


# Create a Health Check
resource "google_compute_health_check" "webapp_health_check" {
  name = "webapp-health-check"
  http_health_check {
    port         = 8080
    request_path = "/healthz"
  }
  unhealthy_threshold = 5
}

# Create an Autoscaler
resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  name   = "webapp-autoscaler"
  target = google_compute_region_instance_group_manager.webapp_manager.id
  autoscaling_policy {
    max_replicas = 6
    min_replicas = 3
    cpu_utilization {
      target = 0.05
    }
  }
}

# Create an Instance Group Manager
resource "google_compute_region_instance_group_manager" "webapp_manager" {
  name               = "webapp-manager"
  base_instance_name = "webapp"
  target_size        = 1

  version {
    name              = "v1"
    instance_template = google_compute_region_instance_template.webapp_template.self_link
  }

  named_port {
    name = "http"
    port = 8080
  }
}

resource "google_compute_backend_service" "webapp_backend_service" {
  name        = "webapp-backend-service"
  port_name   = "http"
  protocol    = "HTTP"
  timeout_sec = 10

  health_checks = [google_compute_health_check.webapp_health_check.id]

  backend {
    group = google_compute_region_instance_group_manager.webapp_manager.instance_group
  }
}

# Load Balancer Resources
resource "google_compute_managed_ssl_certificate" "webapp_ssl_cert" {
  name = "webapp-ssl-cert"
  managed {
    domains = ["ns1.csye6225-vakiti.me"]
  }
}

resource "google_compute_url_map" "webapp_url_map" {
  name            = "webapp-url-map"
  default_service = google_compute_backend_service.webapp_backend_service.id
}

resource "google_compute_target_https_proxy" "webapp_https_proxy" {
  name             = "webapp-https-proxy"
  url_map          = google_compute_url_map.webapp_url_map.id
  ssl_certificates = [google_compute_managed_ssl_certificate.webapp_ssl_cert.id]
}

resource "google_compute_global_forwarding_rule" "webapp_forwarding_rule" {
  name       = "webapp-http-forwarding-rule"
  target     = google_compute_target_https_proxy.webapp_https_proxy.id
  port_range = "443"
}

# Modify DNS record to point to the load balancer
resource "google_dns_record_set" "your_domain_a_record" {
  name         = "ns1.csye6225-vakiti.me."
  managed_zone = "csye6225-vakiti"
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_forwarding_rule.webapp_forwarding_rule.ip_address]
}

data "google_storage_project_service_account" "gcs_account" {
  project = var.project_name
}
