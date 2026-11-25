#!/bin/bash


REPORT_FILE="${1:-PASSPORT/inventory.txt}"

check_privileges() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if ! sudo -v &>/dev/null; then
        echo "Для запуска скрипта необходимы права root или sudo."
        exit 1
    fi
}

check_tool() {
    if [ -z "$(which lastlog2)" ]; then
        echo "Установите пакет lastlog2"
        exit 1
    fi
}

add_section() {
    echo "$1" >> "$REPORT_FILE"
    cat "$2" >> "$REPORT_FILE"
}

log_run() {
    echo "Скрипт был запущен: $(date). Версия файла репорта - v3." >> PASSPORT/log/report.log
}

usage() {
    echo 'Скрипт собирает отчёт о системе по этапам: сбор сырых данных, обработка, логирование.'
    echo 'В параметрах введите имя файла, куда должен сохраниться отчёт.'
}

cleanup() {
    find PASSPORT -name '*.tmp' -delete
}


if [[ "$1" == "-h" ]]; then
    usage
    exit 0
fi


check_privileges
check_tool


mkdir -p PASSPORT/log PASSPORT/tmp


# =========================
# СБОР СЫРЫХ ДАННЫХ
# =========================

date > PASSPORT/tmp/info.tmp
hostname > PASSPORT/tmp/host.tmp
who > PASSPORT/tmp/users.tmp
whoami > PASSPORT/tmp/user.tmp
pwd > PASSPORT/tmp/catalog.tmp
ls > PASSPORT/tmp/files.tmp
uname -svm > PASSPORT/tmp/yadro.tmp
cat /etc/os-release > PASSPORT/tmp/os.tmp
lscpu -e=MODELNAME > PASSPORT/tmp/cpu.tmp
lscpu -e=MHZ >> PASSPORT/tmp/cpu.tmp
nproc > PASSPORT/tmp/logicalnum.tmp
lscpu -C > PASSPORT/tmp/cache.tmp
free -h > PASSPORT/tmp/memory.tmp

sudo dmidecode -t baseboard | grep -E 'Manufacturer:|Product Name:|Version:' > PASSPORT/tmp/motherplate.tmp
sudo dmidecode -t bios | grep -E 'Version:|Release Date:' > PASSPORT/tmp/bios.tmp

lspci > PASSPORT/tmp/pci.tmp


# Пользователи

getent passwd | awk -F: '$3 == 0 || $3 >= 1000 {print $1 ":" $3}' > PASSPORT/tmp/userlist.tmp

> PASSPORT/tmp/inventory_users.tmp

while IFS=: read -r username uid; do

    echo "Имя: $username" >> PASSPORT/tmp/inventory_users.tmp
    echo "UID: $uid" >> PASSPORT/tmp/inventory_users.tmp
    echo "Группы: $(id -nG "$username")" >> PASSPORT/tmp/inventory_users.tmp

    echo "Последняя смена пароля:" >> PASSPORT/tmp/inventory_users.tmp
    sudo chage -l "$username" | grep "Last password change" >> PASSPORT/tmp/inventory_users.tmp

    echo "Последний вход:" >> PASSPORT/tmp/inventory_users.tmp
    sudo lastlog2 -u "$username" >> PASSPORT/tmp/inventory_users.tmp

    echo "" >> PASSPORT/tmp/inventory_users.tmp

done < PASSPORT/tmp/userlist.tmp


# Параметры SSH

sudo sshd -T | grep -E '^(permitrootlogin|port|logingracetime|maxauthtries|passwordauthentication|pubkeyauthentication)' > PASSPORT/tmp/sshd.tmp

grep -RiE '^[[:space:]]*(PermitRootLogin|Port|LoginGraceTime|MaxAuthTries|PasswordAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d >> PASSPORT/tmp/sshd_config.tmp 2>/dev/null


# Топ-5 процессов

ps -eo pid,ppid,user,%mem,args --sort=-%mem | head -n 6 > PASSPORT/tmp/top_processes.tmp


# Подозрительные учётные записи

