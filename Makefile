# Bilježnica - troslojna aplikacija kao kod
# Redoslijed: make all  (check -> infra -> config -> dns -> deploy), zatim make test

TF_VM     = terraform -chdir=terraform/vm
TF_DNS    = ./scripts/tf-dns.sh
IMAGE     = $(shell sed -n 's/^base_image_url *= *"\(.*\)"/\1/p' terraform/vm/terraform.tfvars)
IMAGE_URL = https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
SSH_OPTS  = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR

# nikad dva playbooka istovremeno
.NOTPARALLEL:
.PHONY: check image infra config dns deploy test all destroy

check:
	@for t in terraform ansible-playbook ansible-vault virsh dig nsupdate ssh curl wget openssl python3; do \
	  command -v $$t >/dev/null || { echo "nedostaje alat: $$t"; exit 1; }; done
	@test -f $(HOME)/.ssh/id_ed25519.pub || { echo "nedostaje ~/.ssh/id_ed25519.pub (ssh-keygen -t ed25519)"; exit 1; }
	@virsh -c qemu:///system net-info default | grep -q 'Active:.*yes' || { echo "libvirt mreza default nije aktivna"; exit 1; }
	@echo "check OK"

# slika se skida samo ako je nema (Terraform download je padao na timeout)
image:
	@mkdir -p $(dir $(IMAGE))
	@test -f $(IMAGE) || { wget -c -O $(IMAGE).part $(IMAGE_URL) && mv $(IMAGE).part $(IMAGE); }
	@echo "slika: $(IMAGE)"

infra: image
	$(TF_VM) init -input=false
	$(TF_VM) apply -auto-approve -input=false

config:
	cd ansible && ./vault-init.sh && ansible-playbook site.yml

dns:
	terraform -chdir=terraform/dns init -input=false
	$(TF_DNS) apply -auto-approve -input=false

deploy:
	cd ansible && ansible-playbook deploy.yml

test:
	@IP=$$($(TF_VM) output -raw vm_ip); USR=$$($(TF_VM) output -raw admin_user); \
	echo "##### DNS"; ./tests/dns.sh $$IP || exit 1; \
	echo "##### Izolacija (na VM)"; ssh $(SSH_OPTS) $$USR@$$IP 'bash -s' < tests/izolacija.sh || exit 1; \
	echo "##### Aplikacija"; ./tests/aplikacija.sh $$IP

all: check infra config dns deploy

# prvo DNS zapisi (dok BIND jos radi), pa VM
destroy:
	-$(TF_DNS) destroy -auto-approve -input=false
	$(TF_VM) destroy -auto-approve -input=false
