module "app_subnet" {
  source        = "./modules/subnet"
  name          = "app-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "asia-east1"
  network       = "projects/demo/global/networks/vpc"
}