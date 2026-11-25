# DockerInstall

Scripts para instalar y actualizar **Docker Engine**, **Docker Buildx** y **Docker Compose V2** en **Ubuntu** (y derivados compatibles basados en Ubuntu) siguiendo la documentación oficial de Docker.

## Scripts incluidos

- [`instalar_DE_DC.sh`](./instalar_DE_DC.sh): Instalación limpia desde el repositorio oficial de Docker (formato Deb822).
  - Elimina paquetes conflictivos (`docker.io`, `podman-docker`, `docker-compose`, etc.).
  - Configura la clave GPG oficial y el repositorio `docker.sources`.
  - Instala `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` y `docker-compose-plugin`.
  - Opciones:
    - `--skip-test`: Omite la prueba con el contenedor `hello-world`.
    - `--add-user`: Agrega el usuario actual al grupo `docker`.
    - `-h, --help`: Muestra la ayuda.

- [`actualizar_DE_DC.sh`](./actualizar_DE_DC.sh): Migración y actualización segura de instalaciones existentes de `docker-ce`.
  - Migra repositorios legados (`docker.list`) al formato Deb822 (`docker.sources`).
  - Actualiza la clave GPG oficial y todos los componentes de Docker sin eliminar imágenes, contenedores ni volúmenes.
  - Instala `docker-buildx-plugin` y `docker-compose-plugin` si faltaban en instalaciones previas.

## Uso

```bash
chmod +x instalar_DE_DC.sh actualizar_DE_DC.sh

# Instalación inicial
./instalar_DE_DC.sh

# Actualización / migración de repositorio
./actualizar_DE_DC.sh
```
