#!/usr/bin/env bash
# =============================================================================
# destroy.sh — Clean teardown of all resources
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will destroy ALL infrastructure!     ║${NC}"
echo -e "${RED}║  EKS cluster, VPC, ECR, Jenkins — everything.       ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
read -p "Type 'destroy' to confirm: " CONFIRM
[[ "${CONFIRM}" != "destroy" ]] && echo "Aborted." && exit 0

cd "$(dirname "$0")/../terraform"

echo -e "${YELLOW}[1/4] Removing Kubernetes resources...${NC}"
kubectl delete namespace application --ignore-not-found=true 2>/dev/null || true
kubectl delete namespace jenkins --ignore-not-found=true 2>/dev/null || true

echo -e "${YELLOW}[2/4] Removing Helm releases...${NC}"
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
helm uninstall jenkins -n jenkins 2>/dev/null || true

echo -e "${YELLOW}[3/4] Cleaning ECR images...${NC}"
ECR_REPO=$(terraform output -raw ecr_repository_name 2>/dev/null || echo "")
if [ -n "${ECR_REPO}" ]; then
    IMAGES=$(aws ecr list-images --repository-name "${ECR_REPO}" --query 'imageIds[*]' --output json 2>/dev/null || echo "[]")
    if [ "${IMAGES}" != "[]" ]; then
        aws ecr batch-delete-image --repository-name "${ECR_REPO}" --image-ids "${IMAGES}" 2>/dev/null || true
    fi
fi

echo -e "${YELLOW}[4/4] Destroying Terraform resources...${NC}"
terraform destroy -auto-approve

echo -e "\n${RED}All resources destroyed.${NC}"
