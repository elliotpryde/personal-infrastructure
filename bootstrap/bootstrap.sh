#!/usr/bin/env bash
# One-off bootstrap for running this repository's Terraform from GitHub Actions.
#
# GitHub Actions can't create the AWS resources it needs to log in, so this creates them once:
#   * the S3 bucket holding Terraform state
#   * the GitHub Actions OIDC provider
#   * the github-terraform-plan and github-terraform-apply roles
# Terraform then takes them over (Terraform/ci.tf), so make changes there, not here.
#
# Run it in AWS CloudShell (eu-west-2), which is already logged in. Re-running it is safe: anything that already
# exists is left alone. At the end it prints the values to set as GitHub Actions secrets and variables.
set -euo pipefail

REGION="eu-west-2"
BUCKET="elliotpryde-terraform-state"
STATE_KEY="personal-infrastructure/terraform.tfstate"
REPO="elliotpryde/personal-infrastructure"
EXPECTED_ACCOUNT_ID="670785527082"
ZONE_ID="Z104083113ZEFTET5POA5"
OIDC_HOST="token.actions.githubusercontent.com"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$ACCOUNT_ID" != "$EXPECTED_ACCOUNT_ID" ]]; then
  echo "Logged in to account $ACCOUNT_ID, expected $EXPECTED_ACCOUNT_ID. Stopping." >&2
  exit 1
fi
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"

echo "== State bucket"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "$BUCKET already exists"
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
  echo "created $BUCKET"
fi
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "== GitHub Actions OIDC provider"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  echo "already exists"
else
  aws iam create-open-id-connect-provider --url "https://${OIDC_HOST}" --client-id-list sts.amazonaws.com >/dev/null
  echo "created"
fi

# trust_policy <OIDC subject>
trust_policy() {
  cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "${OIDC_ARN}"},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {"StringEquals": {
      "${OIDC_HOST}:aud": "sts.amazonaws.com",
      "${OIDC_HOST}:sub": "$1"
    }}
  }]
}
EOF
}

# ensure_role <name> <OIDC subject> <managed policy ARN>
ensure_role() {
  if aws iam get-role --role-name "$1" >/dev/null 2>&1; then
    echo "$1 already exists"
  else
    aws iam create-role --role-name "$1" --path /github/ --assume-role-policy-document "$(trust_policy "$2")" >/dev/null
    echo "created $1"
  fi
  aws iam attach-role-policy --role-name "$1" --policy-arn "$3"
}

echo "== Roles"
# plans run on pull requests: read-only, plus writing the state lock file
ensure_role github-terraform-plan "repo:${REPO}:pull_request" arn:aws:iam::aws:policy/ReadOnlyAccess
aws iam put-role-policy --role-name github-terraform-plan --policy-name terraform-state-lock --policy-document "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Effect\": \"Allow\",
    \"Action\": [\"s3:PutObject\", \"s3:DeleteObject\"],
    \"Resource\": \"arn:aws:s3:::${BUCKET}/${STATE_KEY}.tflock\"
  }]
}"
# applies run on merge, only from the GitHub "production" environment
ensure_role github-terraform-apply "repo:${REPO}:environment:production" arn:aws:iam::aws:policy/AdministratorAccess

# Values for the GitHub settings, read from what's live today
TXT_VALUES="$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='elliotpryde.com.' && Type=='TXT'].ResourceRecords[].Value" --output text)"
VERIFICATION="$(tr '\t' '\n' <<<"$TXT_VALUES" | tr -d '"' | grep -v '^v=spf1' || true)"
NAS_IP="$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='\\052.elliotpryde.com.' && Type=='A'].ResourceRecords[0].Value" --output text)"
HEALTH_CHECKS="$(aws route53 list-health-checks --query 'length(HealthChecks)' --output text)"
if [[ "$HEALTH_CHECKS" == "0" ]]; then DISABLE_HEALTH_CHECKS=true; else DISABLE_HEALTH_CHECKS=false; fi

cat <<EOF

Done. Now set these in GitHub, under Settings -> Secrets and variables -> Actions:

  Secrets (and the same three under Secrets and variables -> Dependabot):
    TF_VAR_MY_EMAIL_ADDRESS                               <the address budget alerts go to>
    TF_VAR_NAS_PUBLIC_IP                                  ${NAS_IP}
    TF_VAR_PROTONMAIL_ELLIOTPRYDE_COM_VERIFICATION_STRING ${VERIFICATION}

  Variables:
    TF_VAR_DISABLE_ALL_HEALTH_CHECKS                      ${DISABLE_HEALTH_CHECKS}  (${HEALTH_CHECKS} health checks exist today)
    AWS_PLAN_ROLE_ARN                                     arn:aws:iam::${ACCOUNT_ID}:role/github/github-terraform-plan
    AWS_APPLY_ROLE_ARN                                    arn:aws:iam::${ACCOUNT_ID}:role/github/github-terraform-apply
EOF
