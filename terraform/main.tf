# =============================================================================
# main.tf — The actual infrastructure we want to build in Azure
# =============================================================================
#
# HOW TERRAFORM WORKS:
# 1. You describe WHAT you want (not HOW to build it)
# 2. Terraform figures out the correct order to create things
# 3. Terraform calls the Azure API to make it happen
# 4. If you run it again with the same values, nothing changes (idempotent!)
#
# TERRAFORM BLOCKS:
# - "terraform {}"   → Sets up Terraform itself (version, plugins to use)
# - "provider {}"    → Tells Terraform which cloud to use (Azure in our case)
# - "resource {}"    → Each piece of infrastructure we want to create
# - "locals {}"      → Like variables you calculate yourself (not passed in)
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      # WHY: Terraform doesn't know Azure natively. This "provider" is a plugin
      # that translates Terraform commands into actual Azure API calls.
      # Like a translator between Terraform and Azure.
      source  = "hashicorp/azurerm"
      version = "~> 3.110"
    }
  }
}

# =============================================================================
# PROVIDER BLOCK — Connect to Azure
# =============================================================================
# WHY: Before Terraform can create anything, it needs to log in to Azure.
# It reads the ARM_* environment variables we set in GitHub Actions secrets.
# ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# =============================================================================
# LOCALS — Values we calculate ourselves
# =============================================================================
# WHY: Instead of repeating the same string everywhere, we define it once here.
# Also, all tags are defined here so every resource gets the same tags
# (useful for Azure cost reports and finding who owns what).
locals {
  # Prefix all resource names with the vm_name and environment for uniqueness
  prefix = "${var.vm_name}-${var.environment}"

  # These "tags" are like sticky labels on every Azure resource.
  # They help you filter costs, find resources, and know who owns them.
  common_tags = {
    vm_name     = var.vm_name
    environment = var.environment
    owner       = var.owner_email
    provisioned_by = "ServiceNow + Terraform"
    created_on  = timestamp()
  }
}

# =============================================================================
# RESOURCE 1: Resource Group
# =============================================================================
# WHY: In Azure, EVERYTHING must live inside a Resource Group.
# It's like a "project folder" in Azure. When you delete the resource group,
# it deletes everything inside it too.
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}"   # e.g. rg-test-vm-01-staging
  location = var.location
  tags     = local.common_tags
}

# =============================================================================
# RESOURCE 2: Virtual Network (VNet)
# =============================================================================
# WHY: Azure VMs can't just float in the internet. They need a private network.
# The VNet is like a private neighbourhood. Only resources inside it can
# talk to each other by default.
# 10.0.0.0/16 means we can have up to 65,536 IP addresses in this network.
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.prefix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# =============================================================================
# RESOURCE 3: Subnet
# =============================================================================
# WHY: A VNet is divided into Subnets, like dividing a neighbourhood into streets.
# Our VM will sit on this subnet. 10.0.1.0/24 gives us 256 IP addresses.
resource "azurerm_subnet" "main" {
  name                 = "subnet-${local.prefix}"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

# =============================================================================
# RESOURCE 4: Public IP Address
# =============================================================================
# WHY: By default, VMs only have a private IP (only reachable inside the VNet).
# We need a Public IP so we can SSH into the VM from the internet,
# and so Ansible can connect to it to install software.
resource "azurerm_public_ip" "main" {
  name                = "pip-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"   # Static = the IP doesn't change on restart
  sku                 = "Standard"
  tags                = local.common_tags
}

# =============================================================================
# RESOURCE 5: Network Interface Card (NIC)
# =============================================================================
# WHY: This is the "network adapter" that connects the VM to the subnet AND
# to the public IP. Without this, the VM has no network connection.
resource "azurerm_network_interface" "main" {
  name                = "nic-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# =============================================================================
# RESOURCE 6: Network Security Group (Firewall Rules)
# =============================================================================
# WHY: By default, Azure blocks ALL inbound traffic. We need to explicitly
# open port 22 (SSH) so we can connect to the VM.
# Think of this as the firewall/bouncer at the door.
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${local.prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"      # Port 22 = SSH
    source_address_prefix      = "*"       # Allow from anywhere (restrict in production!)
    destination_address_prefix = "*"
  }
}

# Attach the NSG to the NIC so the rules apply to our VM
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# =============================================================================
# RESOURCE 7: The Actual Virtual Machine! 🖥️
# =============================================================================
# WHY: Finally! This is the VM itself. It references the NIC we created above.
# The admin_ssh_key block means we log in with SSH keys (more secure than passwords).
resource "azurerm_linux_virtual_machine" "main" {
  name                = var.vm_name                        # e.g. "phase-5"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size                        # e.g. "Standard_B1s"
  admin_username      = "azureuser"                        # default Linux user

  # Connect the VM to the NIC (which connects it to the subnet + public IP)
  network_interface_ids = [azurerm_network_interface.main.id]

  # SSH Key Authentication (no password login — more secure!)
  # WHY a variable: GitHub Actions writes the key from a Secret into this variable.
  # We can't use file() here because GitHub's server won't have a local file.
  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  # The disk the OS is installed on
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"   # Standard SSD (cheapest)
  }

  # The OS image to install
  # Ubuntu 22.04 LTS — Long Term Support means it's stable and supported for years
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = local.common_tags
}
