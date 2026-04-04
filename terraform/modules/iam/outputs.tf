output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  value = aws_iam_role.eks_node.arn
}

output "jenkins_role_arn" {
  value = aws_iam_role.jenkins.arn
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}
