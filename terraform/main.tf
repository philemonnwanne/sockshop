# this file defines the terraform block, which Terraform uses to configure itself
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.47"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
  }
}

# # import secrets from vault
# data "vault_generic_secret" "capstone_aws_creds" {
#     path = "secret/aws"
# }

# this block configures the AWS provider
# provider "aws" {
#   region = local.region
#   access_key = data.vault_generic_secret.capstone_aws_creds.data["aws_access_key_id"]
#   secret_key = data.vault_generic_secret.capstone_aws_creds.data["aws_secret_access_key"]
# }

# retrieve info about the authnticated aws user
data "aws_caller_identity" "current" {}

# create local variables
locals {
  region = var.region

  oidc_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  cluster_name = var.cluster_name
  account_id = data.aws_caller_identity.current.account_id

  tags = {
    Maintainer = "${var.maintainer}"
    Track = "${var.track}"
  }
}

# import the vpc module
module "vpc" {
  source = "./modules/vpc"

  vpc_name = "${var.vpc_name}-vpc"
  tags     = local.tags
}

# import the eks module
module "eks" {
  source  = "./modules/eks"

  cluster_name = local.cluster_name
  subnet_ids = module.vpc.capstone_vpc_private_subnets
  vpc_id = module.vpc.capstone_vpc_id
 
  tags = local.tags
}

module "k8s" {
  source = "./modules/k8s"

  cluster_name           = module.eks.cluster_name
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

# import the kubeconfig module
module "eks-kubeconfig" {
  source  = "hyperbadger/eks-kubeconfig/aws"
  version = "1.0.0"

  depends_on = [module.eks]
  cluster_id = module.eks.cluster_name
}

# generate a kubeconfig file
resource "local_file" "kubeconfig" {
  content  = module.eks-kubeconfig.kubeconfig
  filename = "kubeconfig_${local.cluster_name}"
}


resource "aws_iam_policy" "worker_policy" {
  name        = "worker-policy"
  description = "Worker policy for the ALB Ingress"

  policy = file("../json/iam-policy.json")
}  

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = module.eks.eks_managed_node_groups

  policy_arn = aws_iam_policy.worker_policy.arn
  role       = each.value.iam_role_name

}

# # TODO
# module "lb_role" {
#   source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

#   role_name                              = "prod_eks_lb"
#   attach_load_balancer_controller_policy = true

#   oidc_providers = {
#     main = {
#       provider_arn               = module.eks.oidc_provider_arn
#       namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
#     }
#   }
# }

# # TODO
# resource "kubernetes_service_account" "service-account" {
#   metadata {
#     name      = "aws-load-balancer-controller"
#     namespace = "kube-system"
#     labels = {
#       "app.kubernetes.io/name"      = "aws-load-balancer-controller"
#       "app.kubernetes.io/component" = "controller"
#     }
#     annotations = {
#       "eks.amazonaws.com/role-arn"               = module.lb_role.iam_role_arn
#       "eks.amazonaws.com/sts-regional-endpoints" = "true"
#     }
#   }
# }
