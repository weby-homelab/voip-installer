<p align="center">
  <a href="README_ENG.md">
    <img src="https://img.shields.io/badge/🇬🇧_English-00D4FF?style=for-the-badge&logo=readme&logoColor=white" alt="English README">
  </a>
  <a href="README.md">
    <img src="https://img.shields.io/badge/🇺🇦_Українська-FF4D00?style=for-the-badge&logo=readme&logoColor=white" alt="Українська версія">
  </a>
</p>

<br>

# 🛡️ VoIP Server Installer

[![Version](https://img.shields.io/github/v/tag/weby-homelab/voip-installer?label=version&style=flat-square)](https://github.com/weby-homelab/voip-installer/tags)
[![ShellCheck](https://img.shields.io/github/actions/workflow/status/weby-homelab/voip-installer/lint.yml?label=ShellCheck&style=flat-square)](https://github.com/weby-homelab/voip-installer/actions/workflows/lint.yml)
[![Test Deploy](https://img.shields.io/github/actions/workflow/status/weby-homelab/voip-installer/test-install.yml?label=Test%20Deploy&style=flat-square)](https://github.com/weby-homelab/voip-installer/actions/workflows/test-install.yml)
[![License](https://img.shields.io/github/license/weby-homelab/voip-installer?style=flat-square)](LICENSE)

**Безпечне та автоматизоване розгортання Asterisk на Ubuntu 24.04**

> Готовий установник захищеного VoIP-сервера: **Asterisk 22** (Docker) + **PJSIP** + шифрування **TLS/SRTP** + **Let's Encrypt** SSL + **Fail2Ban** та **NFTables**. Створений для приватності та простоти використання.

---

## 🚀 Покроковий сценарій розгортання на чистому VPS

Коли ви запускаєте `install.sh` на чистому сервері Ubuntu/Debian, скрипт повністю автоматизує процес розгортання крок за кроком:

```mermaid
graph TD
    %% Styling Classes
    classDef init fill:#1e1e2e,stroke:#313244,stroke-width:1px,color:#cdd6f4;
    classDef prep fill:#1e1e2e,stroke:#f5c2e7,stroke-width:2px,color:#f5c2e7;
    classDef config fill:#1e1e2e,stroke:#89b4fa,stroke-width:2px,color:#89b4fa;
    classDef security fill:#1e1e2e,stroke:#f38ba8,stroke-width:2px,color:#f38ba8;
    classDef deploy fill:#1e1e2e,stroke:#a6e3a1,stroke-width:2px,color:#a6e3a1;

    %% Nodes
    A[Старт: root@VPS] --> B[1. Підготовка системи та залежностей]:::prep
    B --> B1[Оновлення apt та встановлення утиліт: curl, fail2ban, nftables, certbot]:::prep
    B --> B2[Встановлення офіційного Docker CE]:::prep
    B --> B3[Встановлення лімітів логів journald та docker daemon]:::prep

    B3 --> C[2. Налаштування директорій та сертифікатів]:::config
    C --> C1[Створення робочих папок: /root/voip-server]:::config
    C --> C2[Генерація users.env з випадковими паролями]:::config
    C --> C3[Отримання Let's Encrypt SSL сертифіката]:::config
    C --> C4[Створення deploy-hook для автооновлення SSL сертифікатів]:::config

    C4 --> D[3. Конфігурація Asterisk]:::config
    D --> D1[Копіювання конфігів з Docker-образу]:::config
    D --> D2[Генерація rtp.conf, logger.conf, modules.conf, extensions.conf]:::config
    D --> D3[Генерація pjsip.conf та pjsip_wizard.conf з обліковими записами]:::config
    D --> D4[Генерація docker-compose.yml та виправлення прав доступу]:::config

    D5 --> E[4. Фаєрвол та Захист]:::security
    D --> D5[Визначення порту SSH для уникнення блокування]:::security
    E --> E1[Генерація строгого /etc/nftables.conf: policy drop]:::security
    E --> E2[Генерація /etc/fail2ban/jail.local з моніторингом Asterisk та SSH]:::security
    E --> E3[Посилення безпеки SSH: PasswordAuthentication no]:::security

    E3 --> F[5. Запуск та клієнтський доступ]:::deploy
    F --> F1[Запуск контейнера Asterisk через docker compose]:::deploy
    F --> F2[Генерація QR-кодів підключення для софтфонів]:::deploy
    F --> G([Завершено: VoIP розгорнуто!]):::deploy

    %% Class assignment
    class A,B1,B2,B3 init;
    class C1,C2,C3,C4,D1,D2,D3,D4,D5 config;
    class E1,E2,E3 security;
    class F1,F2,G deploy;
```

> [!WARNING]
> ### 🚨 КРИТИЧНЕ ПОПЕРЕДЖЕННЯ (ЗАГРОЗА БЛОКУВАННЯ)
> Оскільки наприкінці встановлення скрипт вимикає парольну автентифікацію SSH (`PasswordAuthentication no`), ви **ОБОВ'ЯЗКОВО** повинні додати свій публічний SSH-ключ у `/root/.ssh/authorized_keys` перед запуском скрипта. Якщо ви цього не зробите, після завершення інсталяції та виходу з поточної сесії ви **втратите доступ до сервера**.

---

# 📞 Інструкція з розгортання Asterisk

**Версія:** `v4.7.9`(Виправлено TLS транспорт: монтування CA сертифікатів, коректні права)

Ця інструкція описує процес встановлення безпечної версії сервера VoIP (**Asterisk 22** + **PJSIP** + **TLS/SRTP** + **Fail2Ban** + **NFTables**) на чистий сервер **Ubuntu 24.04**.

### 🌟 Особливості версії

* **Суворий Firewall:** Політика `DROP` за замовчуванням. Автоматичне визначення порту SSH для захисту від блокування.
* **Авто-встановлення:** Автоматично встановлює Docker, Docker Compose, Certbot, Fail2Ban та NFTables.
* **Safe Mode:** Не скидає налаштування мережі Docker (no flush ruleset).
* **Ротація логів:** Ліміт 100MB для Systemd Journal та Docker логів.
* **Безпека:** Використовує TLS 1.3 на порту `5061`.
* **Автоматизація:** Автоматична генерація SSL через Let's Encrypt.

---

## 🛠 Крок 1. Підготовка сервера

1. **Увійдіть на сервер** через SSH під root:
```bash
ssh root@your-server-ip

```


2. **Перевірте порти:** Переконайтеся, що порти `80`, `443` та `5061` вільні.
> *Примітка: Якщо це чисте встановлення системи, порти мають бути вільні за замовчуванням.*



---

## 📝 Крок 2. Створення скрипту

1. Створіть порожній файл для скрипту:
```bash
nano install.sh

```


2. **Скопіюйте** ПОВНИЙ код скрипту (`install.sh`) у буфер обміну.
3. **Вставте** код у термінал:
* **Windows** (PuTTY/PowerShell): Натисніть **ПРАВУ** кнопку миші.
* **Mac/Linux:** `Cmd+V` або `Ctrl+Shift+V`.


4. **Збережіть та закрийте файл**:
* Натисніть `Ctrl+O`, потім `Enter`.
* Натисніть `Ctrl+X`.



---

## 🚀 Крок 3. Запуск установки

1. Надайте права на виконання:
```bash
chmod +x install.sh

```


2. **Запустіть скрипт** (замініть дані на свої):
```bash
./install.sh --domain your-domain.com --email admin@your-domain.com

```


**Параметри запуску:**
| Параметр | Опис |
| :--- | :--- |
| `--domain` | Ваше доменне ім'я (обов'язково, має бути направлено на IP сервера). |
| `--email` | Пошта для реєстрації сертифіката Let's Encrypt. |
| `--ext-ip` | *(Опціонально)* Зовнішній IP, якщо сервер за NAT. Зазвичай визначається автоматично. |

---

## ⚙️ Крок 4. Що відбудеться автоматично

Скрипт виконає наступні дії без вашої участі:

1. 🐳 Встановить **Docker**, **Docker Compose**, **Certbot**, **Fail2Ban** та **NFTables**.
2. 🔒 Отримає **SSL сертифікат** через Certbot.
3. 👤 Згенерує паролі для користувачів **100-105**.
4. 🛡️ Налаштує firewall (таблиця `inet voip_firewall`), **не ламаючи Docker**.
5. ▶️ Запустить **Asterisk** у контейнері.

---

## ✅ Крок 5. Після встановлення та перевірки

### 1. Отримання паролів SIP

Перегляньте згенеровані паролі:

```bash
cat /root/voip-server/users.env

```


### 2. Статус контейнера

Переконайтеся, що контейнер запущений та працює нормально:

```bash
docker ps

```

> **Очікується:** Статус `"Up (healthy)"`.

### 3. Перевірка Firewall

Перевірте застосування правил:

```bash
nft list table inet voip_firewall

```

### 🚨 3.1. Критична перевірка (Docker Network Safety)

Виконайте ці команди, щоб переконатися, що firewall не заблокував мережу контейнерам:

```bash
systemctl restart nftables
docker exec asterisk-voip curl -Is https://google.com | grep HTTP

```

* **Очікуваний результат:** `HTTP/2 200` (або `HTTP/1.1 200`).
* **Чому це працює:**
* *Host network:* Контейнер використовує стек/IP хоста.
* *Used accept:* Вихідний curl -> SYN -> збіг 'established' при поверненні.
* *No block outbound:* Політика за замовчуванням accept (Safe Mode).



> **Успіх:** Якщо тест проходить — Safe Mode повністю захищає мережеву зв'язність Docker.

### 4. Підключення телефону (наприклад, Linphone)

Налаштуйте софтфон, використовуючи наступні дані:

* **Username:** `100` (або 101-105)
* **Password:** *(з файлу users.env)*
* **Domain:** `your-domain.com:5061`
* **Transport:** `TLS`
* **Media Encryption:** `SRTP`
* **AVPF:** Disabled (зазвичай)
* **ICE:** Enabled

---

## 📂 Структура файлів сервера

Після встановлення сервер буде організовано наступним чином у теці `/root/voip-server/`:

```text
/root/voip-server/
├── config/
│   └── asterisk/
│       ├── pjsip.conf          # Налаштування SIP (порти, транспорт)
│       ├── extensions.conf     # Логіка діалплану (дзвінків)
│       ├── modules.conf        # Завантаження модулів
│       ├── logger.conf         # Налаштування логів
│       └── rtp.conf            # Діапазон RTP портів
├── certs/                      # SSL Сертифікати (Let's Encrypt)
├── data/                       # Бази даних Asterisk та сховище
├── logs/                       # Логи (безпека, дзвінки/CDR)
├── qr_codes/                   # QR-коди для налаштування клієнтів
├── users.env                   # SIP користувачі та паролі
└── docker-compose.yml          # Конфігурація запуску Docker
```

---

## 🏗 Архітектура та вибір образу

У проєкті використовується **`andrius/asterisk:22`** (на базі Alpine Linux) замість великовагових збірок FreePBX. Це свідомий вибір на користь **безпеки** та **продуктивності**.

```mermaid
graph TD
    User[SIP Клієнт / Софтфон]
    Net[Інтернет / WAN]
    FW[NFTables Firewall]
    F2B[Fail2Ban]
    
    subgraph Host [Сервер Ubuntu 24.04]
        FW
        F2B
        
        subgraph Docker [Docker Container: Asterisk 22]
            PJSIP[Стек PJSIP]
            RTP[Модуль RTP]
            Logs[Логи Asterisk]
        end
    end
    
    User -->|"Шифрована сигналізація (TLS:5061)"| Net
    User -->|"Шифрований голос (SRTP)"| Net
    Net --> FW
    
    FW -->|"Дозволити TLS/RTP"| PJSIP
    FW -->|"Дозволити RTP Range"| RTP
    FW -.->|"Режим Host Network"| Docker
    
    F2B -.->|"Моніторить"| Logs
    F2B -.->|"Оновлює бан-лист"| FW
```

### Чому не FreePBX?
Офіційні дистрибутиви (FreePBX) призначені для керування через GUI, тягнуть за собою Apache, MySQL, PHP та NodeJS, займаючи **>1 ГБ**. Це створює величезну поверхню для атак та ускладнює автоматизацію.

### Переваги поточного рішення:
* 🚀 **Легковагість:** Образ важить лише **~60 МБ** (проти 1 ГБ+ у аналогів).
* ⚡ **Alpine Linux & Musl:** Мінімальне споживання RAM та миттєвий старт контейнера.
* 🛡️ **Безпека (Hardened):** У контейнері **немає веб-інтерфейсу**, бази даних та зайвих сервісів. Зламати через веб-вразливість неможливо, оскільки вебу просто немає.
* 📄 **Infrastructure as Code (IaC):** Конфігурація генерується скриптом безпосередньо в `.conf` файли. Це надійніше, ніж правити налаштування в базі даних FreePBX.
* 🔧 **Чистий PJSIP:** Використовується сучасний стек SIP без легасі-коду `chan_sip`.

> **Підсумок:** Це рішення для інженерів, яким потрібен надійний, швидкий та передбачуваний VoIP-сервер, що працює за принципом "поставив і забув".

---

## 🛠 Розширене використання (Advanced Usage)

Приклади повторного запуску скрипту для внесення змін або вирішення проблем.

### 1. Оновлення конфігурації (Стандартне)
Використовуйте після `git pull` або редагування скрипту. Це перегенерує конфіги Asterisk, але ЗБЕРЕЖЕ ваші паролі та сертифікати.
```bash
./install.sh --domain your-domain.com --update
```

### 2. Зміна зовнішнього IP (NAT Fix)
Якщо автовизначення помилилося або у сервера змінився публічний IP.
```bash
./install.sh --domain your-domain.com --ext-ip 1.2.3.4 --update
```

### 3. Повне скидання паролів
Щоб згенерувати НОВІ пароли для всіх користувачів, видаліть файл зі змінними перед запуском.
**Увага:** Доведеться переналаштувати всі телефони!
```bash
rm /root/voip-server/users.env
./install.sh --domain your-domain.com --email admin@example.com --update
```

### 4. Власні сертифікати (Custom Certs)
Якщо ви не можете використовувати Let's Encrypt (наприклад, 80 порт зайнятий), вкажіть шлях до своїх файлів.
```bash
./install.sh --domain your-domain.com --cert-path /path/to/your/certs/ --update
```

---

## 🔧 Вирішення проблем (Troubleshooting)

* **Немає звуку:** Перевірте діапазон UDP `10000-19999` у панелі вашого хостингу (наприклад, Hetzner Firewall / AWS Security Group).
* **Помилка SSL:** Переконайтеся, що домен пінгується з самого сервера.
* **Логи Asterisk:**
```bash
docker logs -f asterisk-voip

```

---

# 🐙 Розгортання Asterisk з GitHub

**Репозиторий:** `weby-homelab/voip-installer`
**Мета:** Швидкий старт на чистому сервері Ubuntu 24.04

Встановлення через GitHub (`git clone`) — це набагато професійніше та надійніше, ніж копіювання тексту вручну. Це виключає помилки кодування та гарантує, що ви використовуєте останню версію коду.

Інструкція для розгортання прямо з репозиторію:

### 📋 Вимоги

* Чистий сервер **Ubuntu 24.04**.
* Права **root**.
* Домен, направлений на IP сервера.

---

## 🚀 Варіант 1: Швидке встановлення (рекомендовано)

Використовуйте цей метод для стандартного розгортання. Ми встановимо git, завантажимо репозиторій та відразу запустимо скрипт.

### Крок 1. Підготовка та клонування

Виконайте команди у консолі сервера:

```bash
# 1. Оновлюємо списки пакетів та ставимо git
apt update && apt install -y git

# 2. Клонуємо репозиторій
git clone https://github.com/weby-homelab/voip-installer.git

# 3. Переходимо в папку
cd voip-installer

```


### Крок 2. Запуск установки





Надаємо права на виконання та запускаємо скрипт з вашими параметрами:





```bash


# 1. Робимо скрипт виконуваним


chmod +x install.sh





# 2. Запускаємо (ЗАМІНІТЬ email та domain НА СВОЇ!)


./install.sh --email admin@your-domain.com --domain your-domain.com


```





---





## ⚡ Варіант 2: "One-Liner" (для профі)





Якщо ви хочете виконати все одним рядком (зручно для масового розгортання або скриптів cloud-init):





```bash


apt update && apt install -y git && \


git clone https://github.com/weby-homelab/voip-installer.git && \


cd voip-installer && \


chmod +x install.sh && \


./install.sh --email admin@your-domain.com --domain your-domain.com


```

---

## ✅ Що перевіряти після встановлення

Після того, як скрипт відпрацює, файли конфігурації можуть знаходитися або всередині папки репозиторію, або в системних шляхах (залежно від логіки скрипту).

1. **Перевірка статусу:**
```bash
docker ps

```


*(Має бути статус `Up (healthy)`)*
2. **Пошук паролів SIP:**
Зазвичай скрипт генерує файл `users.env`. Перевірте його наявність:
```bash
# Варіант А (у поточній папці)
cat users.env

# Варіант Б (у папці /root/voip-server, якщо скрипт створює її)
cat /root/voip-server/users.env

```


3. **Тест безпеки мережі (Safe Mode):**
```bash
docker exec asterisk-voip curl -Is https://google.com | grep HTTP

```



---

## 💡 Порада щодо оновлення

Якщо ви оновите код у репозиторії (наприклад, виправите баги або додасте фічі), на сервері достатньо виконати:

```bash
cd ~/voip-installer
git pull
# Потім перезапустити скрипт, якщо потрібне оновлення конфігурації
```

Коли необхідно оновлення конфігурацій БЕЗ зміни паролів та без повторної генерації сертифікатів (наприклад, змінити TZ):

```bash
./install.sh --domain example.com --cert-path /etc/letsencrypt/live/example.com/ --tz Europe/Berlin --update --yes
```

---

<br>
<p align="center">
  Built in Ukraine under air raid sirens &amp; blackouts ⚡<br>
  &copy; 2026 Weby Homelab
</p>
