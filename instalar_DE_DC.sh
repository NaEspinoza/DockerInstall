#!/bin/bash

set -euo pipefail

# ==================================================
# INSTALACIÓN OFICIAL DE DOCKER ENGINE + COMPOSE V2
# Ubuntu
# ==================================================

echo "=========================================="
echo " Instalación de Docker Engine y Compose"
echo "=========================================="

# 1. Verificar que el sistema sea Ubuntu
if [ ! -f /etc/os-release ]; then
    echo "ERROR: No se pudo identificar el sistema operativo."
    exit 1
fi

source /etc/os-release

if [ "${ID}" != "ubuntu" ]; then
    echo "ERROR: Este script está diseñado para Ubuntu."
    exit 1
fi

UBUNTU_CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

echo "Ubuntu detectado: $PRETTY_NAME"
echo "Codename: $UBUNTU_CODENAME"
echo "Arquitectura: $(dpkg --print-architecture)"

# 2. Eliminar paquetes conflictivos instalados
echo "[1/6] Eliminando paquetes conflictivos..."

conflicting_packages=(
    docker.io
    docker-doc
    docker-compose
    docker-compose-v2
    docker-buildx
    podman-docker
    containerd
    runc
)

installed_packages=()

for package in "${conflicting_packages[@]}"; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null \
        | grep -q "install ok installed"; then
        installed_packages+=("$package")
    fi
done

if [ "${#installed_packages[@]}" -gt 0 ]; then
    sudo apt-get remove -y "${installed_packages[@]}"
else
    echo "No se encontraron paquetes conflictivos."
fi

# 3. Instalar dependencias
echo "[2/6] Instalando dependencias..."

sudo apt-get update

sudo apt-get install -y \
    ca-certificates \
    curl

# 4. Configurar clave GPG oficial
echo "[3/6] Configurando clave GPG..."

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL \
    https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

# 5. Configurar repositorio oficial
echo "[4/6] Configurando repositorio oficial..."

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

# 6. Instalar Docker Engine y plugins oficiales
echo "[5/6] Instalando Docker Engine y Compose V2..."

sudo apt-get update

sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# 7. Verificar servicio
echo "[6/6] Verificando instalación..."

sudo systemctl enable --now docker

echo ""
echo "=========================================="
echo " VERSIONES INSTALADAS"
echo "=========================================="

docker --version

docker compose version

docker buildx version

echo ""
echo "=========================================="
echo " ESTADO DEL SERVICIO"
echo "=========================================="

sudo systemctl is-active docker

echo ""
echo "=========================================="
echo " PRUEBA DE FUNCIONAMIENTO"
echo "=========================================="

sudo docker run --rm hello-world

echo ""
echo "=========================================="
echo " INSTALACIÓN COMPLETADA"
echo "=========================================="
