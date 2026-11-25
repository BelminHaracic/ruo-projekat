# Bilježnica – troslojna aplikacija kao kod

Projektni zadatak iz predmeta **Računarstvo u oblaku**, Politehnički fakultet Univerziteta u Zenici, 2026/27.
Autor: Belmin Haračić

Cijela infrastruktura za jednostavnu web aplikaciju je opisana kodom: virtuelna mašina (Terraform + libvirt),
početna konfiguracija (cloud-init), konfiguracija servera (Ansible role), kontejneri (Docker Compose),
segmentirana mreža (Docker mreže) i DNS (BIND + DNS zapisi kao Terraform resursi).

Aplikacija "Bilježnica" je mali CRUD za bilješke: dodavanje, pregled i brisanje. Sama aplikacija nije
poenta projekta, služi da postoje tri sloja koji stvarno komuniciraju.

| Sloj     | Tehnologija               | Kontejner  |
|----------|---------------------------|------------|
| frontend | Nginx 1.27 (statički HTML + reverse proxy na `/api/`) | `frontend` |
| backend  | Python 3.12, FastAPI, psycopg 3 | `backend` |
| baza     | PostgreSQL 16 (alpine) + named volume `pgdata` | `db` |
| DNS      | BIND 9.18, zona `biljeznica.lab` | `dns` |

Tok zahtjeva je samo **frontend → backend → baza**.

---

## 1. Arhitektura (stvarni raspored)

Izabrana je opcija A iz DO-2: jedna VM `app1`, a segmenti su Docker mreže s fiksnim podmrežama.
Svaki kontejner je samo na mrežama koje mu trebaju.

```
 WSL2 (Ubuntu) – administrator: terraform, ansible, make
 │
 │  libvirt mreža "default" (NAT, 192.168.122.0/24)
 │
 └── VM app1 (Ubuntu 24.04, 2 vCPU, 2 GB RAM, 20 GB, IP iz DHCP-a, trenutno 192.168.122.17)
      │
      │  objavljeni portovi na IP adresi VM-a:  8080/tcp -> frontend,  53/udp+tcp -> dns
      │
      ├── mreža web  172.28.1.0/24  (bridge, jedina koja ima izlaz)
      │     ├── frontend  172.28.1.10   ← jedini ulaz za korisnike (:8080)
      │     └── dns       172.28.1.2
      │
      ├── mreža app  172.28.2.0/24  (internal)
      │     ├── frontend  172.28.2.10
      │     ├── backend   172.28.2.20
      │     └── dns       172.28.2.2
      │
      └── mreža db   172.28.3.0/24  (internal)
            ├── backend   172.28.3.20
            ├── db        172.28.3.30   (port 5432 NIJE objavljen)
            └── dns       172.28.3.2

 frontend --X--> db : frontend nije na mreži db, pa nema mrežnog puta (provjerava tests/izolacija.sh)
```

## 2. Plan adresiranja i izolacija

| Segment | Podmreža        | Tip      | Kontejneri (adresa)                                   |
|---------|-----------------|----------|-------------------------------------------------------|
| web     | 172.28.1.0/24   | bridge   | frontend (.10), dns (.2)                              |
| app     | 172.28.2.0/24   | internal | frontend (.10), backend (.20), dns (.2)               |
| db      | 172.28.3.0/24   | internal | backend (.20), db (.30), dns (.2)                     |
| VM      | 192.168.122.0/24 | libvirt NAT | app1 (DHCP)                                       |

Adrese kontejnera su fiksne (`ipv4_address` u `app/compose.yaml`) zato što DNS zapisi u Terraformu
moraju pokazivati na adresu koja se ne mijenja pri svakom ponovnom kreiranju kontejnera.

Kako je urađena izolacija:

- `app` i `db` su `internal: true`, nemaju izlaz van VM-a i Docker na njih ne može objaviti port.
- frontend je na `web` i `app`, backend na `app` i `db`, a baza samo na `db`. Frontend i baza nemaju
  zajedničku mrežu, a Docker ne rutira između različitih mreža, pa frontend do baze ne može doći ni po imenu ni po IP-u.
