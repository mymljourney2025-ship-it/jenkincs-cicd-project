# =============================================================================
# Jenkins + EKS CI/CD Pipeline — Root Module
# =============================================================================
# Creates: VPC, EKS Cluster, ECR Repository, IAM Roles, Security Groups,
#          Jenkins on EKS, and all supporting infrastructure.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Uncomment and configure for remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "jenkins-k8s-pipeline/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-lock"
  #   encrypt        = true
  # }
}

# -----------------------------------------------------------------------------
# Provider Configuration
# -----------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    }
  }
}

# Kubernetes provider — configured after EKS is created
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# Modules
# -----------------------------------------------------------------------------

# --- VPC ---
module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
}

# --- IAM Roles ---
module "iam" {
  source = "./modules/iam"

  project_name   = var.project_name
  environment    = var.environment
  account_id     = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region
  ecr_repo_arn   = module.ecr.repository_arn
  eks_cluster_id = module.eks.cluster_name
}

# --- ECR Repository ---
module "ecr" {
  source = "./modules/ecr"

  project_name          = var.project_name
  environment           = var.environment
  image_tag_mutability  = "MUTABLE"
  scan_on_push          = true
  max_image_count       = var.ecr_max_image_count
  account_id            = data.aws_caller_identity.current.account_id
}

# --- Security Groups ---
module "security" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = var.vpc_cidr
}

# --- EKS Cluster ---
module "eks" {
  source = "./modules/eks"

  project_name        = var.project_name
  environment         = var.environment
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  cluster_role_arn    = module.iam.eks_cluster_role_arn
  node_role_arn       = module.iam.eks_node_role_arn
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size
  security_group_ids  = [module.security.eks_cluster_sg_id]

  depends_on = [module.vpc, module.iam]
}

# --- Jenkins on EKS ---
module "jenkins" {
  source = "./modules/jenkins"

  project_name       = var.project_name
  environment        = var.environment
  jenkins_admin_user = var.jenkins_admin_user
  jenkins_admin_pass = var.jenkins_admin_pass
  storage_class      = "gp2"
  storage_size       = var.jenkins_storage_size

  depends_on = [module.eks]
}
