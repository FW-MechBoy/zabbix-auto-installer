#!/bin/bash
# ==============================================================================
# ZABBIX UNIVERSAL AUTO-INSTALLER
# Author:Mech Boy
# Version: 1.0.0
# Description: Automated, foolproof Zabbix deployment
# Support: Debian, Ubuntu, Oracle Linux, RHEL, CentOS, Arch Linux
# ==============================================================================

# ====== COLORES Y VARIABLES GLOBALES ======
R=$(tput setaf 1); G=$(tput setaf 2); Y=$(tput setaf 3)
B=$(tput setaf 4); C=$(tput setaf 6); N=$(tput sgr0); BOLD=$(tput bold)
LOG_FILE="/tmp/zbx_install.log"
VALID_FILE="/tmp/zbx_valid.txt"
START_TIME=$(date +%s)

# ====== MANEJO DE INTERRUPCIONES (CTRL+C) ======
trap 'cleanup_on_exit' SIGINT

cleanup_on_exit() {
    tput cnorm # Restaura el cursor siempre
    rm -f "$LOG_FILE" "$VALID_FILE" /tmp/zbx_*.tmp
    echo -e "\n\n${R}█▓▒░ Instalación cancelada por el usuario (SIGINT). Limpiando temporales...${N}\n"
    exit 1
}

# ====== INTERFAZ GRÁFICA ======
print_ascii_logo() {
    clear
    echo -e "${C}${BOLD}"
    echo '  ███████╗ █████╗ ██████╗ ██████╗ ██╗██╗  ██╗'
    echo '  ╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██║╚██╗██╔╝'
    echo '    ███╔╝ ███████║██████╔╝██████╔╝██║ ╚███╔╝ '
    echo '   ███╔╝  ██╔══██║██╔══██╗██╔══██╗██║ ██╔██╗ '
    echo '  ███████╗██║  ██║██████╔╝██████╔╝██║██╔╝ ██╗'
    echo '  ╚══════╝╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚═╝╚═╝  ╚═╝'
    echo -e "${N}"
    echo -e "${B}================================================================================${N}"
    echo -e "${BOLD}  UNIVERSAL AUTO-INSTALLER v1.0.0 | by FW-Mech Boy${N}"
    echo -e "${B}================================================================================${N}\n"
}

msg() { echo -e "${1}$2${N}"; }
fail() { tput cnorm; echo ""; msg "$R" "█▓▒░ ERROR CRÍTICO: $1"; exit 1; }

> "$LOG_FILE"
> "$VALID_FILE"

# ====== MOTOR GRÁFICO: BARRAS ALINEADAS CON RELLENO VERDE ======
task_progress_bar() {
    local title="$1"
    local func="$2"
    local pid

    local padded_title=$(printf "%-39s" "$title")
    local bar_len=40
    local bar_char="█"
    local empty_char="░"

    $func >> "$LOG_FILE" 2>&1 &
    pid=$!

    tput civis
    local pct=0
    local delay=0.2

    while kill -0 $pid 2>/dev/null; do
        if [ $pct -lt 99 ]; then pct=$((pct + 1)); fi
        local filled_len=$(( (pct * bar_len) / 100 ))
        local empty_len=$(( bar_len - filled_len ))

        local filled=""
        local empty=""
        [[ $filled_len -gt 0 ]] && filled=$(printf "%${filled_len}s" | tr ' ' "$bar_char")
        [[ $empty_len -gt 0 ]] && empty=$(printf "%${empty_len}s" | tr ' ' "$empty_char")

        printf "\r ${C}[BUSY]${N} %s ${B}[${G}%s${C}%s${B}]${N} %3d%% " "$padded_title" "$filled" "$empty" "$pct"
        sleep $delay
    done

    wait $pid
    local status=$?
    printf "\r\033[K"

    local full_bar=$(printf "%${bar_len}s" | tr ' ' "$bar_char")
    if [ $status -eq 0 ]; then
        printf " ${G}[ OK ]${N} %s ${B}[${G}%s${B}]${N} 100%%\n" "$padded_title" "$full_bar"
    else
        printf " ${R}[FAIL]${N} %s ${B}[${R}%s${B}]${N} ERR%%\n\n" "$padded_title" "$full_bar"
        msg "${Y}⚠️  EL PROCESO FALLÓ. ÚLTIMAS LÍNEAS DEL LOG:${N}"
        echo "--------------------------------------------------------------------------------"
        tail -n 12 "$LOG_FILE"
        echo "--------------------------------------------------------------------------------"
        fail "Revise el error en el log o pruebe con una versión de Zabbix distinta."
    fi
    tput cnorm
}

