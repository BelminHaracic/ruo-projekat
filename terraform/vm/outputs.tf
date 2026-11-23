output "vm_ip" {
  value = libvirt_domain.vm.network_interface[0].addresses[0]
}

output "admin_user" {
  value = var.admin_user
}
