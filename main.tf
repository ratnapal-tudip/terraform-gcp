###############################################################
# ROOT MAIN.TF
# Ratnapal Project - GCP Architecture
# Region: us-central1 | Free-tier optimized
###############################################################

module "vpc" {
  source     = "./modules/vpc"
  project_id = var.project_id
  region     = var.region
}

module "artifact_registry" {
  source     = "./modules/artifact_registry"
  project_id = var.project_id
  region     = var.region
}

module "storage" {
  source     = "./modules/storage"
  project_id = var.project_id
  region     = var.region
}

module "sql" {
  source          = "./modules/sql"
  project_id      = var.project_id
  region          = var.region
  private_network = module.vpc.vpc_self_link
  db_password     = var.db_password
  depends_on      = [module.vpc]
}

module "compute" {
  source                  = "./modules/compute"
  project_id              = var.project_id
  region                  = var.region
  zone                    = var.zone
  private_subnet_id       = module.vpc.private_subnet_id
  public_subnet_id        = module.vpc.public_subnet_id
  vpc_name                = module.vpc.vpc_name
  artifact_registry_repo  = module.artifact_registry.repository_id
  depends_on              = [module.vpc, module.artifact_registry]
}

module "load_balancer" {
  source            = "./modules/load_balancer"
  project_id        = var.project_id
  region            = var.region
  backend_vm_group  = module.compute.backend_instance_group
  frontend_bucket   = module.storage.bucket_name
  depends_on        = [module.compute, module.storage]
}