# ====== 1. PRE-REQUISITOS Y DETECCIÓN DE SISTEMA ======
check_prereqs() {
    for cmd in curl wget grep awk tput; do
        command -v $cmd >/dev/null 2>&1 || fail "El sistema no tiene '$cmd' instalado. Instálelo primero."
    done
}

source /etc/os-release
OS_NAME="$PRETTY_NAME"
VER_ID="$VERSION_ID"
VER_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)

detect_pkg() {
    if command -v apt >/dev/null; then
        PKG="apt"
        [[ "$ID" == "ubuntu" ]] && REPO_OS="ubuntu" || REPO_OS="debian"
    elif command -v dnf >/dev/null; then PKG="dnf"
    elif command -v yum >/dev/null; then PKG="yum"
    elif command -v pacman >/dev/null; then PKG="pacman"
    else fail "Gestor de paquetes no soportado."; fi
}

# ====== 2. MENÚ VERTICAL E INTERACCIÓN ======
select_options() {
    print_ascii_logo
    msg "${C}🖥️  SISTEMA DETECTADO: ${N}$OS_NAME"
    echo ""

    if [ "$PKG" == "pacman" ]; then
        Z_VER="Rolling (Arch Repos)"
        msg "$Y" "➜ Arch Linux detectado. Utilizando repositorios nativos rolling-release."
        echo ""
    else
        msg "$C" "➜ Scrapeando repositorios oficiales de Zabbix..."
        (
        mapfile -t RAW_VERSIONS < <(curl -s https://repo.zabbix.com/zabbix/ | grep -Eo 'href="[0-9]+\.[0-9]+/' | cut -d'"' -f2 | tr -d '/' | sort -Vr | head -n 5)
        VERSIONS_FOUND=()

        for v in "${RAW_VERSIONS[@]}"; do
            if [ "$PKG" == "apt" ]; then
                DIR_URL="https://repo.zabbix.com/zabbix/${v}/release/${REPO_OS}/pool/main/z/zabbix-release/"
                LATEST_DEB=$(curl -s "$DIR_URL" | grep -Eo "zabbix-release_${v}-1\+${REPO_OS}[0-9.]+_all\.deb" | sort -V | tail -n 1)
                if [ -n "$LATEST_DEB" ]; then
                    echo "$v|$LATEST_DEB" >> "$VALID_FILE"
                    VERSIONS_FOUND+=("$v")
                fi
            else
                DIR_URL="https://repo.zabbix.com/zabbix/${v}/rhel/${VER_MAJOR}/x86_64/"
                LATEST_RPM=$(curl -s "$DIR_URL" | grep -Eo "zabbix-release-${v}-1\.el${VER_MAJOR}\.noarch\.rpm" | head -n 1)
                if [ -n "$LATEST_RPM" ]; then
                    echo "$v|$LATEST_RPM" >> "$VALID_FILE"
                    VERSIONS_FOUND+=("$v")
                fi
            fi
        done
        declare -p VERSIONS_FOUND > /tmp/zbx_versions.tmp
        ) & spinner_pid=$!

        while kill -0 $spinner_pid 2>/dev/null; do printf "${C}●${N} "; sleep 0.2; printf "\b\b"; done
        wait $spinner_pid
        source /tmp/zbx_versions.tmp && rm /tmp/zbx_versions.tmp
        VERSIONS=("${VERSIONS_FOUND[@]}")

        [[ ${#VERSIONS[@]} -eq 0 ]] && fail "No se encontraron paquetes para esta distro."
        printf "\r\033[K"

        msg "${BOLD}Versiones disponibles compatibles:${N}"
        for i in "${!VERSIONS[@]}"; do echo -e "  ${C}[$((i+1))]${N} Zabbix ${VERSIONS[$i]}"; done
        echo ""
        read -p "  👉 Selecciona Versión: " OPC_V
        Z_VER="${VERSIONS[$((OPC_V-1))]}"
        [[ -z "$Z_VER" ]] && fail "Opción incorrecta."
        echo ""
    fi

    msg "${BOLD}Configuración de Base de Datos:${N}"
    echo -e "  ${C}[1]${N} MySQL / MariaDB"
    echo -e "  ${C}[2]${N} PostgreSQL"
    read -p "  👉 Selecciona Motor DB: " OPC_D
    DB_TYPE="mysql"; [[ "$OPC_D" == "2" ]] && DB_TYPE="pgsql"
    echo ""

    msg "${BOLD}Configuración de Servidor Web:${N}"
    echo -e "  ${C}[1]${N} Apache"
    echo -e "  ${C}[2]${N} Nginx"
    read -p "  👉 Selecciona Servidor Web: " OPC_W
    WEB_TYPE="apache"; [[ "$OPC_W" == "2" ]] && WEB_TYPE="nginx"
    echo ""

    msg "${BOLD}Seguridad de Base de Datos:${N}"
    while true; do
        read -s -p "  🔑 Crea contraseña para 'zabbix': " Z_PASS1; echo
        read -s -p "  🔑 Confirma la contraseña: " Z_PASS2; echo
        if [ "$Z_PASS1" == "$Z_PASS2" ] && [ ! -z "$Z_PASS1" ]; then
            Z_PASS="$Z_PASS1"; break
        else msg "$R" "  ❌ Las contraseñas no coinciden. Reintente."; fi
    done
    echo ""
}

# ====== TAREAS (BACKEND) ======
task_repos() {
    if [ "$PKG" == "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt update -y && apt install -y wget curl gnupg
        rm -f /etc/apt/sources.list.d/zabbix*
        EXACT_FILE=$(grep "^${Z_VER}|" "$VALID_FILE" | cut -d'|' -f2)
        URL="https://repo.zabbix.com/zabbix/${Z_VER}/release/${REPO_OS}/pool/main/z/zabbix-release/${EXACT_FILE}"
        wget -q "$URL" -O zbx.deb
        dpkg -i -E --force-confnew zbx.deb
        apt update -y
    elif [ "$PKG" == "dnf" ] || [ "$PKG" == "yum" ]; then
        rpm --import https://repo.zabbix.com/zabbix/RPM-GPG-KEY-ZABBIX-08EFA7DD
        EXACT_FILE=$(grep "^${Z_VER}|" "$VALID_FILE" | cut -d'|' -f2)
        URL_RPM="https://repo.zabbix.com/zabbix/${Z_VER}/rhel/${VER_MAJOR}/x86_64/${EXACT_FILE}"
        $PKG install -y "$URL_RPM"
        $PKG clean all
    fi
}

task_packages() {
    if [ "$PKG" == "apt" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt install -y zabbix-server-$DB_TYPE zabbix-frontend-php zabbix-$WEB_TYPE-conf zabbix-sql-scripts zabbix-agent mariadb-server
    elif [ "$PKG" == "pacman" ]; then
        pacman -Sy --noconfirm zabbix-server zabbix-frontend-php zabbix-agent mariadb apache php-apache
    else
        $PKG install -y zabbix-server-$DB_TYPE zabbix-web-$DB_TYPE zabbix-$WEB_TYPE-conf zabbix-sql-scripts zabbix-agent mariadb-server
    fi
}

task_database() {
    if [ "$PKG" == "pacman" ]; then
        mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    fi
    systemctl enable --now mariadb
    sleep 3
    mysql -e "DROP DATABASE IF EXISTS zabbix; CREATE DATABASE zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;"
    mysql -e "DROP USER IF EXISTS 'zabbix'@'localhost'; CREATE USER 'zabbix'@'localhost' IDENTIFIED BY '$Z_PASS';"
    mysql -e "GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost'; FLUSH PRIVILEGES;"
    mysql -e "SET GLOBAL log_bin_trust_function_creators = 1;"

    SQL_PATH=$(find /usr/share -name "server.sql.gz" -o -name "mysql.sql" | grep "$DB_TYPE" | head -n 1)
    if [[ "$SQL_PATH" == *.gz ]]; then
        zcat "$SQL_PATH" | mysql -uzabbix -p"$Z_PASS" zabbix
    else
        cat "$SQL_PATH" | mysql -uzabbix -p"$Z_PASS" zabbix
    fi
    mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;"
}

task_security() {
    if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service={http,https}
        firewall-cmd --permanent --add-port=10051/tcp
        firewall-cmd --reload
    elif command -v ufw >/dev/null && systemctl is-active --quiet ufw; then
        ufw allow 80/tcp
        ufw allow 10051/tcp
    fi

    if command -v setsebool >/dev/null; then
        setsebool -P httpd_can_network_connect 1
    fi
}

task_services() {
    CONF_PATH=$(find /etc -name "zabbix_server.conf" | head -n 1)
    sed -i "s/# DBPassword=/DBPassword=$Z_PASS/g" "$CONF_PATH"

    rm -f /etc/zabbix/web/zabbix.conf.php /usr/share/zabbix/conf/zabbix.conf.php

    WEB_SRV="apache2"; [[ "$WEB_TYPE" == "nginx" ]] && WEB_SRV="nginx"
    [[ "$PKG" != "apt" && "$WEB_TYPE" == "apache" ]] && WEB_SRV="httpd"

    systemctl restart zabbix-server zabbix-agent $WEB_SRV
    systemctl enable zabbix-server zabbix-agent $WEB_SRV
}

# ====== EJECUCIÓN PRINCIPAL ======
[[ $EUID -ne 0 ]] && fail "Este script requiere privilegios de root (sudo)."
check_prereqs
detect_pkg
select_options

echo -e "${B}================================================================================${N}"
echo -e "${BOLD}${C}   INICIANDO DESPLIEGUE EN SEGUNDO PLANO${N}"
echo -e "${B}================================================================================${N}\n"

task_progress_bar "Sincronizando repositorios y llaves GPG" task_repos
task_progress_bar "Descargando e instalando dependencias" task_packages
task_progress_bar "Inicializando motor de Base de Datos" task_database
task_progress_bar "Aplicando politicas de seguridad" task_security
task_progress_bar "Registrando e iniciando servicios Web" task_services

rm -f "$VALID_FILE" /tmp/zbx_*.tmp

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINS=$((DURATION / 60))
SECS=$((DURATION % 60))

IP_ADDR=$(hostname -I | awk '{print $1}')
echo ""
echo "${B}================================================================================${N}"
echo "${G}  🚀 ¡ZABBIX $Z_VER INSTALADO Y DESPLEGADO CON ÉXITO!${N}"
echo "${B}================================================================================${N}"
echo "  ⏱️  Tiempo total:  ${C}${MINS}m ${SECS}s${N}"
echo "  🌐 URL Acceso:   ${C}http://$IP_ADDR/zabbix${N}"
echo "  👤 Usuario Web:  ${Y}Admin${N} (Con 'A' mayúscula)"
echo "  🔑 Clave Web:    ${Y}zabbix${N}"
echo "${B}================================================================================${N}"
