<p align="center">
  <a href="README_ENG.md">
    <img src="https://img.shields.io/badge/🇬🇧_English-00D4FF?style=for-the-badge&logo=readme&logoColor=white" alt="English README">
  </a>
  <a href="README.md">
    <img src="https://img.shields.io/badge/🇺🇦_Українська-FF4D00?style=for-the-badge&logo=readme&logoColor=white" alt="Українська версія">
  </a>
</p>

<br>

# SSH Port Changer для Ubuntu 24.04+

Цей скрипт безпечно змінює порт SSH на сучасних системах Ubuntu, які використовують `systemd socket activation` (де простої зміни `sshd_config` недостатньо).

## Можливості
*   **Безпечний перехід:** Прослуховує Обидва порти (старий 22 та новий) під час налаштування, щоб запобігти втраті доступу.
*   **Верифікація:** Зупиняється та просить вас перевірити з'єднання у новому вікні перед закриттям старого порту.
*   **Systemd Socket:** Коректно переналаштовує конфігурацію `ssh.socket`.
*   **Файрвол:** Автоматично виявляє та оновлює **UFW** або **NFTables** (якщо налаштовано через `/etc/nftables.conf`).
*   **Fail2Ban:** Оновлює порт, що моніториться, у `jail.local`.

## Використання

1.  **Клонуйте або завантажте** скрипт на ваш сервер.
2.  **Зробіть виконуваним:**
    ```bash
    chmod +x change_port.sh
    ```
3.  **Запустіть від імені root:**
    ```bash
    sudo ./change_port.sh [НОВИЙ_ПОРТ]
    ```
    *Приклад:* `sudo ./change_port.sh 54322`

4.  **Дотримуйтесь підказок.** Скрипт попросить вас підтвердити з'єднання перед завершенням.

## Вимоги
*   Ubuntu 24.04 або новіша (використовує `ssh.socket`).
*   Права root.