- Izvana je objavljen samo frontend (`8080`). Baza nema `ports:`.
- DNS kontejner je na sve tri mreže da bi ga svaki sloj mogao koristiti kao resolver. Na `web` je zato
  što se port 53 može objaviti samo preko mreže koja nije internal (Terraform s hosta šalje RFC 2136 update).
  Kontejner ne prosljeđuje pakete između mreža, pa to ne otvara put frontend → baza.
- Mreža VM-a je libvirt NAT, tako da su portovi 8080 i 53 dostupni samo s hosta.

**Imenovanje (AO-7):** komponente se adresiraju isključivo DNS imenima. nginx radi `proxy_pass` na
`backend.biljeznica.lab:8000`, a backend se spaja na `db.biljeznica.lab`. Frontend i backend dobijaju
BIND kao resolver preko `dns:` u compose fajlu. IP adrese se u kodu pojavljuju samo tamo gdje drugačije
ne može: u planu adresiranja (compose `ipam`/`ipv4_address`), u adresi resolvera (`dns:`) i u samim DNS zapisima
(`terraform/dns`).

## 3. DNS

- Zona `biljeznica.lab`, TTL 300, BIND 9.18 u kontejneru `dns`.
- Ansible postavlja samo prazan "kostur" zone (SOA, NS, `ns` A zapis) i `named.conf`.
- Zapisi `frontend`, `backend`, `db` (A) i TXT `upravlja: terraform` su Terraform resursi
  (`terraform/dns/main.tf`, provider `hashicorp/dns`, RFC 2136 dinamički update).
- TSIG ključ `ruo-tf` (hmac-sha256) ima `update-policy { grant ruo-tf zonesub ANY; }`, znači smije mijenjati samo
  imena unutar zone `biljeznica.lab`. Update bez ključa server odbija (`REFUSED`, vidi testove).
- Zona je na named volumenu `bindzone`, pa dinamički zapisi (journal) preživljavaju restart kontejnera.

## 4. Tajne

- `vault_postgres_password` i `vault_tsig_secret` su u `ansible/group_vars/app/vault.yml`, šifrovano s `ansible-vault`.
- Generiše ih `ansible/vault-init.sh` pri prvom pokretanju (`openssl rand`), zajedno s `.vault_pass`.
  Ako fajlovi već postoje, skripta ih ne dira.
- U Gitu je samo `vault.yml.example`. `vault.yml`, `.vault_pass`, `*.tfstate`, `.terraform/`, `.env`,
  `ansible/inventory.ini` i ključevi su u `.gitignore` i nikad nisu bili commitani.
- Terraform za DNS dobija TSIG tajnu kroz `scripts/tf-dns.sh`, koji je čita iz vaulta i prosljeđuje kao
  `TF_VAR_tsig_secret`. Tajna ne završava ni u jednom fajlu.
- `.env` na VM-u pravi Ansible iz šablona (`env.j2`, mode 0600).

## 5. Struktura repozitorija

```
projekat/
├── app/
│   ├── frontend/        # nginx.conf, index.html, Dockerfile
│   ├── backend/         # FastAPI (main.py), multi-stage Dockerfile
│   ├── dns/             # BIND slika + kostur zone
│   └── compose.yaml     # 4 servisa, 3 mreže, 2 volumena
├── terraform/
│   ├── vm/              # VM, diskovi, cloud-init ISO, generisanje inventory-ja
│   └── dns/             # DNS zapisi (A + TXT)
├── cloud-init/          # user-data.tftpl
├── ansible/             # role docker, dns, app; site.yml, deploy.yml, vault-init.sh
├── scripts/tf-dns.sh    # terraform za DNS s tajnom iz vaulta
├── tests/               # izolacija.sh, dns.sh, aplikacija.sh, drift-dns.sh
├── docs/dokazi/         # sačuvani izlazi naredbi
├── Makefile
└── README.md
```

Odstupanja od preporučene strukture: `app/dns/` (BIND je dio istog compose projekta kao aplikacija),
`scripts/` (pomoćna skripta za Terraform DNS) i `docs/dokazi/`.

## 6. Pokretanje od praznog računara

### 6.1 Preduslovi

Testirano na Windows 11 + WSL2 (Ubuntu 24.04).

```bash
sudo apt update
sudo apt install -y qemu-system-x86 libvirt-daemon-system libvirt-clients \
    ansible bind9-dnsutils curl wget openssl python3 git make
sudo usermod -aG libvirt $USER          # zatim zatvoriti i ponovo otvoriti terminal
```

