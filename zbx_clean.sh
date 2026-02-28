#!/bin/bash
# ==============================================================================
# ZABBIX CLEAN / UNINSTALLER (UNIVERSAL)
# Version: 1.0.0
# Purpose: Remove Zabbix + repo + configs + optional DB/Web/Docker resources
# Supports: Debian/Ubuntu/RaspberryPiOS (APT), RHEL/CentOS/Alma/Rocky/Oracle/Amazon (DNF/YUM),
#           SUSE/OpenSUSE (ZYPPER), Arch (PACMAN)
# ==============================================================================

set -u

# FIX PATH (para entornos donde root no tiene sbin en PATH)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# ====== COLORES ======
R=$(tput setaf 1 2>/dev/null || true); G=$(tput setaf 2 2>/dev/null || true); Y=$(tput setaf 3 2>/dev/null || true)
B=$(tput setaf 4 2>/dev/null || true); C=$(tput setaf 6 2>/dev/null || true); N=$(tput sgr0 2>/dev/null || true); BOLD=$(tput bold 2>/dev/null || true)

LOG_FILE="/tmp/zbx_clean.log"
: > "$LOG_FILE"

msg() { echo -e "${1}${2}${N}"; echo "[INFO] ${2}" >> "$LOG_FILE"; }
warn() { echo -e "${Y}${2}${N}"; echo "[WARN] ${2}" >> "$LOG_FILE"; }
err() { echo -e "${R}${2}${N}"; echo "[ERR ] ${2}" >> "$LOG_FILE"; }
run() { echo "[CMD ] $*" >> "$LOG_FILE"; "$@" >> "$LOG_FILE" 2>&1; return $?; }

cleanup_tmp() { rm -f /tmp/zbx_*.tmp >/dev/null 2>&1 || true; }
trap cleanup_tmp EXIT

# ====== DETECT OS / PKG ======
PKG=""
source /etc/os-release 2>/dev/null || true
OS_NAME="${PRETTY_NAME:-Unknown Linux}"

detect_pkg() {
  if command -v apt-get >/dev/null 2>&1; then PKG="apt"
  elif command -v dnf >/dev/null 2>&1; then PKG="dnf"
  elif command -v yum >/dev/null 2>&1; then PKG="yum"
  elif command -v zypper >/dev/null 2>&1; then PKG="zypper"
  elif command -v pacman >/dev/null 2>&1; then PKG="pacman"
  else PKG="unknown"
  fi
}

have_systemd() {
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl list-unit-files >/dev/null 2>&1 && return 0
  return 1
}

stop_service() {
  local svc="$1"
  if have_systemd; then
    run systemctl stop "$svc" || true
    run systemctl disable "$svc" || true
  fi
  if command -v service >/dev/null 2>&1; then
    run service "$svc" stop || true
  fi
  if [ -x "/etc/init.d/$svc" ]; then
    run "/etc/init.d/$svc" stop || true
  fi
}

# ====== MENÚ / MODOS ======
MODE="${1:-}"

print_header() {
  clear 2>/dev/null || true
  echo -e "${C}${BOLD}"
  echo "================================================"
  echo " ZABBIX CLEAN / UNINSTALLER v1.0.0"
  echo "================================================"
  echo -e "${N}"
  msg "${C}" "Sistema detectado: $OS_NAME"
  msg "${C}" "Package manager: $PKG"
  echo ""
}

sanitize_num() { echo "${1//[^0-9]/}"; }

