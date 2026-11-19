# Exercise 6 — шпаргалка Terraform + Ansible + AWS + Java + MySQL

> Навчальний проєкт. Команди виконуються **на Mac** або **на Ansible Control Server** — це важливо. IP-адреси EC2 змінюються після повторного `terraform apply`.

## 1. Архітектура

```text
Mac ──SSH/Ansible──> Control EC2 (public subnet)
                          │ SSH
                          ├──> Web EC2 (public subnet): Java / Spring Boot :8080
                          │                                  │ JDBC :3306
                          └──> DB EC2 (private subnet) <─────┘
                                                       MySQL / java-app-db
```

Terraform створює VPC, підмережі, маршрути, Internet/NAT Gateways, Security Groups, EC2 та генерує `ansible/inventory-terraform.ini`.

## 2. Підготувати Java JAR — Mac, корінь репозиторію

```bash
gradle clean build
ansible-playbook -i localhost, ansible/build-app.yaml
```

Перевір, що артефакт скопійовано в `ansible/files/java-app-1.0-SNAPSHOT.jar`.

## 3. Створити AWS — Mac, каталог `terraform/`

```bash
cd terraform
terraform init
terraform fmt
terraform validate
terraform plan -var="my_ip=$(curl -fsS -4 https://checkip.amazonaws.com | tr -d '\n')/32"
terraform apply -var="my_ip=$(curl -fsS -4 https://checkip.amazonaws.com | tr -d '\n')/32"
terraform output
```

- `my_ip` — поточна публічна IPv4-адреса Mac, обмежена маскою `/32`.
- Terraform генерує `../ansible/inventory-terraform.ini`. Файл **не комітити**: його адреси тимчасові.
- Запиши з `terraform output` **новий** `control_public_ip`.

## 4. Налаштувати Control Server — Mac, каталог `ansible/`

```bash
cd ../ansible
ansible --version | grep 'config file'
ansible-playbook -i inventory-terraform.ini configure-ansible-server.yaml \
  --private-key ~/.ssh/ansible-jenkins.pem
```

Підключення (підставити актуальний IP):

```bash
ssh -A -i ~/.ssh/ansible-jenkins.pem ubuntu@<CONTROL_PUBLIC_IP>
```

`-A` вмикає SSH-agent forwarding; застосовуй лише для довіреного Control Server.

## 5. Налаштувати DB і Web — **на Control Server**

```bash
cd ~/ansible-project
ls -l configure-app-servers.yaml inventory-terraform.ini
ansible-playbook -i inventory-terraform.ini configure-app-servers.yaml --ask-vault-pass
```

Очікувано: `PLAY RECAP` з `failed=0`, `unreachable=0` для `db` і `web`.

## 6. Перевірити MySQL — **на Control Server**

Перевірити таблицю:

```bash
ansible -i inventory-terraform.ini db_server -b \
  -m ansible.builtin.command \
  -a "mysql -N -e 'SHOW TABLES FROM \`java-app-db\`;'"
```

Очікувано: `team_members`.

Додати або оновити тестовий запис:

```bash
ansible -i inventory-terraform.ini db_server -b \
  -m ansible.builtin.command \
  -a "mysql java-app-db -e \"INSERT INTO team_members (member_name, member_role) VALUES ('Test User', 'Developer') ON DUPLICATE KEY UPDATE member_role='Developer';\""
```

## 7. Перевірити Java API — **на Control Server**

Візьми `web_private_ip` із поточного `terraform output` або `inventory-terraform.ini` і підстав замість `<WEB_PRIVATE_IP>`.

```bash
curl --connect-timeout 5 --max-time 10 -i http://<WEB_PRIVATE_IP>:8080/get-data
```

Після додавання тестового запису:

```json
[{"name":"Test User","role":"Developer"}]
```

Оновити роль через POST:

```bash
curl -sS -X POST http://<WEB_PRIVATE_IP>:8080/update-roles \
  -H 'Content-Type: application/json' \
  -d '[{"name":"Test User","role":"DevOps Engineer"}]'

curl -sS http://<WEB_PRIVATE_IP>:8080/get-data
```

Очікувано: `"role":"DevOps Engineer"` — зміна збереглася в MySQL.

## 8. Діагностика проблем

### `Host key verification failed`

**На Mac**, у `ansible/`:

```bash
ansible --version | grep 'config file'
```

Перевір, що використовується `ansible/ansible.cfg`. Налаштування `StrictHostKeyChecking=accept-new` приймає **нові**, але не **змінені** ключі. Якщо ключ для повторно використаної IP-адреси змінився, спочатку незалежно перевір відбиток ключа нового EC2; лише після перевірки видали застарілий запис:

```bash
ssh-keygen -R <CONTROL_PUBLIC_IP>
```

### `curl` зависає або `Connection timed out`

1. **На Control Server** перевір, чи Java слухає `8080`:

```bash
ansible -i inventory-terraform.ini web_server -b \
  -m ansible.builtin.shell -a "ss -lntp | grep ':8080' || true"
```

2. Перевір API локально **на Web Server** через Ansible:

```bash
ansible -i inventory-terraform.ini web_server \
  -m ansible.builtin.command \
  -a "curl --max-time 10 -i http://127.0.0.1:8080/get-data"
```

3. Якщо локально `200 OK`, а з Control Server timeout — перевір ingress-правило AWS Security Group Web на TCP `8080` з `aws_security_group.control.id`.

4. **Приватна адреса `10.x.x.x` недоступна напряму з Mac** без VPN/тунелю. Перевір її з Control Server. Публічний Web IP можна використовувати з Mac, лише якщо Security Group дозволяє доступ з поточної публічної IP Mac.

### `/get-data` повертає `[]`

Це може означати порожню таблицю, **але не доводить**, що SQL-запит успішний: поточний Java-код перехоплює SQL-помилки та може повернути `[]`. Перевір `team_members`, додай тестовий запис, повтори GET, за потреби подивись логи Java-служби.

### `PLAY RECAP` має `failed` або `unreachable`

Дивись першу помилку `TASK`, перевір inventory, SSH-доступ, `ansible.cfg`, Security Groups і пароль Ansible Vault. `--syntax-check` перевіряє синтаксис playbook, але **не гарантує** виконання SQL чи доступності AWS.

## 9. Безпека та Git — Mac

- Не коміть `.pem`, `.tfstate`, `.tfvars` із секретами, розшифрований Vault або `inventory-terraform.ini`.
- MySQL розміщено у приватній підмережі; `8080` відкритий лише для дозволених джерел.
- Не відкривай `3306` або `8080` для `0.0.0.0/0` без потреби.
- Поточне SQL-оновлення в Java формує запит із рядка; для реального застосунку використовуй `PreparedStatement`.

```bash
git status --short
git diff --check
git add README.md CHEATSHEET.md
git commit -m "Document Exercise 6 deployment and troubleshooting"
git push
```

Команди Git запускай **із кореня репозиторію**, де розташовані обидва Markdown-файли.

## 10. Видалити AWS-ресурси — Mac, `terraform/`

> **Увага:** це видалить EC2, мережеві ресурси й тестові дані MySQL. Перед підтвердженням уважно перевір план видалення. NAT Gateway та EC2 можуть коштувати грошей, доки існують.

```bash
cd terraform
terraform destroy -var="my_ip=$(curl -fsS -4 https://checkip.amazonaws.com | tr -d '\n')/32"
```

Після підтвердження очікувано: `Destroy complete!`.

**Статус Exercise 6:** Terraform + Ansible + Java + MySQL розгорнуто й перевірено; Jenkins — окремий наступний етап.
