resource "google_compute_subnetwork" "no_flow_logs" {
  name          = "app-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"
}

resource "google_compute_subnetwork" "with_flow_logs" {
  name          = "app-subnet-2"
  ip_cidr_range = "10.0.2.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
  }

  private_ip_google_access = true # .tf 布林值只能用小寫
}

resource "google_compute_subnetwork" "commit" {
    #checkov:skip=CKV_GCP_26:test_vpc
  name          = "app-subnet-3"
  ip_cidr_range = "10.0.1.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"
}