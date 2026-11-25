#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# MIGRACIÓN Y ACTUALIZACIÓN DE DOCKER ENGINE + DOCKER COMPOSE V2
# Sistema soportado: Ubuntu (y derivados basados en Ubuntu con UBUNTU_CODENAME)
# Documentación: https://docs.docker.com/engine/install/ubuntu/
# ==============================================================================

readonly DOCKER_GPG_URL="https://download.docker.com/linux/ubuntu/gpg"
readonly DOCKER_REPO_URL="https://download.docker.com/linux/ubuntu"
readonly DOCKER_KEYRING="/etc/apt/keyrings/docker.asc"
readonly DOCKER_SOURCES="/etc/apt/sources.list.d/docker.sources"
readonly LEGACY_DOCKER_LIST="/etc/apt/sources.list.d/docker.list"

readonly -a DOCKER_PACKAGES=(
    docker-ce
    docker-ce-cli
    containerd.io
    docker-buildx-plugin
    docker-compose-plugin
)

TMP_KEY_FILE=""

# --- Colores y utilidades de salida -------------------------------------------
if [ -t 1 ]; then
    readonly C_RESET='\033[0m'
    readonly C_INFO='\033[0;34m'
    readonly C_OK='\033[0;32m'
    readonly C_WARN='\033[0;33m'
    readonly C_ERR='\033[0;31m'
else
    readonly C_RESET=''
    readonly C_INFO=''
    readonly C_OK=''
    readonly C_WARN=''
    readonly C_ERR=''
fi

log_info()  { printf "${C_INFO}[INFO]${C_RESET} %s\n" "$*"; }
log_ok()    { printf "${C_OK}[OK]${C_RESET} %s\n" "$*"; }
log_warn()  { printf "${C_WARN}[AVISO]${C_RESET} %s\n" "$*" >&2; }
log_error() { printf "${C_ERR}[ERROR]${C_RESET} %s\n" "$*" >&2; }

die() {
    log_error "$*"
    exit 1
}

cleanup() {
    if [ -n "${TMP_KEY_FILE:-}" ] && [ -f "$TMP_KEY_FILE" ]; then
        rm -f "$TMP_KEY_FILE"
    fi
}

on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "Fallo inesperado en la línea ${line_no} (código de salida: ${exit_code})."
    exit "$exit_code"
}

trap cleanup EXIT
trap 'on_error $LINENO' ERR

usage() {
    cat <<EOF
Uso: $(basename "$0") [OPCIONES]

Migra el repositorio legado (.list) al formato Deb822 (.sources) si existe,
actualiza la clave GPG oficial y actualiza Docker Engine, Buildx y Compose V2
sin eliminar imágenes, contenedores ni volúmenes existentes.

Opciones:
  -h, --help     Muestra esta ayuda y finaliza.
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Opción desconocida: '$1'. Usa --help para ver las opciones disponibles."
                ;;
        esac
        shift
    done
}

# Ejecuta comandos como root (directamente o vía sudo)
run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

run_apt() {
    run_root env DEBIAN_FRONTEND=noninteractive \
        apt-get -o DPkg::Lock::Timeout=60 "$@"
}

is_pkg_installed() {
    local pkg="$1"
    dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null | grep -qx "install ok installed"
}

check_privileges() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        die "Se requieren permisos de superusuario, pero 'sudo' no está instalado. Ejecuta como root."
    fi

    log_info "Validando permisos de sudo..."
    if ! sudo -v; then
        die "No se pudieron obtener permisos de sudo."
    fi
}

