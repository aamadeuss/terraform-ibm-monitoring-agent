##############################################################################
# Resource Group
##############################################################################

module "resource_group" {
  source  = "terraform-ibm-modules/resource-group/ibm"
  version = "1.2.1"
  # if an existing resource group is not set (null) create a new one using prefix
  resource_group_name          = var.resource_group == null ? "${var.prefix}-resource-group" : null
  existing_resource_group_name = var.resource_group
}

########################################################################################################################
# VPC + Subnet + Public Gateway
#
# NOTE: This is a very simple VPC with single subnet in a single zone with a public gateway enabled, that will allow
# all traffic ingress/egress by default.
# For production use cases this would need to be enhanced by adding more subnets and zones for resiliency, and
# ACLs/Security Groups for network security.
########################################################################################################################

resource "ibm_is_vpc" "vpc" {
  name                      = "${var.prefix}-vpc"
  resource_group            = module.resource_group.resource_group_id
  address_prefix_management = "auto"
  tags                      = var.resource_tags
}

# Public gateway required when deploying a cluster with public endpoint enabled otherwise ingress goes into degraded state
resource "ibm_is_public_gateway" "gateway" {
  name           = "${var.prefix}-gateway-1"
  vpc            = ibm_is_vpc.vpc.id
  resource_group = module.resource_group.resource_group_id
  zone           = "${var.region}-1"
}

resource "ibm_is_subnet" "subnet_zone_1" {
  name                     = "${var.prefix}-subnet-1"
  vpc                      = ibm_is_vpc.vpc.id
  resource_group           = module.resource_group.resource_group_id
  zone                     = "${var.region}-1"
  total_ipv4_address_count = 256
  public_gateway           = ibm_is_public_gateway.gateway.id
}

########################################################################################################################
# OCP VPC cluster (single zone)
########################################################################################################################

locals {
  cluster_vpc_subnets = {
    default = [
      {
        id         = ibm_is_subnet.subnet_zone_1.id
        cidr_block = ibm_is_subnet.subnet_zone_1.ipv4_cidr_block
        zone       = ibm_is_subnet.subnet_zone_1.zone
      }
    ]
  }

  worker_pools = [
    {
      subnet_prefix    = "default"
      pool_name        = "default" # ibm_container_vpc_cluster automatically names default pool "default" (See https://github.com/IBM-Cloud/terraform-provider-ibm/issues/2849)
      machine_type     = "bx2.4x16"
      workers_per_zone = 2 # minimum of 2 is allowed when using single zone
      operating_system = "RHCOS"
    }
  ]
}

module "ocp_base" {
  source               = "terraform-ibm-modules/base-ocp-vpc/ibm"
  version              = "3.52.4"
  resource_group_id    = module.resource_group.resource_group_id
  region               = var.region
  tags                 = var.resource_tags
  cluster_name         = "${var.prefix}-cluster"
  force_delete_storage = true
  vpc_id               = ibm_is_vpc.vpc.id
  vpc_subnets          = local.cluster_vpc_subnets
  worker_pools         = local.worker_pools
  access_tags          = []
}

##############################################################################
# Monitoring:
# - Cloud Monitoring instance
##############################################################################

module "cloud_monitoring" {
  source            = "terraform-ibm-modules/cloud-monitoring/ibm"
  version           = "1.5.0"
  instance_name     = "${var.prefix}-cloud-monitoring"
  resource_group_id = module.resource_group.resource_group_id
  resource_tags     = var.resource_tags
  region            = var.region
  plan              = "graduated-tier"
}
