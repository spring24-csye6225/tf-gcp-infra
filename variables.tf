variable "service_key_path" {
  description = "Path to the service key JSON file"
  type        = string
  default     = "/Users/vakitisaikumarreddy/Downloads/TerraformConfig/csye6225-spring-e2cbfe24ab49.json"
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
  default     = "csye6225-spring"
}

variable "webapp_subnet_cidr" {
  description = "CIDR range for the webapp subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "db_subnet_cidr" {
  description = "CIDR range for the database subnet"
  type        = string
  default     = "10.0.2.0/24"
}
