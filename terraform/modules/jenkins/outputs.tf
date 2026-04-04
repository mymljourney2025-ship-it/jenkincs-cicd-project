output "jenkins_namespace" {
  value = kubernetes_namespace.jenkins.metadata[0].name
}

output "jenkins_service_account" {
  value = kubernetes_service_account.jenkins.metadata[0].name
}
