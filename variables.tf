variable "service_key_path" {
  description = "Path to the service key JSON file"
  type        = string
  default     = "/Users/vakitisaikumarreddy/Downloads/vakiti-dev-c00eff790fae.json"
}

variable "region" {
  description = "GCP region name"
  type        = string
  default     = "us-central1"
}

variable "vpc_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "custom-vpc"
}

variable "project_name" {
  description = "GCP project name"
  type        = string
  default     = "vakiti-dev"
}

variable "webapp_subnet_cidr" {
  description = "CIDR range for the webapp subnet"
  type        = string
  default     = "10.0.1.0/24" // Example update - Adjust as needed
}

variable "db_subnet_cidr" {
  description = "CIDR range for the database subnet"
  type        = string
  default     = "10.0.2.0/24" // Example update - Adjust as needed
}

variable "vm_name" {
  description = "VM Instance Name"
  type        = string
  default     = "web-server"
}
variable "zone" {
  description = "VM Instance Zone"
  type        = string
  default     = "us-central1-a"
}
variable "machine_type" {
  description = "VM Machine Type"
  type        = string
  default     = "e2-medium"
}
variable "image" {
  description = "Image file path"
  type        = string
  default     = "projects/vakiti-dev/global/images/my-app-image-1708559725"
}
variable "boot_disk_size" {
  description = "Boot Disk Size"
  type        = number
  default     = 20
}
variable "boot_disk_type" {
  description = "Boot Disk Type"
  type        = string
  default     = "pd-balanced"
}

variable "routing_mode" {
  description = "routing mode"
  type        = string
  default     = "REGIONAL"
}
