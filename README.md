# Репозиторий с ответом на тестовое задание

В этом репозитории содержатся файлы ansible и скрипт для установки и настройки 
PostgreSQL на 2-х серверах (Debian и CentOS) и проверки работоспособности.


## Требования

- Bash
- Ansible
- SSH-доступ к серверам (пользователь root, SSH-ключ)

## Структура проекта

*roles/* - директория с 2-мя ролями для Ansible для установки и настройки PostgreSQL на Debian или CentOS (был принят такой подход, поскольку установка и настройка имеет свои отличия в зависимости от дистрибутива);  
*install_postgres_playbook.yml* - основной плейбук, вызывает нужную роль, а затем делает команду проверки со второго сервера к выбранному;  
*inventory.yml* - инвентори-файл, первоначально пустой (заполняется в ходе выполнения скрипта script.sh (110-117 строки));  
*script.sh* - скрипт, который обрабатывает полученные данные о серверах, выбирает целевой и запускает Ansible плейбук.

## Установка

1. Клонируйте репозиторий:
   ```bash
   git clone https://github.com/kolibri337/Answer.git
   cd Answer
   ```
2. В файл **script.sh** напишите в переменную KEY_PATH (18 строка) расположение приватной части ключа для ssh-соединения.
3. Сделайте файл исполняемым:
   ```bash
   chmod +x script.sh
   ```
4. Запустите скрипт, передав в качестве параметра 2 ip-адреса, разделённых запятой:
   ```bash
   ./script.sh 192.168.10.2,192.168.10.3
   ```
Скрипт сообщит о своих шагах, а Ansible выведет сообщение о завершении своей работы.