echo "Пользователи с пустым паролем:" > PASSPORT/tmp/suspicious_users.tmp

sudo awk -F: '$2 == "" {print $1}' /etc/shadow >> PASSPORT/tmp/suspicious_users.tmp

echo "" >> PASSPORT/tmp/suspicious_users.tmp
echo "Пользователи с UID 0, кроме root:" >> PASSPORT/tmp/suspicious_users.tmp

getent passwd | awk -F: '$3 == 0 && $1 != "root" {print $1}' >> PASSPORT/tmp/suspicious_users.tmp


# Файлы с SUID

find /usr/bin /usr/sbin -type f -perm -4000 -print > PASSPORT/tmp/suid_files.tmp


# =========================
# ЗАПИСЬ В ИТОГОВЫЙ ФАЙЛ
# =========================

> "$REPORT_FILE"

add_section '===ИНФОРМАЦИЯ О ДАТЕ===' PASSPORT/tmp/info.tmp
add_section '===ИНФОРМАЦИЯ О ХОСТЕ===' PASSPORT/tmp/host.tmp
add_section '===ИНФОРМАЦИЯ О ПОЛЬЗОВАТЕЛЯХ, ВОШЕДШИХ В СИСТЕМУ===' PASSPORT/tmp/users.tmp
add_section '===ИНФОРМАЦИЯ О ПОЛЬЗОВАТЕЛЕ===' PASSPORT/tmp/user.tmp
add_section '===ИНФОРМАЦИЯ О КАТАЛОГЕ===' PASSPORT/tmp/catalog.tmp
add_section '===ИНФОРМАЦИЯ О ФАЙЛАХ===' PASSPORT/tmp/files.tmp
add_section '===ИНФОРМАЦИЯ О ЯДРЕ===' PASSPORT/tmp/yadro.tmp
add_section '===ИНФОРМАЦИЯ ОБ ОПЕРАЦИОННОЙ СИСТЕМЕ===' PASSPORT/tmp/os.tmp
add_section '===ИНФОРМАЦИЯ О ПРОЦЕССОРЕ===' PASSPORT/tmp/cpu.tmp
add_section '===КОЛИЧЕСТВО ЛОГИЧЕСКИХ ЯДЕР ПРОЦЕССОРА===' PASSPORT/tmp/logicalnum.tmp
add_section '===РАЗМЕРЫ КЭША ПРОЦЕССОРА ВСЕХ УРОВНЕЙ===' PASSPORT/tmp/cache.tmp
add_section '===ОБЪЁМ ФИЗИЧЕСКОЙ ПАМЯТИ===' PASSPORT/tmp/memory.tmp
add_section '===ИНФОРМАЦИЯ О МАТЕРИНСКОЙ ПЛАТЕ===' PASSPORT/tmp/motherplate.tmp
add_section '===ИНФОРМАЦИЯ О BIOS===' PASSPORT/tmp/bios.tmp
add_section '===ИНФОРМАЦИЯ ОБ УСТРОЙСТВАХ, ПОДКЛЮЧЕННЫХ К PCI===' PASSPORT/tmp/pci.tmp

add_section '===ПОЛЬЗОВАТЕЛИ===' PASSPORT/tmp/inventory_users.tmp
add_section '===ПАРАМЕТРЫ SSHD: ЭФФЕКТИВНЫЕ ЗНАЧЕНИЯ===' PASSPORT/tmp/sshd.tmp
add_section '===ЯВНО ПРОПИСАННЫЕ ПАРАМЕТРЫ SSHD===' PASSPORT/tmp/sshd_config.tmp
add_section '===ТОП-5 ПРОЦЕССОВ ПО ПОТРЕБЛЕНИЮ ПАМЯТИ===' PASSPORT/tmp/top_processes.tmp
add_section '===ПОДОЗРИТЕЛЬНЫЕ УЧЁТНЫЕ ЗАПИСИ===' PASSPORT/tmp/suspicious_users.tmp
add_section '===ФАЙЛЫ С SUID===' PASSPORT/tmp/suid_files.tmp


log_run
cleanup
