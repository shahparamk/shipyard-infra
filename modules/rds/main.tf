resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnets"
  subnet_ids = var.subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds"
  description = "Postgres access for ${var.name}; only from allowed security groups"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-rds" })
}

# count (not for_each) because the SG IDs aren't known until the cluster exists
resource "aws_vpc_security_group_ingress_rule" "postgres" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "Postgres from allowed security group"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
}

# Created first so we control retention (RDS would create them with "never expire")
resource "aws_cloudwatch_log_group" "this" {
  for_each = toset(["postgresql", "upgrade"])
  #checkov:skip=CKV_AWS_158:DB logs are encrypted at rest by CloudWatch by default; a dedicated KMS key isn't justified for dev
  #checkov:skip=CKV_AWS_338:Short retention is a deliberate dev cost control

  name              = "/aws/rds/instance/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# Query logging: schema changes + slow queries only (useful for debugging, no routine data in logs)
resource "aws_db_parameter_group" "this" {
  name        = "${var.name}-pg"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "Query logging for ${var.name}"

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "500" # milliseconds
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }

  # Refuse any connection that isn't TLS-encrypted
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "this" {
  #checkov:skip=CKV_AWS_157:Single-AZ by design: dev database is torn down every session; prod would be Multi-AZ
  #checkov:skip=CKV_AWS_293:No deletion protection: the dev DB is intentionally destroyed with the cluster switch
  #checkov:skip=CKV_AWS_118:Enhanced monitoring adds cost; CloudWatch basic metrics + exported logs are enough for dev
  #checkov:skip=CKV_AWS_353:Performance Insights not needed for a short-lived dev database

  identifier     = var.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.username
  # AWS generates the password and stores it in Secrets Manager; it never appears in code or Terraform state
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = false

  iam_database_authentication_enabled = true
  auto_minor_version_upgrade          = true
  copy_tags_to_snapshot               = true
  enabled_cloudwatch_logs_exports     = ["postgresql", "upgrade"]

  # Dev lifecycle: recreated on every spin-up
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.this]
}