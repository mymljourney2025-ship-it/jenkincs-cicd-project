# Jenkins + EKS CI/CD Pipeline — Complete Infrastructure as Code

Production-grade CI/CD pipeline that provisions AWS infrastructure with Terraform and deploys
a containerized application to Kubernetes via Jenkins — fully automated, end to end.

---

## What Gets Created

| Resource | Description |
|---|---|
| **VPC** | Multi-AZ VPC with 3 public + 3 private subnets, NAT Gateways (HA), Internet Gateway, VPC Flow Logs |
| **EKS Cluster** | Managed Kubernetes (v1.29) with OIDC, control-plane logging, EBS CSI driver |
| **Node Groups** | General-purpose nodes (t3.large × 2) + dedicated Jenkins nodes (t3.xlarge, tainted) |
| **ECR** | Private container registry with vulnerability scanning, lifecycle policy (keeps 30 images) |
| **IAM Roles** | Least-privilege roles for EKS cluster, worker nodes, Jenkins (IRSA), ALB controller |
| **Security Groups** | Separate SGs for EKS control plane, Jenkins, ALB |
| **Jenkins** | Jenkins LTS on EKS via Helm — JCasC, Blue Ocean, Kubernetes agents, Prometheus metrics |
| **K8s Manifests** | Deployment (3 replicas), HPA (3-10), NLB Service, ALB Ingress, NetworkPolicy, PDB |

### Pipeline Stages (Jenkinsfile)

```
Checkout → Unit Tests → Docker Build → Trivy Security Scan → Push to ECR → Deploy to EKS → Smoke Test
```

### Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│  AWS Account                                                        │
│                                                                     │
│  ┌─── VPC (10.0.0.0/16) ───────────────────────────────────────┐   │
│  │                                                               │   │
│  │  ┌─ Public Subnets ──────┐    ┌─ Private Subnets ─────────┐ │   │
│  │  │  Internet Gateway      │    │                            │ │   │
│  │  │  NAT Gateways (×3)    │    │  EKS Control Plane         │ │   │
│  │  │  ALB / NLB             │    │  Worker Nodes (general)    │ │   │
│  │  │                        │    │  Worker Nodes (jenkins)    │ │   │
│  │  └────────────────────────┘    │                            │ │   │
│  │                                │  ┌── Jenkins (Helm) ─────┐ │ │   │
│  │                                │  │  Controller Pod        │ │ │   │
│  │                                │  │  Dynamic K8s Agents    │ │ │   │
│  │                                │  └────────────────────────┘ │ │   │
│  │                                │                            │ │   │
│  │                                │  ┌── App Deployment ─────┐ │ │   │
│  │        Internet ──► NLB ──────►│  │  3 replicas (HPA)     │ │ │   │
│  │                                │  │  /health /ready        │ │ │   │
│  │                                │  └────────────────────────┘ │ │   │
│  │                                └────────────────────────────┘ │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─ ECR ──────────┐  ┌─ IAM ─────────────┐  ┌─ CloudWatch ──────┐ │
│  │ App images      │  │ EKS cluster role   │  │ VPC Flow Logs     │ │
│  │ Scan on push    │  │ Node role          │  │ EKS audit logs    │ │
│  │ Lifecycle policy│  │ Jenkins IRSA role   │  │ Jenkins metrics   │ │
│  └─────────────────┘  │ ALB controller role│  └────────────────────┘ │
│                        └───────────────────┘                         │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Install these tools on your local machine (Ubuntu/macOS/WSL):

| Tool | Minimum Version | Install |
|---|---|---|
| Terraform | 1.5+ | `https://developer.hashicorp.com/terraform/install` |
| AWS CLI | 2.x | `https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html` |
| kubectl | 1.28+ | `https://kubernetes.io/docs/tasks/tools/` |
| Helm | 3.x | `https://helm.sh/docs/intro/install/` |
| Docker | 24+ | `https://docs.docker.com/engine/install/` |
| Git | 2.x | `sudo apt install git` |

### Quick Install (Ubuntu)

```bash
# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

---

## Step-by-Step Deployment Guide

### Step 1 — Clone and Configure AWS

```bash
git clone <your-repo-url> jenkins-k8s-pipeline
cd jenkins-k8s-pipeline

# Configure AWS credentials (use a user/role with Admin or PowerUser access)
aws configure
# AWS Access Key ID:     <your-key>
# AWS Secret Access Key: <your-secret>
# Default region name:   us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity
```

### Step 2 — Run Setup Script

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

This script will:
- Verify all prerequisites are installed
- Check AWS credentials
- Optionally create S3 backend for Terraform state
- Create `terraform/terraform.tfvars` from the example
- Add required Helm repos

### Step 3 — Edit Configuration

```bash
# IMPORTANT: Edit the variables for your environment
vi terraform/terraform.tfvars
```

Key settings to change:

```hcl
aws_region         = "us-east-1"       # Your preferred region
jenkins_admin_pass = "YourSecurePass"  # Strong password!
environment        = "dev"             # dev | staging | prod
node_instance_types = ["t3.large"]     # Adjust for workload
```

**Security tip** — pass the password via environment variable instead of the file:

```bash
export TF_VAR_jenkins_admin_pass="YourStrongPassword123!"
```

### Step 4 — Initialize and Apply Terraform

```bash
cd terraform

