terraform {
  required_providers {
    dns = { source = "hashicorp/dns", version = "~> 3.4" }
  }
}

variable "dns_server" {
  type = string
}

variable "tsig_secret" {
  type      = string
  sensitive = true
}

variable "zona" {
  type    = string
  default = "biljeznica.lab."
}

variable "servisi" {
  type = map(string)
  default = {
    frontend = "172.28.1.10"
    backend  = "172.28.2.20"
    db       = "172.28.3.30"
  }
}

provider "dns" {
  update {
    server        = var.dns_server
    port          = 53
    key_name      = "ruo-tf."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_secret
  }
}

resource "dns_a_record_set" "servis" {
  for_each  = var.servisi
  zone      = var.zona
  name      = each.key
  addresses = [each.value]
  ttl       = 300
}

resource "dns_txt_record_set" "vlasnik" {
  zone = var.zona
  txt  = ["upravlja: terraform"]
  ttl  = 300
}

output "imena" {
  value = [for k, _ in dns_a_record_set.servis : "${k}.${var.zona}"]
}
