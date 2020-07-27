locals {
  cloudflare_ttl = 120
}

variable "nas_public_ip" {
  type        = string
  description = "The public IP address of my NAS"
}