# Initialize providers and modules
terraform init

# Review the plan (57 resources)
terraform plan -out=plan.out

# Apply — takes ~15-20 minutes (EKS cluster creation is the bottleneck)
terraform apply plan.out
```

Expected output:
```
Apply complete! Resources: 57 added, 0 changed, 0 destroyed.

Outputs:
  ecr_repository_url = "123456789.dkr.ecr.us-east-1.amazonaws.com/jenkins-k8s-dev-app"
  eks_cluster_name   = "jenkins-k8s-dev-eks"
  kubeconfig_command  = "aws eks update-kubeconfig --region us-east-1 --name jenkins-k8s-dev-eks"
```

### Step 5 — Post-Deploy Setup

```bash
cd ..
./scripts/post-deploy.sh
```

This script will:
- Configure kubectl for the new EKS cluster
- Install AWS Load Balancer Controller
- Install Metrics Server (required for HPA)
- Show the Jenkins URL

### Step 6 — Access Jenkins

```bash
# Get Jenkins URL
kubectl get svc jenkins -n jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# If LoadBalancer is still provisioning, use port-forward:
kubectl port-forward svc/jenkins -n jenkins 8080:8080
# Then open: http://localhost:8080
```

Login with:
- **Username**: `admin` (or your configured value)
- **Password**: the value from `terraform.tfvars` or `TF_VAR_jenkins_admin_pass`

### Step 7 — Configure Jenkins Pipeline

1. Open Jenkins → **New Item** → **Pipeline** → name it `myapp-pipeline`
2. Under **Pipeline**, select **Pipeline script from SCM**
3. Set:
   - **SCM**: Git
   - **Repository URL**: your repo URL
   - **Script Path**: `jenkins/pipelines/Jenkinsfile`
4. Under **Build Triggers**, enable **GitHub hook trigger for GITScm polling** (optional)
5. **Save** and click **Build Now**

### Step 8 — Add AWS Credentials to Jenkins

1. **Manage Jenkins** → **Manage Credentials** → **System** → **Global credentials**
2. Add:
   - **Kind**: Secret text, **ID**: `aws-account-id`, **Secret**: your AWS account ID
   - **Kind**: Secret text, **ID**: `aws-region`, **Secret**: `us-east-1`
3. If not using IRSA, also add AWS Access Key credentials:
   - **Kind**: AWS Credentials, **ID**: `aws-credentials`

### Step 9 — Trigger the Pipeline

Push code to your repo, or click **Build Now** in Jenkins. The pipeline will:

1. Check out your code
2. Run unit tests
3. Build a Docker image
4. Scan with Trivy for vulnerabilities
5. Push to ECR
6. Deploy to EKS with rolling updates
7. Run smoke tests against the live endpoint

### Step 10 — Verify the Deployment

```bash
# Check pods
kubectl get pods -n application

# Check service (get public URL)
kubectl get svc myapp -n application

# Check HPA
kubectl get hpa -n application