Terraform se instalira po uputama s hashicorp.com (apt repozitorij). Zatim:

```bash
ssh-keygen -t ed25519                   # ako ključ ne postoji, Terraform ga ubacuje u cloud-init
virsh -c qemu:///system net-start default        # ako mreža nije aktivna
virsh -c qemu:///system net-autostart default
```

> **Napomena o KVM-u:** u mom WSL2 okruženju KVM akceleracija ne radi (`/dev/kvm` postoji, ali libvirt
> javlja `accel 'kvm' is not supported`). Zato je u `terraform/vm/main.tf` postavljeno `type = "qemu"`,
> pa VM radi pod softverskom emulacijom. Sve radi isto, samo sporije: podizanje od nule traje
> oko [X] minuta. Na računaru s ispravnim KVM-om dovoljno je promijeniti `type` u `"kvm"`.
> Detaljnije u ADR-u za DO-2.

### 6.2 Podizanje, test i uklanjanje

```bash
git clone <link na repozitorij> projekat && cd projekat
make check      # da li su svi alati tu, SSH ključ, libvirt mreža
make all        # image -> infra -> config -> dns -> deploy
make test       # DNS, izolacija, aplikacija
make destroy    # brisanje DNS zapisa, pa VM-a
```

Aplikacija je nakon `make all` na `http://<vm_ip>:8080` (`terraform -chdir=terraform/vm output vm_ip`).

Šta radi svaki cilj (isto se može pokrenuti i ručno, ovim redoslijedom):

| Cilj | Naredbe |
|------|---------|
| `image`  | skine Ubuntu 24.04 cloud sliku u putanju iz `terraform/vm/terraform.tfvars`, samo ako je nema |
| `infra`  | `terraform -chdir=terraform/vm init` i `apply` (VM, diskovi, cloud-init ISO, `ansible/inventory.ini`) |
| `config` | `ansible/vault-init.sh`, pa `ansible-playbook site.yml` (čeka SSH i cloud-init, Docker, BIND) |
| `dns`    | `terraform -chdir=terraform/dns init`, pa `./scripts/tf-dns.sh apply` |
| `deploy` | `ansible-playbook deploy.yml` (kopira kod, `docker compose up -d`) |
| `test`   | `tests/dns.sh`, `tests/izolacija.sh` (preko SSH na VM-u), `tests/aplikacija.sh` |
| `destroy`| `./scripts/tf-dns.sh destroy`, pa `terraform -chdir=terraform/vm destroy` |

Redoslijed je bitan: BIND mora raditi prije `make dns`, a DNS zapisi moraju postojati prije `deploy`,
jer nginx pri startu razrješava `backend.biljeznica.lab`. Kod brisanja je obrnuto: prvo se brišu DNS
zapisi dok BIND još radi, pa tek onda VM. Playbookovi se nikad ne pokreću paralelno (`.NOTPARALLEL` u Makefileu).

### 6.3 Ponovno pokretanje VM-a

Svi kontejneri imaju `restart: unless-stopped`, a Docker servis je `enabled`. Nakon `virsh start app1`
cijeli stack se digne sam, `/api/ready` vraća `{"status":"ready"}`.

## 7. Idempotentnost (AO-5)

Drugo izvršavanje playbooka mora dati `changed=0`. Za `docker compose up` (task `command`) Ansible ne zna
sam da li se nešto promijenilo, pa:

- `--build` se dodaje samo kad je task kopiranja koda javio promjenu (`kod.changed`). Ranije se slika gradila
  pri svakom pokretanju, kontejneri su se ponovo kreirali i task je uvijek bio `changed`;
- `changed_when` gleda samo statusne redove kontejnera (`Container ... Created|Recreated|Started`), a ne build log.

Izlaz drugog izvršavanja `deploy.yml` (`docs/dokazi/ansible-drugo-izvrsavanje.txt`):

