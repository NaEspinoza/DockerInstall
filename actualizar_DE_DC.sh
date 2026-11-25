#!/bin/bash

set -Eeuo pipefail

echo "==============================================" echo " MIGRACIÓN Y ACTUALIZACIÓN DE DOCKER" echo "=============================================="

1. Verificar Ubuntu

if [ ! -f /etc/os-release ]; then echo "ERROR: No se pudo identificar el sistema operativo." exit 1 fi

source /etc/os-release

if [ "$ID" != "ubuntu" ]; then echo "ERROR: Este script requiere Ubuntu." exit 1 fi

UBUNTU_CODENAME="{UBUNTU_CODENAME:-VERSION_CODENAME}" ARCH="$(dpkg --print-architecture)"

echo "Sistema: $PRETTY_NAME" echo "Codename: $UBUNTU_CODENAME" echo "Arquitectura: $ARCH"

2. Comprobar instalación previa

echo "" echo "[1/7] Comprobando instalación existente..."

if ! command -v docker >/dev/null 2>&1; then echo "ERROR: Docker no está instalado." echo "Utiliza el script de instalación inicial." exit 1 fi

docker --version || true docker compose version || true

3. Comprobar y configurar clave GPG

echo "" echo "[2/7] Configurando clave GPG oficial..."

sudo install -m 0755 -d /etc/apt/keyrings

sudo curl -fsSL
https://download.docker.com/linux/ubuntu/gpg
-o /etc/apt/keyrings/docker.asc

sudo chmod a+r /etc/apt/keyrings/docker.asc

4. Migrar repositorio antiguo al formato Deb822

echo "" echo "[3/7] Actualizando configuración del repositorio..."

sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF Types: deb URIs: https://download.docker.com/linux/ubuntu Suites: ${UBUNTU_CODENAME} Components: stable Architectures: ${ARCH} Signed-By: /etc/apt/keyrings/docker.asc EOF

Eliminar únicamente el archivo antiguo de configuración.
No elimina paquetes ni datos de Docker.

if [ -f /etc/apt/sources.list.d/docker.list ]; then sudo rm /etc/apt/sources.list.d/docker.list echo "Repositorio docker.list migrado correctamente." fi

5. Actualizar índices APT

echo "" echo "[4/7] Actualizando índices de paquetes..."

sudo apt-get update

6. Actualizar Docker Engine y sus componentes

echo "" echo "[5/7] Actualizando Docker Engine y Compose..."

sudo apt-get install --only-upgrade -y
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin

7. Habilitar e iniciar Docker

echo "" echo "[6/7] Verificando servicio Docker..."

sudo systemctl enable --now docker

sudo systemctl is-active --quiet docker

8. Mostrar versiones y estado

echo "" echo "[7/7] Verificando componentes instalados..."

echo "" echo "==============================================" echo " VERSIONES INSTALADAS" echo "=============================================="

docker --version docker compose version docker buildx version

echo "" echo "==============================================" echo " ESTADO DEL SERVICIO" echo "=============================================="

sudo systemctl status docker --no-pager

echo "" echo "==============================================" echo " PAQUETES INSTALADOS" echo "=============================================="

dpkg-query -W
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin

echo "" echo "==============================================" echo " MIGRACIÓN COMPLETADA" echo "=============================================="

echo "Docker Engine y Docker Compose V2 actualizados." echo "Los datos existentes de Docker no fueron eliminados." echo "=============================================="
