#!/bin/bash

# Проверим корректность ввода аргументов
if [ $# -ne 1]; then
	echo "Вы неправильно ввели параметры для запуска."
	echo "Повторите запуск в виде ./script.sh <server1_ip,server2_ip>"
	exit 1
fi

# Читаем ip-адреса через разделитель в IFS
IFS=',' read -a SERVERS <<< "$1"

# !!! ВНИМАНИЕ, ИЗМЕНИТЕ ЗНАЧЕНИЕ ПЕРЕМЕННОЙ KEY_PATH НА ФАЙЛ С КЛЮЧОМ !!!
KEY_PATH="/path/to/private/key"

ANSIBLE_PLAYBOOK="install_postgres_playbook.yml"  # Сам файл с плейбуком
INVENTORY_FILE="inventory.yml"  # inventory-файл, в который будем писать целевой сервер

# Функция оценки загруженности серверов
server_load() {
    local server=$1
    local cpu_usage
    local ram_usage

    # Получаем загруженность CPU (в процентах)
    cpu_usage=$(ssh -i "$KEY_PATH" root@"$server" "top -bn1 | grep 'Cpu(s)' | awk '{print \$2}' | cut -d'%' -f1")

    # Получаем использование RAM (в процентах)
    ram_usage=$(ssh -i "$KEY_PATH" root@"$server" "free | grep Mem | awk '{print \$3/\$2 * 100.0}' | cut -d'.' -f1")

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
    load=$(server_load "$server")
    cpu=${load%,*}
    ram=${load#*,}
    load_score=$(calculate_load "$cpu" "$ram")
    LOADS["$server"]=$load_score
    echo "Сервер: $server, CPU=${cpu}%, RAM=${ram}%, Средняя загруженность: ${load_score}%"
done

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

# Запуск Ansible-плейбука с использованием inventory.yml
ansible-playbook -i "$INVENTORY_FILE" "$ANSIBLE_PLAYBOOK"