check_system() {
    if [ "$(uname -s)" != "Linux" ]; then
        die "Este script solo es compatible con Linux."
    fi

    if ! command -v dpkg >/dev/null 2>&1 || ! command -v apt-get >/dev/null 2>&1; then
        die "No se encontraron 'dpkg' o 'apt-get'. Este script requiere un sistema basado en APT/Ubuntu."
    fi

    if [ ! -f /etc/os-release ]; then
        die "No se pudo identificar el sistema operativo (/etc/os-release no existe)."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    local os_id="${ID:-}"
    local os_like="${ID_LIKE:-}"
    local pretty_name="${PRETTY_NAME:-Ubuntu}"

    if [ "$os_id" != "ubuntu" ]; then
        if [[ " $os_like " == *" ubuntu "* ]] && [ -n "${UBUNTU_CODENAME:-}" ]; then
            log_warn "Derivado de Ubuntu detectado ($pretty_name). Se usará codename '$UBUNTU_CODENAME'."
        else
            die "Sistema no soportado ($pretty_name). Este script requiere Ubuntu."
        fi
    fi

    UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    if [ -z "$UBUNTU_CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
        UBUNTU_CODENAME="$(lsb_release -cs 2>/dev/null || true)"
    fi

    if [ -z "$UBUNTU_CODENAME" ]; then
        die "No se pudo determinar el codename de Ubuntu (UBUNTU_CODENAME / VERSION_CODENAME)."
    fi

    ARCH="$(dpkg --print-architecture)"
    case "$ARCH" in
        amd64|arm64|armhf|ppc64el|s390x)
            ;;
        i386)
            die "La arquitectura 'i386' no está soportada por Docker Engine oficial."
            ;;
        *)
            log_warn "Arquitectura '$ARCH' no listada entre las estándar de Docker; se continuará de todos modos."
            ;;
    esac

    log_info "Sistema:      $pretty_name"
    log_info "Codename:     $UBUNTU_CODENAME"
    log_info "Arquitectura: $ARCH"
}

check_existing_docker() {
    log_info "[1/7] Comprobando instalación existente de Docker..."

    if ! is_pkg_installed "docker-ce"; then
        if command -v snap >/dev/null 2>&1 && snap list docker >/dev/null 2>&1; then
            die "Se detectó Docker instalado vía Snap. Este script actualiza paquetes oficiales 'docker-ce'. Usa 'instalar_DE_DC.sh' tras eliminar el snap."
        fi
        if is_pkg_installed "docker.io"; then
            die "Se detectó el paquete no oficial 'docker.io' en lugar de 'docker-ce'. Usa 'instalar_DE_DC.sh' para migrar de forma segura al repositorio oficial."
        fi
        if ! command -v docker >/dev/null 2>&1; then
            die "Docker no está instalado. Utiliza 'instalar_DE_DC.sh' para realizar la instalación inicial."
        fi
        die "Docker está presente pero no mediante el paquete oficial 'docker-ce'. Usa 'instalar_DE_DC.sh' para instalar la versión oficial."
    fi

    docker --version || true
    docker compose version 2>/dev/null || log_warn "Docker Compose V2 aún no está instalado; se instalará durante la actualización."

    if command -v docker-compose >/dev/null 2>&1; then
        log_warn "Se detectó 'docker-compose' (V1 legado). Se recomienda migrar a 'docker compose' (V2)."
    fi

    # Verificar si hay paquetes de Docker retenidos (held) en APT
    local -a held_packages=()
    local pkg
    for pkg in "${DOCKER_PACKAGES[@]}"; do
        if apt-mark showhold "$pkg" 2>/dev/null | grep -qx "$pkg"; then
            held_packages+=("$pkg")
        fi
    done

    if [ "${#held_packages[@]}" -gt 0 ]; then
        die "Los siguientes paquetes están marcados como retenidos (hold) en APT: ${held_packages[*]}. Libéralos con 'sudo apt-mark unhold ${held_packages[*]}' antes de actualizar."
    fi
}

ensure_dependencies() {
    local -a missing=()
    local pkg
    for pkg in ca-certificates curl; do
        if ! is_pkg_installed "$pkg"; then
            missing+=("$pkg")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        log_info "Instalando dependencias faltantes: ${missing[*]}"
        run_apt update
        run_apt install -y "${missing[@]}"
    fi
}

setup_gpg_key() {
    log_info "[2/7] Actualizando clave GPG oficial de Docker..."

    ensure_dependencies
    run_root install -m 0755 -d /etc/apt/keyrings

    TMP_KEY_FILE="$(mktemp)"
    if ! curl -fsSL --connect-timeout 15 --retry 3 --retry-delay 2 \
        "$DOCKER_GPG_URL" -o "$TMP_KEY_FILE"; then
        die "No se pudo descargar la clave GPG oficial desde $DOCKER_GPG_URL."
    fi

    if [ ! -s "$TMP_KEY_FILE" ] || ! grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$TMP_KEY_FILE"; then
        die "El archivo descargado no parece una clave GPG válida."
    fi

    run_root install -m 0644 "$TMP_KEY_FILE" "$DOCKER_KEYRING"
    rm -f "$TMP_KEY_FILE"
    TMP_KEY_FILE=""
    log_ok "Clave GPG actualizada en $DOCKER_KEYRING."
}

