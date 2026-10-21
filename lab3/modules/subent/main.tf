variable "name" {
  type = string
}

variable "ip_cidr_range" {
  type = string
}

variable "region" {
  type = string
}

variable "network" {
  type = string
}

resource "google_compute_subnetwork" "this" {
  name          = var.name
  ip_cidr_range = var.ip_cidr_range
  region        = var.region
  network       = var.network

  # 安全預設：一律啟用 Flow Logs
  # log_config {
  #   aggregation_interval = "INTERVAL_5_SEC"
  # }

  private_ip_google_access = true
}