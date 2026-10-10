# Personal infrastructure

Terraform for the cloud side of my homelab and personal projects, all in AWS (`eu-west-2`):

* DNS for elliotpryde.com, including Proton Mail records and the wildcard record for services on the NAS
* Route 53 health checks for NAS services
* An IAM user that lets Traefik on the NAS complete Let's Encrypt DNS challenges
* A monthly AWS budget with email alerts
* The S3 state bucket and GitHub Actions OIDC roles used to run this Terraform (`Terraform/ci.tf`)

The Azure subscription still has a £1 budget alert that is no longer managed here. It goes away when the Azure account
is closed.

## How changes are applied

Everything goes through pull requests against `master`:

1. Opening or updating a pull request runs `terraform fmt`, `validate`, `tflint` and `plan`, and posts the plan as a
   single comment on the pull request that is updated on every push.
2. Merging applies it. The `apply` job runs in the `production` GitHub environment, the only thing allowed to assume the
   apply role.

GitHub Actions authenticates to AWS with OIDC (`Terraform/ci.tf`), so there are no AWS access keys stored in GitHub.
State lives in the `elliotpryde-terraform-state` S3 bucket, locked with an S3 lock file.

To run Terraform locally, use your own AWS credentials, set the `TF_VAR_*` variables listed in
`.github/workflows/terraform.yml`, then `cd Terraform && terraform init && terraform plan`.

## One-off setup

These steps only needed doing once, when this repository moved off Terraform Cloud. They're kept for reference.

### GitHub settings

* **Environments → `production`**: deployment branches and tags limited to `master`.
* **Secrets and variables → Actions**:
  * Secrets: `TF_VAR_MY_EMAIL_ADDRESS`, `TF_VAR_NAS_PUBLIC_IP`, `TF_VAR_PROTONMAIL_ELLIOTPRYDE_COM_VERIFICATION_STRING`.
    Add the same three under **Secrets and variables → Dependabot** too, because Dependabot pull requests can't read
    Actions secrets.
  * Variables: `TF_VAR_DISABLE_ALL_HEALTH_CHECKS` (`true` or `false`), plus `AWS_PLAN_ROLE_ARN` and
    `AWS_APPLY_ROLE_ARN` from the `github-terraform-*-role-arn` Terraform outputs.
* **Branch protection on `master`**: require a pull request, require the `plan` status check, and require branches to
  be up to date before merging, so the plan on the pull request is the plan that gets applied.
* **Actions → General**: require approval for workflows from all outside contributors.

### Migrating state from Terraform Cloud

1. In Terraform Cloud, disconnect the workspace from version control so merges stop triggering runs there.
2. Check out the branch that switches to the S3 backend, then run `terraform login`, and from `Terraform/` run
   `terraform init -migrate-state`, answering yes to copy the state to S3.
3. Run `terraform plan` locally and check it reports no changes.
4. Merge. After the first successful apply from GitHub Actions, delete the Terraform Cloud workspace and the IAM user
   whose access keys Terraform Cloud used.