```
PLAY [Isporuka aplikacije] *****************************************************

TASK [Gathering Facts] *********************************************************
ok: [app1]

TASK [app : Kod aplikacije (frontend, backend, compose)] ***********************
ok: [app1] => (item=frontend)
ok: [app1] => (item=backend)
ok: [app1] => (item=compose.yaml)

TASK [app : Pokretanje aplikacije] *********************************************
ok: [app1]

PLAY RECAP *********************************************************************
app1                       : ok=3    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`terraform plan` nakon `apply` (`docs/dokazi/tf-vm-plan.txt`):

```
No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
```

## 8. Drift DNS zapisa (AO-8)

`tests/drift-dns.sh` napravi drift namjerno: preko `nsupdate` (s TSIG ključem, mimo Terraforma) promijeni
`backend.biljeznica.lab` sa `172.28.2.20` na `172.28.2.99`. `terraform plan` to primijeti, a `apply` vrati
zapis na vrijednost iz koda. Skraćen izlaz (cijeli je u `docs/dokazi/drift-dns.txt`):

```
### prije: 172.28.2.20
### nakon rucne izmjene: 172.28.2.99
### terraform plan
  # dns_a_record_set.servis["backend"] will be updated in-place
  ~ resource "dns_a_record_set" "servis" {
      ~ addresses = [
          - "172.28.2.99",
          + "172.28.2.20",
        ]
        id        = "backend.biljeznica.lab."
        name      = "backend"
        # (2 unchanged attributes hidden)
    }

Plan: 0 to add, 1 to change, 0 to destroy.
### terraform apply
dns_a_record_set.servis["backend"]: Modifying... [id=backend.biljeznica.lab.]
dns_a_record_set.servis["backend"]: Modifications complete after 0s [id=backend.biljeznica.lab.]

Apply complete! Resources: 0 added, 1 changed, 0 destroyed.
### poslije ispravke: 172.28.2.20
### ponovni plan
No changes. Your infrastructure matches the configuration.
```

## 9. Testovi

`make test` (`docs/dokazi/testovi.txt`):

```
##### DNS
PASS frontend.biljeznica.lab -> 172.28.1.10
PASS backend.biljeznica.lab -> 172.28.2.20
PASS db.biljeznica.lab -> 172.28.3.30
PASS ns.biljeznica.lab -> 172.28.2.2
TXT: "upravlja: terraform"
SOA: ns.biljeznica.lab. admin.biljeznica.lab. 7 3600 600 86400 300
PASS update bez kljuca -> REFUSED
##### Izolacija (na VM)
== 1: frontend -> backend.biljeznica.lab:8000 mora PROCI (kontrola da nc radi)
PASS
== 2: frontend razrjesava db.biljeznica.lab (DNS radi, pa pad u testu 3 nije zbog imena)
Name:   db.biljeznica.lab
Address: 172.28.3.30
== 3: frontend -> db.biljeznica.lab:5432 mora PASTI (nema mreznog puta)
PASS
== 4: backend -> db.biljeznica.lab:5432 mora PROCI
PASS
== 5: port 5432 nije otvoren na VM-u
PASS
== 6: podaci baze su na volumenu (AO-10)
/var/lib/docker/volumes/biljeznica_pgdata/_data
PASS
##### Aplikacija
{"status":"ready"}  PASS ready
PASS dodana biljeska id=2
PASS biljeska se vidi u listi
PASS obrisana biljeska 2
PASS 5432 nije dostupan izvana
```

Test 1 je kontrola: isti `nc` iz frontenda uspije do backenda, pa pad u testu 3 sigurno znači da nema mrežnog
puta, a ne da alat ne radi. Test 2 pokazuje da frontend uredno razriješi `db.biljeznica.lab` preko BIND-a,
dakle veza ne pada zbog imena.

**AO-10 (podaci preživljavaju ponovno kreiranje baze):** provjereno ručno na VM-u:

```bash
cd /opt/biljeznica
curl -X POST localhost:8080/api/notes -H 'Content-Type: application/json' -d '{"tekst":"ostaje"}'
sudo docker compose rm -sf db && sudo docker compose up -d db
curl localhost:8080/api/notes        # bilješka "ostaje" je i dalje tu
```

## 10. Poznata ograničenja

- VM radi pod QEMU emulacijom (bez KVM-a), pa je sve osjetno sporije, posebno build slika i podizanje od nule.
- Bazna slika se skida kroz `make image` (`wget -c`), a ne kroz Terraform, jer je preuzimanje iz libvirt
  providera padalo na timeout.
- Adresa VM-a dolazi iz DHCP-a libvirt mreže. Terraform je vraća kao output i iz nje generiše inventory,
  pa se nigdje ne upisuje ručno.
