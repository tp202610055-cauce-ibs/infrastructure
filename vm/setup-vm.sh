#!/usr/bin/env bash
# Prepara Ubuntu 24.04 para Cauce (paquetes, Docker con compose, swap de 2 GB, git); idempotente y sin tocar firewall ni SSH.
# Uso: bash vm/setup-vm.sh [usuario]      (por defecto, azureuser)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

TARGET_USER="${1:-azureuser}"
DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a

echo "1/5 Actualizando paquetes..."
apt-get update -q
apt-get upgrade -y -q
apt-get install -y -q ca-certificates curl git

echo "2/5 Instalando Docker desde su repositorio oficial..."
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
fi
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -q
apt-get install -y -q "${DOCKER_PACKAGES[@]}"
# Congela las versiones: una actualización automática no debe reiniciar Docker en la semana de pruebas.
apt-mark hold "${DOCKER_PACKAGES[@]}" >/dev/null

echo "3/5 Configurando el demonio de Docker (live-restore y rotación de logs)..."
DAEMON_JSON='{
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}'
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ] || [ "$(cat /etc/docker/daemon.json)" != "$DAEMON_JSON" ]; then
  printf '%s\n' "$DAEMON_JSON" > /etc/docker/daemon.json
  systemctl restart docker
fi
systemctl enable docker containerd >/dev/null
usermod -aG docker "$TARGET_USER"

echo "4/5 Creando el swap de 2 GB..."
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
  fi
  swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=10' > /etc/sysctl.d/99-cauce.conf
sysctl -q --system

echo "5/5 Comprobando..."
docker --version
docker compose version
swapon --show

echo
echo "Listo. Cierra la sesión SSH y vuelve a entrar para usar docker sin sudo."
