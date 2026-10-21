resource "google_compute_firewall" "default" {
  name    = "test-firewall1"
  network = google_compute_network.default.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["web1"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "default2" {
  name    = "test-firewall2"
  network = google_compute_network.default.name

   allow {
    protocol = "tcp"
  }

  source_tags = ["web2"]
  source_ranges = ["0.0.0.0/0"]
}