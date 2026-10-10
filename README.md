# Personal infrastructure

Terraform for the cloud side of my homelab and personal projects, all in AWS (`eu-west-2`):

* DNS for elliotpryde.com: the hosted zone and Proton Mail records. The `*.elliotpryde.com` record for services on the
  NAS is kept up to date by the ddns_updater container on the NAS, not by Terraform
* Route 53 health checks for NAS services (currently switched off)
* Uptime monitoring for NAS services (`Terraform/uptime-monitoring.tf`): a Lambda probes each service every minute,
  a CloudWatch alarm alerts through ntfy.sh and email, and a public function URL serves a 7-day uptime chart for Dashy.
  The Lambda code is in `tools/` and is deployed separately from Terraform. A kill switch
  (`Terraform/uptime-cost-guard.tf`) pauses the probe and the public chart if the function URL is abused or the
  account goes over budget
* An IAM user that lets Traefik on the NAS complete Let's Encrypt DNS challenges
* A monthly AWS budget with email alerts
* The S3 state bucket and GitHub Actions OIDC roles used to run this Terraform (`Terraform/ci.tf`)

## How changes are applied

Everything goes through pull requests against `master`:

1. Opening or updating a pull request runs `terraform fmt`, `validate`, `tflint` and `plan`, and posts the plan as a
   single comment on the pull request that is updated on every push.
2. Merging applies it. The `apply` job runs in the `production` GitHub environment, the only thing allowed to assume the
   apply role.

GitHub Actions logs in to AWS with OIDC, so there are no AWS access keys stored in GitHub. State lives in the
`elliotpryde-terraform-state` S3 bucket, locked with an S3 lock file.

To run Terraform locally, use your own AWS credentials, set the `TF_VAR_*` variables listed in
`.github/workflows/terraform.yml`, then `cd Terraform && terraform init && terraform plan`.

## Lambda functions

Each directory in [`tools/`](tools) is a Go module for the Lambda function of the same name. Terraform creates the
functions with placeholder code and ignores code changes, and
[`.github/workflows/lambdas.yml`](.github/workflows/lambdas.yml) deploys the code instead, so infrastructure and code ship
through separate pipelines. Pull requests build and test every function. Merging deploys the ones whose directory changed,
using the `github-lambda-deploy` role, which can only update these functions' code. Run the workflow by hand to redeploy
them all.

The uptime monitoring functions:

* `uptime-kill-switch` pauses `health-probe` and `uptime-status` if `uptime-status` is requested more than 300 times
  in 5 minutes, or the account goes over its monthly budget. Both publish to the `uptime-cost-guard` topic, which
  triggers the kill switch and `alert-notifier`. The kill switch sets the two functions' reserved concurrency to 0 and
  disables the probe schedule and the uptime alarm's actions. To resume, run the Terraform workflow by hand: the plan
  shows the pause as drift, and applying it restores everything. The kill switch confirms both on the `uptime-alerts`
  topic: "Kill switch activated" once a pause has fully worked, and "Kill switch deactivated" from the check the
  Terraform workflow runs after every apply.

## One-off setup

GitHub Actions can't create the AWS resources it needs to log in, so these steps were done by hand once. They're kept
for reference.

1. **Bootstrap AWS.** In AWS CloudShell (`eu-west-2`), run [`bootstrap/bootstrap.sh`](bootstrap/bootstrap.sh). It
   creates the state bucket, the GitHub OIDC provider and the plan and apply roles, then prints the values for step 2.
   Terraform took those resources over on its first apply, so later changes to them belong in `ci.tf`.
2. **GitHub → Settings → Secrets and variables → Actions:** set the secrets and variables the script printed. Add the
   two secrets under **Secrets and variables → Dependabot** too, because Dependabot pull requests can't read Actions
   secrets.
3. **GitHub → Settings → Environments:** create `production`, with deployment branches limited to `master`.
4. **GitHub → Settings → Branches:** protect `master`. Require a pull request, require the `plan` status check, and
   require branches to be up to date before merging, so the plan on the pull request is the plan that gets applied.
5. **GitHub → Settings → Actions → General:** require approval for workflows from all outside contributors.
6. **GitHub → Settings → Secrets and variables → Actions:** set the `AWS_LAMBDA_DEPLOY_ROLE_ARN` variable to the
   `github-lambda-deploy-role-arn` Terraform output.
7. **Email:** click the link in the "AWS Notification - Subscription Confirmation" email, so uptime alerts are emailed
   too.

The state used to live in Terraform Cloud. Rather than migrating it, the existing AWS resources were imported into fresh
S3 state with import blocks on the first apply from GitHub Actions. The old Terraform Cloud workspace and the Azure
account (which still holds a budget alert and some unused resources from old NAS backups) are no longer used by this
repository and can be deleted or closed at any time.