warn_duplicate_docker_sources() {
    local -a matches=()
    local file
    while IFS= read -r file; do
        if [ "$file" != "$DOCKER_SOURCES" ] && [ "$file" != "$LEGACY_DOCKER_LIST" ]; then
            matches+=("$file")
        fi
    done < <(grep -rEl '^[[:space:]]*[^#].*download\.docker\.com' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true)

    if [ "${#matches[@]}" -gt 0 ]; then
        log_warn "Se detectaron otras fuentes APT con 'download.docker.com': ${matches[*]}"
        log_warn "Si 'apt-get update' falla por conflicto de 'Signed-By', revisa o elimina esos archivos."
    fi
}

migrate_repository() {
    log_info "[3/7] Configurando repositorio oficial (formato Deb822)..."

    run_root tee "$DOCKER_SOURCES" >/dev/null <<EOF
Types: deb
URIs: ${DOCKER_REPO_URL}
Suites: ${UBUNTU_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: ${DOCKER_KEYRING}
EOF
    run_root chmod 0644 "$DOCKER_SOURCES"

    # Eliminar únicamente la configuración legada .list (no afecta paquetes ni /var/lib/docker)
    if [ -f "$LEGACY_DOCKER_LIST" ]; then
        run_root rm -f "$LEGACY_DOCKER_LIST"
        log_ok "Repositorio legado $LEGACY_DOCKER_LIST migrado a $DOCKER_SOURCES."
    else
        log_ok "Repositorio configurado en $DOCKER_SOURCES."
    fi

    warn_duplicate_docker_sources
}

update_apt_indices() {
    log_info "[4/7] Actualizando índices de paquetes APT..."
    if ! run_apt update; then
        die "Falló 'apt-get update'. Verifica tu conexión o que el codename '$UBUNTU_CODENAME' esté disponible en el repositorio de Docker."
    fi
}

upgrade_docker() {
    log_info "[5/7] Actualizando Docker Engine, Buildx y Compose V2..."
    # Se usa 'install -y' (en lugar de --only-upgrade) para actualizar los existentes
    # e instalar plugins faltantes como docker-buildx-plugin o docker-compose-plugin.
    run_apt install -y "${DOCKER_PACKAGES[@]}"
    log_ok "Componentes de Docker actualizados."
}

verify_service() {
    log_info "[6/7] Verificando servicio Docker..."

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        run_root systemctl enable --now docker
        if ! run_root systemctl is-active --quiet docker; then
            die "El servicio 'docker' no quedó activo tras la actualización."
        fi
        log_ok "Servicio systemd 'docker' habilitado y activo."
    elif [ -x /etc/init.d/docker ] && command -v service >/dev/null 2>&1; then
        run_root service docker restart || run_root service docker start
        log_ok "Servicio 'docker' verificado vía SysVinit."
    else
        log_warn "No se detectó systemd activo; omitiendo verificación de servicio."
    fi
}

show_summary() {
    log_info "[7/7] Verificando componentes instalados..."

    echo ""
    echo "=============================================="
    echo " VERSIONES INSTALADAS"
    echo "=============================================="
    docker --version
    docker compose version
    docker buildx version

    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        echo ""
        echo "=============================================="
        echo " ESTADO DEL SERVICIO"
        echo "=============================================="
        run_root systemctl status docker --no-pager -l | sed -n '1,12p'
    fi

    echo ""
    echo "=============================================="
    echo " PAQUETES INSTALADOS"
    echo "=============================================="
    dpkg-query -W -f='${Package}\t${Version}\n' "${DOCKER_PACKAGES[@]}"

    echo ""
    echo "=============================================="
    echo " MIGRACIÓN Y ACTUALIZACIÓN COMPLETADAS"
    echo "=============================================="
    echo "Docker Engine y Docker Compose V2 actualizados."
    echo "Los datos existentes de Docker (/var/lib/docker) no fueron eliminados."
    echo "=============================================="
}

main() {
    parse_args "$@"

    echo "=============================================="
    echo " MIGRACIÓN Y ACTUALIZACIÓN DE DOCKER"
    echo "=============================================="

    check_system
    check_privileges
    check_existing_docker
    setup_gpg_key
    migrate_repository
    update_apt_indices
    upgrade_docker
    verify_service
    show_summary
}

main "$@"
