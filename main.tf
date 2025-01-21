# main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  vpc_cidr           = var.vpc_cidr
  environment        = var.environment
  availability_zones = var.availability_zones
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
}

# EKS Module
module "eks" {
  source = "./modules/eks"
  
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  private_subnets = module.vpc.private_subnet_ids
  
  node_groups = {
    managed_group = {
      desired_size = 2
      max_size     = 4
      min_size     = 1
      instance_types = ["t3.medium"]
    }
  }
}

# AWS Control Tower Module
module "control_tower" {
  source = "./modules/control_tower"
  
  account_name = var.account_name
  email        = var.account_email
  org_unit     = var.organizational_unit
}

# DynamoDB for State Management
module "dynamodb" {
  source = "./modules/dynamodb"
  
  table_name = "aft-request-table"
  hash_key   = "id"
}

# CodeBuild Projects
module "codebuild" {
  source = "./modules/codebuild"
  
  project_name = "aft-account-customizations"
  vpc_id       = module.vpc.vpc_id
  subnets      = module.vpc.private_subnet_ids
}

# Add-ons Module
module "addons" {
  source = "./modules/addons"
  
  cluster_name     = module.eks.cluster_name
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_ca       = module.eks.cluster_ca_certificate
}

# modules/vpc/main.tf
resource "aws_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${var.environment}-vpc"
  }
}

resource "aws_subnet" "public" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "${var.environment}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  
  tags = {
    Name = "${var.environment}-private-${count.index + 1}"
  }
}

# modules/eks/main.tf
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = var.private_subnets
  }
}

resource "aws_eks_node_group" "managed" {
  for_each = var.node_groups
  
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnets

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  instance_types = each.value.instance_types
}

# modules/addons/main.tf
resource "helm_release" "vpc_cni" {
  name       = "aws-vpc-cni"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-vpc-cni"
  namespace  = "kube-system"
}

resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "prometheus"
  namespace  = "monitoring"
}

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"
}

resource "helm_release" "coredns" {
  name       = "coredns"
  repository = "https://coredns.github.io/helm"
  chart      = "coredns"
  namespace  = "kube-system"
}

# variables.tf
variable "region" {
  description = "AWS region"
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name"
  default     = "production"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-west-2a", "us-west-2b", "us-west-2c"]
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "cluster_name" {
  description = "EKS cluster name"
  default     = "main-eks-cluster"
}

variable "cluster_version" {
  description = "Kubernetes version"
  default     = "1.27"
}

variable "account_name" {
  description = "AWS account name"
  type        = string
}

variable "account_email" {
  description = "AWS account email"
  type        = string
}

variable "organizational_unit" {
  description = "AWS organizational unit"
  type        = string
}
