# =============================================================================
# Jenkins Module — Deploy Jenkins on EKS via Helm
# =============================================================================

# --- Namespace ---
resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = "jenkins"
    labels = {
      app         = "jenkins"
      environment = var.environment
    }
  }
}

# --- Jenkins Service Account ---
resource "kubernetes_service_account" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace.jenkins.metadata[0].name
    labels = {
      app = "jenkins"
    }
  }
}

# --- Cluster Role Binding for Jenkins ---
resource "kubernetes_cluster_role_binding" "jenkins" {
  metadata {
    name = "jenkins-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.jenkins.metadata[0].name
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }
}

# --- Jenkins Helm Release ---
resource "helm_release" "jenkins" {
  name       = "jenkins"
  namespace  = kubernetes_namespace.jenkins.metadata[0].name
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = "5.1.5"
  timeout    = 600

  values = [
    yamlencode({
      controller = {
        image         = "jenkins/jenkins"
        tag           = "lts-jdk17"
        imagePullPolicy = "IfNotPresent"

        serviceType = "LoadBalancer"
        servicePort = 8080

        adminUser     = var.jenkins_admin_user
        adminPassword = var.jenkins_admin_pass

        resources = {
          requests = {
            cpu    = "500m"
            memory = "1Gi"
          }
          limits = {
            cpu    = "2000m"
            memory = "4Gi"
          }
        }

        # Tolerate the jenkins taint so it schedules on dedicated nodes
        tolerations = [{
          key      = "jenkins"
          operator = "Equal"
          value    = "true"
          effect   = "NoSchedule"
        }]

        nodeSelector = {
          role = "jenkins"
        }

        # JCasC — Jenkins Configuration as Code
        JCasC = {
          configScripts = {
            welcome-message = <<-EOT
              jenkins:
                systemMessage: "Jenkins CI/CD Pipeline — Managed by Terraform"
            EOT

            security-config = <<-EOT
              jenkins:
                securityRealm:
                  local:
                    allowsSignup: false
                authorizationStrategy:
                  loggedInUsersCanDoAnything:
                    allowAnonymousRead: false
            EOT

            credentials-config = <<-EOT
              credentials:
                system:
                  domainCredentials:
                    - credentials:
                        - string:
                            id: "aws-account-id"
                            scope: GLOBAL
                            description: "AWS Account ID"
                            secret: "REPLACE_WITH_ACCOUNT_ID"
            EOT
          }
        }

        # Install essential plugins
        installPlugins = [
          "kubernetes:4206.v39c68e6f15e5",
          "workflow-aggregator:600.vb_57cdd26fdd7",
          "git:5.2.2",
          "pipeline-stage-view:2.34",
          "docker-workflow:572.v950f58993843",
          "amazon-ecr:1.114.v5f88003dff4e",
          "aws-credentials:218.v1b_e9466ec5da_",
          "configuration-as-code:1810.v9b_c30a_249a_4c",
          "blueocean:1.27.14",
          "pipeline-utility-steps:2.16.2",
          "slack:722.vd18a_3f1ee22b_",
          "sonar:2.17.2",
          "prometheus:779.vc5cb_0b_5fe168",
          "kubernetes-cli:1.12.1",
          "timestamper:1.27",
          "ansicolor:1.0.4",
          "rebuild:332.va_1ee476d8f6d",
          "generic-webhook-trigger:2.2.2"
        ]

        initializeOnce = true

        prometheus = {
          enabled = true
          serviceMonitorEnabled = false
        }
      }

      persistence = {
        enabled       = true
        storageClass  = var.storage_class
        size          = var.storage_size
      }

      agent = {
        enabled   = true
        namespace = kubernetes_namespace.jenkins.metadata[0].name
        image     = "jenkins/inbound-agent"
        tag       = "latest-jdk17"

        resources = {
          requests = {
            cpu    = "256m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "2Gi"
          }
        }

        # Pod template for Kubernetes agents
        podTemplates = {
          docker = <<-EOT
            - name: docker
              label: docker
              serviceAccount: jenkins
              containers:
                - name: docker
                  image: docker:24-dind
                  privileged: true
                  command: "dockerd-entrypoint.sh"
                  args: ""
                  ttyEnabled: true
                - name: kubectl
                  image: bitnami/kubectl:latest
                  command: "cat"
                  ttyEnabled: true
                - name: aws-cli
                  image: amazon/aws-cli:latest
                  command: "cat"
                  ttyEnabled: true
              volumes:
                - emptyDirVolume:
                    mountPath: /var/lib/docker
                    memory: false
          EOT
        }
      }

      rbac = {
        create = true
      }

      serviceAccount = {
        create = false
        name   = kubernetes_service_account.jenkins.metadata[0].name
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.jenkins,
    kubernetes_service_account.jenkins,
    kubernetes_cluster_role_binding.jenkins
  ]
}