choose_mode() {
  if [ -n "$MODE" ]; then
    case "$MODE" in
      --zabbix-only) CLEAN_ZABBIX=1; CLEAN_STACK=0; CLEAN_DOCKER=0; CLEAN_IMAGES=0 ;;
      --full-stack)  CLEAN_ZABBIX=1; CLEAN_STACK=1; CLEAN_DOCKER=0; CLEAN_IMAGES=0 ;;
      --docker-only) CLEAN_ZABBIX=0; CLEAN_STACK=0; CLEAN_DOCKER=1; CLEAN_IMAGES=0 ;;
      --nuke)        CLEAN_ZABBIX=1; CLEAN_STACK=1; CLEAN_DOCKER=1; CLEAN_IMAGES=1 ;;
      *) MODE="" ;;
    esac
  fi

  if [ -z "$MODE" ]; then
    echo -e "${BOLD}Elegí qué limpiar:${N}"
    echo -e "  ${C}[1]${N} Solo Zabbix (paquetes + repo + configs)"
    echo -e "  ${C}[2]${N} Full Stack (Zabbix + DB + Web)"
    echo -e "  ${C}[3]${N} Solo Docker Zabbix (contenedores/volúmenes/redes)"
    echo -e "  ${C}[4]${N} NUCLEAR (Zabbix + DB + Web + Docker + borrar imágenes zabbix/*)"
    echo ""
    while true; do
      read -r -p "👉 Opción: " opt
      opt="$(sanitize_num "$opt")"
      [[ "$opt" =~ ^[1-4]$ ]] && break
    done

    CLEAN_ZABBIX=0; CLEAN_STACK=0; CLEAN_DOCKER=0; CLEAN_IMAGES=0
    case "$opt" in
      1) CLEAN_ZABBIX=1 ;;
      2) CLEAN_ZABBIX=1; CLEAN_STACK=1 ;;
      3) CLEAN_DOCKER=1 ;;
      4) CLEAN_ZABBIX=1; CLEAN_STACK=1; CLEAN_DOCKER=1; CLEAN_IMAGES=1 ;;
    esac
  fi

  return 0
}

confirm_or_exit() {
  # Para correr sin preguntar: FORCE=1 ./zbx_clean.sh
  if [ "${FORCE:-0}" = "1" ]; then
    warn "${Y}" "FORCE=1 -> ejecutando sin confirmación."
    return 0
  fi

  echo ""
  warn "${Y}" "ATENCIÓN: Esto va a desinstalar y borrar recursos según el modo elegido."
  echo "Para confirmar, escribí: YES"
  read -r -p "> " ans
  if [ "$ans" != "YES" ]; then
    err "${R}" "Cancelado."
    exit 1
  fi
}

# ====== DOCKER CLEAN ======
docker_running() {
  command -v docker >/dev/null 2>&1 || return 1
  run docker info >/dev/null 2>&1 && return 0
  return 1
}

docker_clean_zabbix() {
  docker_running || { warn "${Y}" "Docker no disponible o no está corriendo. Skip."; return 0; }

  msg "${C}" "🧹 Limpiando Docker (solo recursos Zabbix)..."

  local ids
  ids="$(docker ps -a --format '{{.ID}} {{.Image}} {{.Names}} {{.Ports}}' 2>/dev/null \
        | awk '$2 ~ /^zabbix\// || $3 ~ /zabbix/ {print $1}')"

  if [ -n "$ids" ]; then
    run docker rm -f $ids || true
  else
    warn "${Y}" "No encontré contenedores Zabbix."
  fi

  # Redes y volúmenes con nombre típico
  local nets vols
  nets="$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -Ei '(^zbx|zabbix)' || true)"
  vols="$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -Ei '(zbx|zabbix)' || true)"

  if [ -n "$nets" ]; then
    while read -r n; do [ -n "$n" ] && run docker network rm "$n" || true; done <<< "$nets"
  fi
  if [ -n "$vols" ]; then
    while read -r v; do [ -n "$v" ] && run docker volume rm "$v" || true; done <<< "$vols"
  fi

  # Directorio compose típico
  if [ -d /opt/zabbix-docker ]; then
    run rm -rf /opt/zabbix-docker || true
  fi

  # Imágenes zabbix/*
  if [ "${CLEAN_IMAGES:-0}" = "1" ]; then
    msg "${C}" "🧨 Eliminando imágenes Docker zabbix/* ..."
    local imgs
    imgs="$(docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' 2>/dev/null | awk '$1 ~ /^zabbix\// {print $2}' | sort -u)"
    if [ -n "$imgs" ]; then
      run docker rmi -f $imgs || true
    else
      warn "${Y}" "No encontré imágenes zabbix/*."
    fi
  fi

  return 0
}

