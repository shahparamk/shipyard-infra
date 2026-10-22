output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "cluster_name" {
  value = try(module.eks[0].cluster_name, null)
}

output "cluster_endpoint" {
  value = try(module.eks[0].cluster_endpoint, null)
}