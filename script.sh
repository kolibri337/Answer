#!/bin/bash

# Функция для вывода ошибки и завершения скрипта
error_exit() {
    echo "Ошибка: $1" >&2
    exit 1
}

# Проверим корректность ввода аргументов
if [ $# -ne 1 ]; then
    error_exit "Вы неправильно ввели параметры для запуска. Используйте: ./script.sh <server1_ip,server2_ip>"
fi

# Читаем ip-адреса через разделитель в IFS
IFS=',' read -r -a SERVERS <<< "$1"

# !!! ВНИМАНИЕ, ИЗМЕНИТЕ ЗНАЧЕНИЕ ПЕРЕМЕННОЙ KEY_PATH НА ФАЙЛ С КЛЮЧОМ !!!
KEY_PATH="/path/to/private/key"

# Проверка наличия SSH-ключа
if [ ! -f "$KEY_PATH" ]; then
    error_exit "SSH-ключ не найден по пути: $KEY_PATH"
fi

# Проверка прав на SSH-ключ
if [ ! -r "$KEY_PATH" ]; then
    error_exit "Нет прав на чтение SSH-ключа: $KEY_PATH"
fi

ANSIBLE_PLAYBOOK="install_postgres_playbook.yml"  # Сам файл с плейбуком
INVENTORY_FILE="inventory.yml"  # inventory-файл, в который будем писать целевой сервер

# Функция оценки загруженности серверов
server_load() {
    local server=$1
    local cpu_usage
    local ram_usage

    # Проверка доступности сервера
    if ! ping -c 1 -W 1 "$server" &> /dev/null; then
        error_exit "Сервер $server недоступен."
    fi

    # Получаем загруженность CPU (в процентах)
    cpu_usage=$(ssh -i "$KEY_PATH" root@"$server" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1" 2>/dev/null)
    if [ -z "$cpu_usage" ]; then
        error_exit "Не удалось получить загруженность CPU для сервера $server."
    fi

    # Получаем использование RAM (в процентах)
    ram_usage=$(ssh -i "$KEY_PATH" root@"$server" "free | grep Mem | awk '{print \$3/\$2 * 100.0}' | cut -d'.' -f1" 2>/dev/null)
    if [ -z "$ram_usage" ]; then
        error_exit "Не удалось получить использование RAM для сервера $server."
    fi

    # Возвращаем результат
    echo "${cpu_usage},${ram_usage}"
}

# Функция для расчета средней загруженности (как среднее от CPU и RAM)
calculate_load() {
    local cpu=$1
    local ram=$2
    echo "scale=2; ($cpu + $ram) / 2" | bc
}

# Объявим ассоциативный массив загруженностей
declare -A LOADS

# В цикле заполняем средние значения загруженностей для каждого сервера и выводим информацию в терминал
for server in "${SERVERS[@]}"; do
    if ! load=$(server_load "$server"); then
        continue  # Пропускаем сервер, если не удалось получить данные
    fi
    cpu=${load%,*}
    ram=${load#*,}
    load_score=$(calculate_load "$cpu" "$ram")
    LOADS["$server"]=$load_score
    echo "Сервер: $server, CPU=${cpu}%, RAM=${ram}%, Средняя загруженность: ${load_score}%"
done

# Проверка, что хотя бы один сервер доступен
if [ ${#LOADS[@]} -eq 0 ]; then
    error_exit "Нет доступных серверов для установки."
fi

# Выбор наименее загруженного сервера
min_load=999999
TARGET_SERVER=""
for server in "${!LOADS[@]}"; do
    if (( $(echo "${LOADS[$server]} < $min_load" | bc -l) )); then
        min_load=${LOADS[$server]}
        TARGET_SERVER=$server
    fi
done

# Вывод информации о сервере для дальнейшей работы
echo "Наименее загруженным сервером является ${TARGET_SERVER}, выполним установку и настройку PostgreSQL на нём"

# Определяем IP второго сервера
SECOND_SERVER_IP=""
for server in "${SERVERS[@]}"; do
    if [ "$server" != "$TARGET_SERVER" ]; then
        SECOND_SERVER_IP="$server"
        break
    fi
done

# Создаем файл inventory с выбранным сервером и ключом
cat <<EOF > "$INVENTORY_FILE"
all:
  hosts:
    "$TARGET_SERVER":
      ansible_connection: ssh
      ansible_user: root
      ansible_ssh_private_key_file: "$KEY_PATH"
EOF

# Сообщение о создании inventory файла
echo "Внимание! Создан inventory файл для ansible ${INVENTORY_FILE}"

# Проверка наличия Ansible
if ! command -v ansible-playbook &> /dev/null; then
    error_exit "Ansible не установлен. Установите Ansible и повторите попытку."
fi

# Запуск Ansible-плейбука с использованием inventory.yml
ansible-playbook -i "$INVENTORY_FILE" "$ANSIBLE_PLAYBOOK" -e "postgresql_version=14" -e "second_server_ip=$SECOND_SERVER_IP"
