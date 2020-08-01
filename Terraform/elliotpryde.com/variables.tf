locals {
  dns_ttl = 120
  dkim_records = [
    {
      hostname = "protonmail._domainkey",
      data     = "protonmail.domainkey.d4zotdvax2nt4447zdfl5bkm6uc3lozcidvlw5jdxq3hhurmq3u5q.domains.proton.ch."
    },
    {
      hostname = "protonmail2._domainkey",
      data     = "protonmail2.domainkey.d4zotdvax2nt4447zdfl5bkm6uc3lozcidvlw5jdxq3hhurmq3u5q.domains.proton.ch."
    },
    {
      hostname = "protonmail3._domainkey",
      data     = "protonmail3.domainkey.d4zotdvax2nt4447zdfl5bkm6uc3lozcidvlw5jdxq3hhurmq3u5q.domains.proton.ch."
    }
  ]
}

variable "nas_public_ip" {
  type        = string
  description = "The public IP address of my NAS"
}

variable "protonmail_elliotpryde_com_verification_string" {
  type        = string
  description = "The domain verification data provided at https://mail.protonmail.com/domains"
}
