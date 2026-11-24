resource "local_file" "inventory" {
  filename = "${path.module}/../../ansible/inventory.ini"
  content  = <<-EOT
    [app]
    ${var.vm_name} ansible_host=${libvirt_domain.vm.network_interface[0].addresses[0]} ansible_user=${var.admin_user}
  EOT
}
