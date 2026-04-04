#!/usr/bin/env bash
# =============================================================================
# post-deploy.sh — Run after `terraform apply` to finalize configuration
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
step() { echo -e "\n${CYAN}━━━ $1 ━━━${NC}"; }

# Get outputs from Terraform
cd "$(dirname "$0")/../terraform"
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)
AWS_REGION=$(terraform output -raw aws_region)
ECR_URL=$(terraform output -raw ecr_repository_url)
ACCOUNT_ID=$(terraform output -raw account_id)

# -------------------------------------------------------------------------
step "Configuring kubectl"
# -------------------------------------------------------------------------
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER}"
log "kubectl configured for cluster: ${EKS_CLUSTER}"

# -------------------------------------------------------------------------
step "Verifying Cluster"
# -------------------------------------------------------------------------
kubectl cluster-info
kubectl get nodes
log "Cluster is healthy"

# -------------------------------------------------------------------------
step "Installing AWS Load Balancer Controller"
# -------------------------------------------------------------------------
helm repo add eks https://aws.github.io/eks-charts 2>/dev/null || true
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
    --namespace kube-system \
    --set clusterName="${EKS_CLUSTER}" \
    --set serviceAccount.create=true \
    --set serviceAccount.name=aws-load-balancer-controller \
    --wait

log "AWS Load Balancer Controller installed"

# -------------------------------------------------------------------------
step "Installing Metrics Server (for HPA)"
# -------------------------------------------------------------------------
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>/dev/null || true
log "Metrics Server installed"

# -------------------------------------------------------------------------
step "Checking Jenkins Status"
# -------------------------------------------------------------------------
echo "Waiting for Jenkins pod to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=jenkins-controller \
    -n jenkins --timeout=300s 2>/dev/null || true

JENKINS_URL=$(kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deployment Complete!                                    ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  EKS Cluster: ${EKS_CLUSTER}${NC}"
echo -e "${GREEN}║  ECR Repo:    ${ECR_URL}${NC}"
echo -e "${GREEN}║  Jenkins URL: http://${JENKINS_URL}:8080${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║  Jenkins Creds: See terraform.tfvars                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
