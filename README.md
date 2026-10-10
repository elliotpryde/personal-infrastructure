# Personal infrastructure

Terraform for the cloud side of my homelab and personal projects, all in AWS (`eu-west-2`):

* DNS for elliotpryde.com, including Proton Mail records and the wildcard record for services on the NAS
* Route 53 health checks for NAS services
* An IAM user that lets Traefik on the NAS complete Let's Encrypt DNS challenges
* A monthly AWS budget with email alerts
* The S3 state bucket and GitHub Actions OIDC roles used to run this Terraform (`Terraform/ci.tf`)

The Azure subscription still has a £1 budget alert that is no longer managed here. It goes away when the Azure account
is closed.