# ====== DB CLEAN (drop user/db) ======
mysql_drop_zabbix() {
  command -v mysql >/dev/null 2>&1 || return 0

  # Intento por socket sin password (típico en instalación fresh)
  mysql --protocol=socket -uroot -e "SELECT 1" >/dev/null 2>&1 || { warn "${Y}" "MySQL/MariaDB: no pude conectar como root (skip drop db/user)."; return 0; }

  msg "${C}" "🧹 MySQL/MariaDB: borrando DB/usuario zabbix..."
  run mysql -uroot -e "DROP DATABASE IF EXISTS zabbix;" || true
  run mysql -uroot -e "DROP USER IF EXISTS 'zabbix'@'localhost';" || true
  run mysql -uroot -e "FLUSH PRIVILEGES;" || true
  return 0
}

pgsql_drop_zabbix() {
  command -v psql >/dev/null 2>&1 || return 0

  if command -v runuser >/dev/null 2>&1; then
    msg "${C}" "🧹 PostgreSQL: borrando DB/usuario zabbix..."
    run runuser -u postgres -- psql -tc "SELECT 1" >/dev/null 2>&1 || { warn "${Y}" "PostgreSQL: no pude ejecutar como postgres (skip)."; return 0; }
    run runuser -u postgres -- psql -c "DROP DATABASE IF EXISTS zabbix;" || true
    run runuser -u postgres -- psql -c "DROP ROLE IF EXISTS zabbix;" || true
  else
    msg "${C}" "🧹 PostgreSQL: borrando DB/usuario zabbix..."
    run su - postgres -c "psql -c \"DROP DATABASE IF EXISTS zabbix;\"" || true
    run su - postgres -c "psql -c \"DROP ROLE IF EXISTS zabbix;\"" || true
  fi
  return 0
}

# ====== PACKAGE REMOVE ======
apt_remove() {
  export DEBIAN_FRONTEND=noninteractive
  run apt-get update -y || true
  run apt-get purge -y "$@" || true
}

apt_autoremove() {
  export DEBIAN_FRONTEND=noninteractive
  run apt-get autoremove -y || true
  run apt-get autoclean -y || true
}

dnf_remove() { run dnf remove -y "$@" || true; }
yum_remove() { run yum remove -y "$@" || true; }
zypper_remove() { run zypper --non-interactive rm -u "$@" || true; }
pacman_remove() { run pacman -Rns --noconfirm "$@" || true; }

remove_zabbix_repo_files() {
  msg "${C}" "🧹 Eliminando repositorios/archivos de Zabbix..."
  case "$PKG" in
    apt)
      run rm -f /etc/apt/sources.list.d/zabbix*.list /etc/apt/sources.list.d/zabbix*.sources || true
      run rm -f /etc/apt/preferences.d/99-zabbix || true
      run rm -f /etc/apt/trusted.gpg.d/zabbix* || true
      run apt-get update -y || true
      ;;
    dnf|yum)
      run rm -f /etc/yum.repos.d/zabbix*.repo || true
      ;;
    zypper)
      # zypper: repos list/remove es más variable; borramos archivo si existiese
      run rm -f /etc/zypp/repos.d/zabbix*.repo || true
      ;;
    pacman)
      # Arch: normalmente no hay repo oficial así; no tocamos pacman.conf
      ;;
  esac
  return 0
}

remove_zabbix_packages() {
  msg "${C}" "🧹 Desinstalando paquetes Zabbix..."
  case "$PKG" in
    apt)
      apt_remove 'zabbix-*' 'zabbix-release' || true
      apt_autoremove
      ;;
    dnf)
      dnf_remove 'zabbix*' || true
      ;;
    yum)
      yum_remove 'zabbix*' || true
      ;;
    zypper)
      zypper_remove 'zabbix*' || true
      ;;
    pacman)
      # Arch: nombres pueden variar, intentamos lo común
      pacman_remove zabbix-server zabbix-frontend-php zabbix-agent zabbix-proxy zabbix-sql-scripts 2>/dev/null || true
      ;;
    *)
      warn "${Y}" "No pude detectar package manager. Skip paquetes."
      ;;
  esac
  return 0
}

