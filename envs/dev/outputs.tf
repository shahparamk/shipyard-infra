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

output "orders_queue_url" {
  value = module.orders_queue.queue_url
}

output "orders_dlq_url" {
  value = module.orders_queue.dlq_url
}

output "rds_address" {
  value = try(module.rds[0].address, null)
}

output "rds_secret_arn" {
  value = try(module.rds[0].secret_arn, null)
}