================================================================
 ИНСТРУКЦИЯ ПО РАЗВЕРТЫВАНИЮ ASTERISK (v4.6.2)
================================================================

Эта инструкция описывает процесс установки безопасной версии сервера VoIP (Asterisk 22 + PJSIP + TLS/SRTP + Fail2Ban + NFTables) на чистый сервер Ubuntu 24.04.

ВЕРСИЯ: v4.6.2 (Safe Docker Mode)
ОСОБЕННОСТИ: 
 - Не сбрасывает сетевые настройки Docker (no flush ruleset).
 - Использует TLS 1.3 на порту 5061.
 - Автоматическая генерация SSL (Let's Encrypt).

---

ШАГ 1. ПОДГОТОВКА СЕРВЕРА
-------------------------
1. Зайдите на сервер по SSH как root:
   ssh root@your-server-ip

2. Убедитесь, что порты 80, 443 и 5061 свободны.
   (Если это чистая система, они свободны).

---

ШАГ 2. СОЗДАНИЕ СКРИПТА
-----------------------
1. Создайте пустой файл для скрипта:
   nano install_voip.sh

2. Скопируйте ПОЛНЫЙ код скрипта v4.6.2 (полученный в чате) в буфер обмена.

3. Вставьте код в терминал:
   - Windows (PuTTY/PowerShell): Нажмите ПРАВУЮ кнопку мыши.
   - Mac/Linux: Нажмите Cmd+V или Ctrl+Shift+V.

4. Сохраните и закройте файл:
   - Нажмите Ctrl+O, затем Enter.
   - Нажмите Ctrl+X.

---

ШАГ 3. ЗАПУСК УСТАНОВКИ
-----------------------
1. Дайте права на выполнение:
   chmod +x install_voip.sh

2. Запустите скрипт (замените данные на свои):

   ./install_voip.sh --domain your-domain.com --email admin@your-domain.com

   ПАРАМЕТРЫ:
   --domain  : Ваше доменное имя (обязательно, должно быть направлено на IP сервера).
   --email   : Почта для регистрации сертификата Let's Encrypt.
   --ext-ip  : (Опционально) Внешний IP, если сервер за NAT. Обычно определяется сам.

---

ШАГ 4. ЧТО ПРОИЗОЙДЕТ
---------------------
Скрипт автоматически выполнит следующие действия:
1. Установит Docker, Fail2Ban, NFTables.
2. Получит SSL сертификат через Certbot.
3. Сгенерирует пароли для пользователей 100-105 (см. файл users.env).
4. Настроит firewall (таблица inet voip_firewall), не ломая Docker.
5. Запустит Asterisk в контейнере.

---

ШАГ 5. ПОСЛЕ УСТАНОВКИ
----------------------
1. Узнайте пароли пользователей SIP:
   cat /root/voip-server/users.env

2. Проверьте статус контейнера:
   docker ps
   (Должен быть статус "Up (healthy)")

3. Проверьте Firewall:
   nft list table inet voip_firewall

3.1. Критическая проверка (Docker Network Safety Check):
   Выполните команды для проверки того, что firewall не заблокировал сеть контейнерам:
   
   systemctl restart nftables
   docker exec asterisk-voip curl -Is https://google.com | grep HTTP
   
   Ожидаемый результат: HTTP/2 200 (или HTTP/1.1 200).
   
   Почему это работает:
   - Host network: контейнер использует host IP/stack.
   - Использованный accept: outbound curl -> SYN -> matched as 'established' on return.
   - No block outbound: политика по умолчанию accept (Safe Mode).
   
   Если тест проходит — Safe Mode полностью защищает сетевую связность Docker.

4. Подключение телефона (например, Linphone):
   - Username: 100 (или 101-105)
   - Password: (из users.env)
   - Domain: your-domain.com:5061
   - Transport: TLS
   - Media Encryption: SRTP
   - AVPF: Disabled (обычно) / ICE: Enabled

---

УСТРАНЕНИЕ НЕПОЛАДОК
--------------------
- Если нет звука: проверьте диапазон UDP 10000-19999 в панели хостинга (Hetzner Firewall / AWS SG).
- Если ошибка SSL: убедитесь, что домен пингуется с сервера.
- Логи Asterisk: docker logs -f asterisk-voip
