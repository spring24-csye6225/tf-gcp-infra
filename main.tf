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
  name             = "webapp-internet-route"
  dest_range       = "0.0.0.0/0"
  network          = google_compute_network.vpc_network.self_link
  next_hop_gateway = "default-internet-gateway"
}

resource "google_compute_instance" "my-web-server" {
  name         = var.vm_name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["web-server"]

  boot_disk {
    auto_delete = true
    device_name = var.vm_name // Align device name 
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
      # Assign a public IP if needed (add a variable and make this conditional)
    }
  }
}

resource "google_compute_firewall" "allow-web-traffic" {
  name        = "allow-web-traffic"
  network     = google_compute_network.vpc_network.name
  description = "Allow HTTP traffic to instances with the 'web-server' tag"

  allow {
    protocol = "tcp"
    ports    = ["8080", "80"]
  }

  target_tags   = ["web-server"]
  source_ranges = ["0.0.0.0/0"]
}
