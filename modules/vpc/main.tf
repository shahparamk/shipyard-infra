data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Public: small /24s for load balancers and NAT -> 10.0.0.0/24, 10.0.1.0/24
  public_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 8, i)]

  # Private: large /20s because every EKS pod gets a VPC IP -> 10.0.16.0/20, 10.0.32.0/20
  private_cidrs = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i + 1)]
}

# ---------------- VPC ----------------

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true # required for EKS and private endpoints

  tags = merge(var.tags, { Name = var.name })
}

# Lock down the default security group (AWS's default allows all traffic between members)
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-default-locked" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

# ---------------- Subnets ----------------

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # nothing gets a public IP by accident

  tags = merge(var.tags, {
    Name                                        = "${var.name}-public-${local.azs[count.index]}"
    Tier                                        = "public"
    "kubernetes.io/role/elb"                    = "1" # internet-facing ALBs go here
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name                                        = "${var.name}-private-${local.azs[count.index]}"
    Tier                                        = "private"
    "kubernetes.io/role/internal-elb"           = "1" # internal load balancers go here
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name # Karpenter launches nodes here
  })
}

# ---------------- Public routing ----------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------- NAT (optional, single for dev) ----------------

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(var.tags, { Name = "${var.name}-nat" })

  depends_on = [aws_internet_gateway.this]
}

# ---------------- Private routing ----------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Free S3 gateway endpoint: S3 traffic (ECR image layers, state) skips the NAT and its per-GB charges
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(var.tags, { Name = "${var.name}-s3-endpoint" })
}