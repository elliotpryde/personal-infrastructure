# Proton Mail records. These used to come from the protonmail-domain module, whose relative record names ("", "_dmarc")
# don't match the full names Route 53 records are imported with, which would have forced them to be recreated.
locals {
  email_ttl = 300
}

resource "aws_route53_record" "protonmail-verify-and-spf" {
  zone_id = aws_route53_zone.elliotpryde-com.zone_id
  name    = aws_route53_zone.elliotpryde-com.name
  type    = "TXT"
  ttl     = local.email_ttl

  records = [
    var.protonmail_elliotpryde_com_verification_string,
    "v=spf1 include:_spf.protonmail.ch mx ~all"
  ]
}

resource "aws_route53_record" "protonmail-mx" {
  zone_id = aws_route53_zone.elliotpryde-com.zone_id
  name    = aws_route53_zone.elliotpryde-com.name
  type    = "MX"
  ttl     = local.email_ttl

  records = [
    "10 mail.protonmail.ch",
    "20 mailsec.protonmail.ch"
  ]
}

resource "aws_route53_record" "protonmail-dkim" {
  count   = length(local.dkim_records)
  zone_id = aws_route53_zone.elliotpryde-com.zone_id
  name    = "${local.dkim_records[count.index].hostname}.${aws_route53_zone.elliotpryde-com.name}"
  type    = "CNAME"
  ttl     = local.email_ttl

  records = [
    local.dkim_records[count.index].data
  ]
}

resource "aws_route53_record" "protonmail-dmarc" {
  zone_id = aws_route53_zone.elliotpryde-com.zone_id
  name    = "_dmarc.${aws_route53_zone.elliotpryde-com.name}"
  type    = "TXT"
  ttl     = local.email_ttl

  # the trailing space matches the record as it exists today
  records = ["v=DMARC1; p=none; "]
}