# Test the endpoint
APP_URL=$(kubectl get svc myapp -n application -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://${APP_URL}/health
```

---

## Project Structure

```
jenkins-k8s-pipeline/
├── terraform/
│   ├── main.tf                    # Root module — wires everything together
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── terraform.tfvars.example   # Example config (copy to terraform.tfvars)
│   └── modules/
│       ├── vpc/                   # VPC, subnets, NAT, flow logs
│       ├── eks/                   # EKS cluster, node groups, addons, OIDC
│       ├── iam/                   # IAM roles: cluster, nodes, Jenkins, ALB
│       ├── ecr/                   # ECR repo, lifecycle policy, scanning
│       ├── security/              # Security groups for EKS, Jenkins, ALB
│       └── jenkins/               # Jenkins Helm deployment on EKS
├── jenkins/
│   ├── pipelines/
│   │   └── Jenkinsfile            # Main CI/CD pipeline definition
│   └── docker/
│       └── Dockerfile             # Multi-stage production Dockerfile
├── k8s/
│   └── base/
│       ├── namespace.yaml         # App namespace
│       ├── configmap.yaml         # Non-sensitive config
│       ├── secret.yaml            # Secrets (use Sealed Secrets in prod)
│       ├── deployment.yaml        # App deployment + PDB
│       ├── service.yaml           # NLB service (public)
│       ├── hpa.yaml               # Autoscaler (3-10 pods)
│       ├── ingress.yaml           # ALB ingress
│       └── networkpolicy.yaml     # Network restrictions
├── src/
│   └── server.js                  # Sample Node.js app (replace with yours)
├── scripts/
│   ├── setup.sh                   # Pre-deploy setup
│   ├── post-deploy.sh             # Post-deploy configuration
│   └── destroy.sh                 # Clean teardown
├── package.json
├── .gitignore
└── README.md
```

---

## Customization Guide

### Using Your Own Application

1. Replace `src/server.js` and `package.json` with your app
2. Update `jenkins/docker/Dockerfile` for your language/framework
3. Ensure your app exposes `/health` and `/ready` endpoints
4. Update `k8s/base/deployment.yaml` port if not 3000
5. Uncomment the appropriate test command in the Jenkinsfile

### Switching to Production

| Setting | Dev (default) | Production recommendation |
|---|---|---|
| `node_instance_types` | t3.large | m5.xlarge or c5.xlarge |
| `node_desired_size` | 2 | 3-5 |
| `node_max_size` | 5 | 15-20 |
| K8s replicas | 3 | 5+ |
| NAT Gateways | 3 (HA) | 3 (already HA) |
| Jenkins storage | 50Gi | 100Gi |
| Terraform backend | local | S3 + DynamoDB (uncomment in main.tf) |
| Secrets | K8s Secret | AWS Secrets Manager + External Secrets |
| Ingress | HTTP | HTTPS with ACM certificate |

### Adding HTTPS

1. Request a certificate in AWS Certificate Manager (ACM)
2. Update `k8s/base/ingress.yaml`:
   ```yaml
   annotations:
     alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS": 443}]'
     alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:REGION:ACCOUNT:certificate/ID
     alb.ingress.kubernetes.io/ssl-redirect: "443"
   ```

### Adding Monitoring (Prometheus + Grafana)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install monitoring prometheus-community/kube-prometheus-stack \
    --namespace monitoring --create-namespace \
    --set grafana.service.type=LoadBalancer
```

### Adding Slack Notifications

1. Install the Slack plugin (already in the Helm values)
2. In Jenkins: **Manage Jenkins** → **System** → **Slack**
3. Uncomment the `slackSend` lines in the Jenkinsfile

---

## Estimated AWS Costs

| Resource | Monthly estimate (us-east-1) |
|---|---|
| EKS control plane | ~$73 |
| EC2 nodes (2× t3.large + 1× t3.xlarge) | ~$200 |
| NAT Gateways (×3) | ~$100 |
| ALB/NLB | ~$25 |
| ECR storage | ~$1-5 |
| CloudWatch logs | ~$5-10 |
| **Total** | **~$400-420/month** |

**Cost-saving tips for dev/test:**
- Use 1 NAT Gateway instead of 3 (modify VPC module)
- Use `t3.medium` nodes
- Use Spot instances for general node group
- Scale node min to 1

---

## Cleanup / Teardown

```bash
# Full automated teardown
./scripts/destroy.sh

# Or manually:
cd terraform
terraform destroy -auto-approve
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `terraform apply` timeout on EKS | EKS takes 12-18 min. Re-run `terraform apply`. |
| Jenkins pod stuck in Pending | Check node group: `kubectl describe pod -n jenkins` — likely needs the tainted jenkins nodes |
| ECR push denied | Verify Jenkins IAM role has `ecr:PutImage`. Check: `aws ecr get-login-password` works |
| LoadBalancer shows `<pending>` | Wait 2-3 min. Check: `kubectl describe svc -n application myapp` for events |
| HPA not scaling | Verify metrics-server: `kubectl top pods -n application` |
| Nodes not joining | Check node IAM role has EKS policies. Check: `kubectl get nodes` |
| Jenkins can't reach EKS API | Verify cluster endpoint is public or Jenkins is in private subnet |

### Useful Debug Commands

```bash
# Cluster status
kubectl cluster-info
kubectl get nodes -o wide

# Jenkins logs
kubectl logs -n jenkins -l app.kubernetes.io/component=jenkins-controller -f

# App logs
kubectl logs -n application -l app=myapp -f --all-containers

# EKS events
kubectl get events -n application --sort-by='.lastTimestamp'

# ECR images
aws ecr list-images --repository-name jenkins-k8s-dev-app
```

---

## Security Features Included

- **VPC Flow Logs** — all traffic logged to CloudWatch
- **EKS Audit Logs** — API server, authenticator, scheduler logs enabled
- **Private node groups** — worker nodes in private subnets only
- **Trivy scanning** — container vulnerability scanning in pipeline
- **Non-root containers** — Dockerfile runs as UID 1001
- **Read-only filesystem** — deployment uses `readOnlyRootFilesystem: true`
- **Network Policies** — restrict pod-to-pod traffic
- **Pod Disruption Budget** — ensure availability during rollouts
- **ECR scan on push** — automatic vulnerability scanning
- **IAM least privilege** — IRSA for Jenkins, scoped ECR/EKS permissions
- **Security groups** — separate SGs per component

---

## License

MIT
