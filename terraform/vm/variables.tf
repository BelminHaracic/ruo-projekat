variable "vm_name" {
  type    = string
  default = "app1"
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "vcpu" {
  type    = number
  default = 2
}

variable "disk_gb" {
  type    = number
  default = 20
}

variable "pool" {
  type    = string
  default = "default"
}

variable "network" {
  type    = string
  default = "default"
}

variable "admin_user" {
  type    = string
  default = "student"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "base_image_url" {
  type    = string
  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}
