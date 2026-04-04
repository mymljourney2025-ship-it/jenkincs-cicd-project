output "eks_cluster_sg_id" {
  value = aws_security_group.eks_cluster.id
}

output "jenkins_sg_id" {
  value = aws_security_group.jenkins.id
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}
