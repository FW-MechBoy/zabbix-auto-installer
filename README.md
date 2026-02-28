<div align="center">

# ⚡ FW | Zabbix Auto-Installer ⚡

**Instalador universal y automatizado para Zabbix (Server / Proxy / Agent / Docker).**  
Deploy consistente, rápido y repetible para SysAdmins/DevOps.

<br/>

<!-- Badges (ajustá si querés) -->
![Bash](https://img.shields.io/badge/Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-Compatible-success)
![Zabbix](https://img.shields.io/badge/Zabbix-Automation-red)

[![Stars](https://img.shields.io/github/stars/micklo5188/zabbix-auto-installer?style=flat)](https://github.com/micklo5188/zabbix-auto-installer/stargazers)
[![Issues](https://img.shields.io/github/issues/micklo5188/zabbix-auto-installer?style=flat)](https://github.com/micklo5188/zabbix-auto-installer/issues)
[![Last Commit](https://img.shields.io/github/last-commit/micklo5188/zabbix-auto-installer?style=flat)](https://github.com/micklo5188/zabbix-auto-installer/commits/main)

</div>

---

## ✅ Qué hace
Este proyecto automatiza el despliegue de Zabbix con un asistente interactivo.  
Se encarga de la lógica “fea” (repos, versiones, dependencias, DB/Web, hardening, puertos, docker compose) para que vos solo elijas el modo y listo.

---

## 🧭 Tabla de contenido
- [Características](#-características)
- [Sistemas soportados](#-sistemas-soportados)
- [Requisitos](#-requisitos)
- [Instalación rápida](#-instalación-rápida)
- [Modos de despliegue](#-modos-de-despliegue)
- [Puertos](#-puertos)
- [Logs](#-logs)
- [Limpieza total / Uninstall](#-limpieza-total--uninstall)
- [Troubleshooting](#-troubleshooting)
- [Seguridad](#-seguridad)
- [Contribuir](#-contribuir)

---

## 🚀 Características
- **Multi-OS real:** instala en varias distros con detección automática.
- **Smart Scraper:** detecta versiones disponibles y compatibles según repos oficiales.
- **Deploy guiado:** Server / Proxy / Agent / Docker Stack.
- **Seguridad integrada:** UFW/Firewalld + ajustes SELinux cuando aplica.
- **Docker Multi-instancia:** stack por instancia con directorios separados y puertos dinámicos.
- **Logs completos:** genera logs para soporte y debugging.

---

## 🖥️ Sistemas soportados
Según modo (nativo o docker), soporta:

- Debian / Ubuntu
- Oracle Linux / RHEL / Alma / Rocky / CentOS
- Amazon Linux
- openSUSE / SLES
- Arch (principalmente en modo nativo/rolling)

> Si querés sumar una distro más, abrí un issue con `cat /etc/os-release`.

---

## 🧩 Requisitos
- Ejecutar como **root** (`sudo`)
- Acceso a internet (repos / docker registry)
- Herramientas base: `bash`, `curl`, `wget`, `grep`, `awk`, `sed`

> En modo Docker: Docker instalado (el script puede instalarlo automáticamente).

---

## 🛠️ Instalación rápida



git clone https://github.com/micklo5188/zabbix-auto-installer.git
cd zabbix-auto-installer

chmod +x zabbix_install.sh
sudo ./zabbix_install.sh

en caso de necesitar una limpieza total:

cd zabbix-auto-installer/
 
sudo chmod +x zbx_clean.sh

sudo ./zbx_clean-sh
