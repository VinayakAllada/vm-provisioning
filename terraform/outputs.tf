# =============================================================================
# outputs.tf — Values that Terraform "returns" after it finishes building
# =============================================================================
#
# WHY DO WE NEED OUTPUTS?
# After Terraform builds everything, we need some information back.
# Most importantly, we need the PUBLIC IP ADDRESS of the new VM so that:
#   1. We can tell the user "Your VM is ready at 20.x.x.x"
#   2. Ansible knows which IP to SSH into to install software (Phase 6)
#   3. We can update the ServiceNow RITM ticket with the VM's details
#
# ANALOGY: It's like a function's return value.
#   function buildVM() { 
#     ... build everything ...
#     return { ip: "20.x.x.x", name: "my-vm" }
#   }
# =============================================================================

output "public_ip_address" {
  description = "The public IP address of the newly created VM"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_name" {
  description = "The name of the created Virtual Machine"
  value       = azurerm_linux_virtual_machine.main.name
}

output "resource_group_name" {
  description = "The Resource Group where all VM resources were created"
  value       = azurerm_resource_group.main.name
}

output "ssh_command" {
  description = "Ready-to-use SSH command to connect to your new VM"
  value       = "ssh azureuser@${azurerm_public_ip.main.ip_address}"
}
