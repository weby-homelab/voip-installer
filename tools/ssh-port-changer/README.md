<p align="center">
  <a href="README_ENG.md">
    <img src="https://img.shields.io/badge/🇬🇧_English-00D4FF?style=for-the-badge&logo=readme&logoColor=white" alt="English README">
  </a>
  <a href="README.md">
    <img src="https://img.shields.io/badge/🇺🇦_Українська-FF4D00?style=for-the-badge&logo=readme&logoColor=white" alt="Українська версія">
  </a>
</p>

<br>

# 🛡️ SSH Port Changer `v1.1`

> **Safely migrate your SSH port on modern Ubuntu systems without getting locked out.**

[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%2B-E95420?logo=ubuntu&style=flat-square)](https://ubuntu.com/)
[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?logo=gnu-bash&style=flat-square)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

---

**Ubuntu 24.04 LTS** та пізніших версіях зміна порту SSH більше не така проста, як редагування `/etc/ssh/sshd_config`. Canonical перейшов до **Systemd Socket Activation**, що означає, що `ssh.socket` контролює порт прослуховування, ігноруючи ваш конфігураційний файл.

Цей скрипт обробляє складність за вас, забезпечуючи безпечний перехід без **простоїв**.

### ✨ Основні характеристики (v1.1)

* **🕵️ Автоматичне виявлення:** Автоматично визначає ваш *поточний* порт SSH (22 чи щось інше).
* **🛡️ Безпечний перехід:** Налаштовує сервер для одночасного прослуховування **ОБИДВА** старих та нових портів під час налаштування.
* **🔌 Systemd Socket Override:** Правильно створює випадаючі модулі `listen.conf` для обробки прив'язки сокетів.
* **🧱 Автоматичне налаштування брандмауера:** Автоматично виявляє та оновлює **NFTables** або **UFW**.
* **🧹 Очищення:** Після підтвердження **видаляє старий порт** з конфігурації брандмауера та SSH, залишаючи активним лише новий.
* **🚫 Перевірка захисту від блокування:** Призупиняє роботу та змушує вас перевірити підключення в новому вікні перед закриттям старого порту.

---

## ⚡ Швидкий старт

Запустіть це на вашому сервері від імені `root`:

```bash
# Завантажте та зробіть виконуваним файлом
curl -fsSL https://raw.githubusercontent.com/weby-homelab/voip-installer/main/tools/ssh-port-changer/change_port.sh -o change_port.sh
chmod +x change_port.sh

# Запустіть (замініть 54322 на потрібний порт)
sudo ./change_port.sh 54322
```

---

## 📖 Детальне використання

### 1. Інтерактивний режим
Запустіть без аргументів, щоб запитувати порт:
```bash
./change_port.sh
# > Виявлено поточний порт SSH: 22
# > Введіть новий порт SSH (1024-65535):
```

### 2. Неінтерактивний режим
Передайте порт як аргумент для автоматизація:
```bash
./change_port.sh 2222
```

### 3. Крок перевірки (важливий)
Скрипт призупиниться на цьому етапі:

> **КРИТИЧНО: НЕ ЗАКРИВАЙТЕ ЦЕЙ СЕСІЙ!**
> Відкрийте НОВЕ вікно терміналу та перевірте, чи можете ви підключитися:
> `ssh -p 54322 root@<ip-адреса-вашого-сервера>`

**Тільки** після успішного входу через новий порт в окремому вікні введіть `yes` у скрипті, щоб завершити зміни.

---

## 🔧 Як це працює

1. **Перевірка:** Перевіряє права root, версію ОС та виявляє поточний активний порт SSH (наприклад, 22).
2. **Відкриття брандмауера:** Негайно додає правило `ALLOW` для **НОВОГО** порту.
3. **Socket Dual-Bind:** Налаштовує `ssh.socket` для прослуховування `0.0.0.0:OldPort` ТА `0.0.0.0:NewPort`.
4. **Wait for User:** Призупиняє роботу для ручної перевірки.
5. **Фіналізація (після «yes»):**
* Видаляє `OldPort` з `ssh.socket` (SSH тепер прослуховує ТІЛЬКИ NewPort).
* Оновлює `sshd_config` (видаляє старі рядки `Port`, додає нові).
* Оновлює `fail2ban` (замінює старий моніторинг портів).
* **Закриває брандмауер:** Видаляє правило `ALLOW` для `OldPort` з UFW або NFTables.

---

## 📦 Сумісність

| ОС | Версія | Підтримка | Примітка |
| :--- | :--- | :--- | :--- |
| **Ubuntu** | 24.04 LTS (Noble) | ✅ Повністю підтримується | Використовує логіку `ssh.socket` |
| **Ubuntu** | 22.04 LTS | ⚠️ Не тестувалося | Має працювати, якщо ввімкнено активацію сокета |
| **Debian** | 12 (Bookworm) | ❌ Не підтримується | Використовує стандартний `sshd_config` |

---

## 🤝 Внесок

Знайшли помилку? Скористайтеся вкладкою [Проблеми](https://github.com/weby-homelab/voip-installer/issues).
Запити на доробку вітаються!

---

<br>
<p align="center">
  Built in Ukraine under air raid sirens &amp; blackouts ⚡<br>
  &copy; 2026 Weby Homelab
</p>
