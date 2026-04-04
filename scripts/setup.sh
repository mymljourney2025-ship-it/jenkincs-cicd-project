#!/usr/bin/env bash
# =============================================================================
# setup.sh — One-shot setup for the Jenkins K8s Pipeline project
# Run this ONCE on your local machine before `terraform apply`
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# -------------------------------------------------------------------------
step "Checking Prerequisites"
# -------------------------------------------------------------------------

check_tool() {
    if command -v "$1" &>/dev/null; then
        log "$1 found: $($1 --version 2>&1 | head -1)"
    else
        err "$1 not found. Please install it first."
    fi
}

check_tool terraform
check_tool aws
check_tool kubectl
check_tool helm
check_tool docker

# -------------------------------------------------------------------------
step "Checking AWS Credentials"
# -------------------------------------------------------------------------

if aws sts get-caller-identity &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    log "Authenticated as account: ${ACCOUNT_ID} in region: ${REGION}"
else
    err "AWS credentials not configured. Run: aws configure"
fi

# -------------------------------------------------------------------------
step "Setting Up Terraform Backend (Optional)"
# -------------------------------------------------------------------------

read -p "Create S3 backend for Terraform state? (y/N): " CREATE_BACKEND
if [[ "${CREATE_BACKEND,,}" == "y" ]]; then
    BUCKET_NAME="terraform-state-${ACCOUNT_ID}-${REGION}"
    TABLE_NAME="terraform-lock"

    log "Creating S3 bucket: ${BUCKET_NAME}"
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" \
        $([ "${REGION}" != "us-east-1" ] && echo "--create-bucket-configuration LocationConstraint=${REGION}") \
        2>/dev/null || warn "Bucket already exists"

    aws s3api put-bucket-versioning \
        --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled

    aws s3api put-bucket-encryption \
        --bucket "${BUCKET_NAME}" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

    log "Creating DynamoDB table: ${TABLE_NAME}"
    aws dynamodb create-table \
        --table-name "${TABLE_NAME}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${REGION}" \
        2>/dev/null || warn "Table already exists"

    echo ""
    log "Update terraform/main.tf backend block with:"
    echo "    bucket         = \"${BUCKET_NAME}\""
    echo "    key            = \"jenkins-k8s-pipeline/terraform.tfstate\""
    echo "    region         = \"${REGION}\""
    echo "    dynamodb_table = \"${TABLE_NAME}\""
fi

# -------------------------------------------------------------------------
step "Preparing Terraform Variables"
# -------------------------------------------------------------------------

TFVARS_FILE="terraform/terraform.tfvars"
if [ ! -f "${TFVARS_FILE}" ]; then
    cp terraform/terraform.tfvars.example "${TFVARS_FILE}"
    # Auto-fill account-specific values
    sed -i "s/CHANGE_ME_IMMEDIATELY/$(openssl rand -base64 24 | tr -d '/+=' | head -c 20)/" "${TFVARS_FILE}"
    log "Created ${TFVARS_FILE} — EDIT THIS FILE before running terraform apply"
    warn "Especially change: jenkins_admin_pass, aws_region"
else
    log "${TFVARS_FILE} already exists"
fi

# -------------------------------------------------------------------------
step "Adding Helm Repos"
# -------------------------------------------------------------------------

helm repo add jenkins https://charts.jenkins.io 2>/dev/null || true
helm repo add eks    https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update
log "Helm repos updated"

# -------------------------------------------------------------------------
step "Setup Complete!"
# -------------------------------------------------------------------------

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Setup complete! Next steps:                        ║${NC}"
echo -e "${GREEN}║                                                     ║${NC}"
echo -e "${GREEN}║  1. Edit terraform/terraform.tfvars                 ║${NC}"
echo -e "${GREEN}║  2. cd terraform && terraform init                  ║${NC}"
echo -e "${GREEN}║  3. terraform plan -out=plan.out                    ║${NC}"
echo -e "${GREEN}║  4. terraform apply plan.out                        ║${NC}"
echo -e "${GREEN}║  5. Run: ./scripts/post-deploy.sh                   ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
