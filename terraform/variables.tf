# =============================================================================
# variables.tf — All the inputs our Terraform code accepts
# =============================================================================
#
# WHY DO WE HAVE THIS FILE?
# Instead of hardcoding values like vm_name = "my-vm" directly in main.tf,
# we define "variables" here. This lets us pass different values each time
# without changing the code. GitHub Actions will pass these values via -var flags.
#
# ANALOGY: Think of variables like the parameters of a function.
#   function createVM(vm_name, vm_size, environment) { ... }
# =============================================================================

variable "vm_name" {
  description = "The name for the Virtual Machine (e.g. test-vm-01)"
  type        = string
}

variable "vm_size" {
  description = "The Azure VM size/SKU (e.g. Standard_B1s, Standard_B2s)"
  type        = string
  default     = "Standard_B1s"
}

variable "os_type" {
  description = "The OS image to use (e.g. ubuntu-22.04, ubuntu-20.04)"
  type        = string
  default     = "ubuntu-22.04"
}

variable "environment" {
  description = "The target environment (dev or staging)"
  type        = string
  default     = "dev"
}

variable "owner_email" {
  description = "Email of the person who requested the VM"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID where the VM will be created"
  type        = string
  sensitive   = true  # Marks this as sensitive so it won't be printed in logs
}

# WHY location is hardcoded here: 
# All VMs in this system go to East US. If you want to change region,
# change it here once and all future VMs use the new region.
variable "location" {
  description = "Azure region where resources will be created"
  type        = string
  default     = "East US"
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access (passed from GitHub Secret)"
  type        = string
  sensitive   = true  # Won't be printed in Terraform logs
}