remove_stack_packages() {
  msg "${C}" "🧹 Desinstalando DB + Web (FULL STACK)..."

  case "$PKG" in
    apt)
      apt_remove apache2 nginx 'php*' 'libapache2-mod-php*' 'php-fpm*' || true
      apt_remove mariadb-server mariadb-client 'mysql*' || true
      apt_remove postgresql\* || true
      apt_autoremove
      ;;
    dnf)
      dnf_remove httpd nginx php\* || true
      dnf_remove mariadb\* mysql\* || true
      dnf_remove postgresql\* || true
      ;;
    yum)
      yum_remove httpd nginx php\* || true
      yum_remove mariadb\* mysql\* || true
      yum_remove postgresql\* || true
      ;;
    zypper)
      zypper_remove apache2 nginx php8\* php\* || true
      zypper_remove mariadb\* mysql\* || true
      zypper_remove postgresql\* || true
      ;;
    pacman)
      pacman_remove apache nginx php php-fpm mariadb postgresql 2>/dev/null || true
      ;;
  esac

  return 0
}

# ====== FILES / USERS CLEAN ======
remove_leftovers() {
  msg "${C}" "🧹 Borrando archivos/residuos de Zabbix..."
  run rm -rf /etc/zabbix /var/log/zabbix /var/lib/zabbix /var/run/zabbix || true
  run rm -rf /usr/share/zabbix /usr/share/zabbix-sql-scripts || true
  run rm -f /etc/sudoers.d/zabbix || true
  run rm -f /etc/apache2/conf-available/zabbix*.conf /etc/apache2/conf-enabled/zabbix*.conf 2>/dev/null || true
  run rm -f /etc/nginx/conf.d/zabbix*.conf /etc/nginx/sites-available/zabbix* /etc/nginx/sites-enabled/zabbix* 2>/dev/null || true
  run rm -f /etc/systemd/system/zabbix*.service 2>/dev/null || true
  run rm -f /etc/systemd/system/multi-user.target.wants/zabbix*.service 2>/dev/null || true
  run rm -f /tmp/zbx_install.log /tmp/zbx_valid.txt 2>/dev/null || true
  return 0
}

remove_zabbix_user() {
  if id zabbix >/dev/null 2>&1; then
    msg "${C}" "🧹 Eliminando usuario/grupo zabbix..."
    run userdel -r zabbix || true
    run groupdel zabbix || true
  fi
  return 0
}

# ====== MAIN ======
[[ $EUID -ne 0 ]] && { err "${R}" "Este script requiere root (sudo)."; exit 1; }

detect_pkg
print_header
choose_mode
confirm_or_exit

msg "${BOLD}${C}" "Iniciando limpieza..."
echo "" | tee -a "$LOG_FILE" >/dev/null

# 1) Stop servicios típicos (no rompe si no existen)
msg "${C}" "⛔ Deteniendo servicios..."
for s in \
  zabbix-server zabbix-agent zabbix-agent2 zabbix-proxy zabbix-web-service zabbix-java-gateway \
  apache2 httpd nginx \
  mariadb mysql postgresql php-fpm php8.4-fpm php8.3-fpm php8.2-fpm
do
  stop_service "$s" || true
done

# 2) Docker (si corresponde)
if [ "${CLEAN_DOCKER:-0}" = "1" ]; then
  docker_clean_zabbix
fi

# 3) DB drops (si FULL STACK o si vas a borrar Zabbix server)
if [ "${CLEAN_STACK:-0}" = "1" ] || [ "${CLEAN_ZABBIX:-0}" = "1" ]; then
  mysql_drop_zabbix
  pgsql_drop_zabbix
fi

# 4) Paquetes + repo
if [ "${CLEAN_ZABBIX:-0}" = "1" ]; then
  remove_zabbix_packages
  remove_zabbix_repo_files
fi

if [ "${CLEAN_STACK:-0}" = "1" ]; then
  remove_stack_packages
fi

# 5) Residuos + usuario
remove_leftovers
remove_zabbix_user

msg "${G}" "✅ CLEAN COMPLETADO."
msg "${C}" "Log: $LOG_FILE"
echo ""
msg "${Y}" "TIP: si querés correr sin preguntas: FORCE=1 ./zbx_clean.sh --nuke"
