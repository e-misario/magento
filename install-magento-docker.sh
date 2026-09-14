#!/bin/bash
set -e

# Valores por defecto
DOMAIN="mag.e-misario.com"
INSTALL_DIR="$HOME/magento"
MAGENTO_VERSION="2.4.8"
MAX_RETRIES=5

# Parsear argumentos
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--domain) DOMAIN="$2"; shift ;;
        -p|--path) INSTALL_DIR="$2"; shift ;;
        -v|--version) MAGENTO_VERSION="$2"; shift ;;
        --public-key) MAGENTO_PUBLIC_KEY="$2"; shift ;;
        --private-key) MAGENTO_PRIVATE_KEY="$2"; shift ;;
        *) echo "Parámetro desconocido: $1"; exit 1 ;;
    esac
    shift
done

echo "=== Instalador Magento Docker ==="
echo "Dominio: $DOMAIN"
echo "Directorio: $INSTALL_DIR"
echo "Versión Magento: $MAGENTO_VERSION"

# 1. Instalar Docker si no existe
if ! command -v docker &> /dev/null; then
    echo "[!] Docker no detectado. Instalando Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    echo "[!] Docker instalado."
else
    echo "[OK] Docker ya está instalado."
fi

# Alias temporal para usar docker con sudo si es necesario
dcompose() {
    if docker ps &>/dev/null; then
        docker compose "$@"
    else
        sudo docker compose "$@"
    fi
}

# 2. Claves de Composer
if [[ -z "$MAGENTO_PUBLIC_KEY" || -z "$MAGENTO_PRIVATE_KEY" ]]; then
    echo ""
    echo "Magento 2 requiere claves de autenticación del Marketplace para su descarga."
    read -p "Ingresa tu Magento Public Key: " MAGENTO_PUBLIC_KEY
    read -s -p "Ingresa tu Magento Private Key: " MAGENTO_PRIVATE_KEY
    echo ""
fi

# Crear auth.json en el host (docker-magento lo mapea automáticamente)
mkdir -p ~/.composer
cat <<EOF > ~/.composer/auth.json
{
    "http-basic": {
        "repo.magento.com": {
            "username": "$MAGENTO_PUBLIC_KEY",
            "password": "$MAGENTO_PRIVATE_KEY"
        }
    }
}
EOF
chmod 600 ~/.composer/auth.json

# 3. Descargar Plantilla Docker Magento
echo "[*] Configurando entorno Docker en $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ ! -f "compose.yaml" ] && [ ! -f "docker-compose.yml" ]; then
    echo "[*] Descargando template..."
    curl -s https://raw.githubusercontent.com/markshust/docker-magento/master/lib/template | bash
fi

# Reemplazar dominio
if [ -f "env/app.env" ]; then
    sed -i "s/magento.test/$DOMAIN/g" env/app.env
fi

if grep -q "magento.test" docker-compose.yml 2>/dev/null; then
    sed -i "s/magento.test/$DOMAIN/g" docker-compose.yml
fi
if grep -q "magento.test" compose.yaml 2>/dev/null; then
    sed -i "s/magento.test/$DOMAIN/g" compose.yaml
fi

# Ajustar versión en bin/setup si es posible (aunque bin/download ya la especifica)
if [ -f "bin/setup" ]; then
    sed -i "s/magento\/project-community-edition/magento\/project-community-edition $MAGENTO_VERSION/g" bin/setup
fi

# 4. Descargar Magento y Levantarlo
echo "[*] Descargando Magento $MAGENTO_VERSION..."
./bin/download community "$MAGENTO_VERSION" || true

echo "[*] Levantando contenedores..."
./bin/start

echo "[*] Ejecutando instalación de Magento (esto tomará varios minutos)..."
# Usamos un modo no interactivo si es posible, o bin/setup normal
./bin/setup "$DOMAIN"

# 5. Bucle de Verificación
echo "[*] Verificando despliegue..."
RETRY_COUNT=0
HTTP_STATUS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Chequeando http://$DOMAIN... (Intento $((RETRY_COUNT+1))/$MAX_RETRIES)"
    # Hacemos la prueba localmente al puerto 80 del servidor
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --resolve "$DOMAIN:80:127.0.0.1" "http://$DOMAIN" || true)
    
    if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "301" ] || [ "$HTTP_STATUS" = "302" ]; then
        echo "[OK] ¡Magento está levantado y responde HTTP $HTTP_STATUS!"
        break
    else
        echo "[WARN] Código HTTP $HTTP_STATUS. Esperando 15 segundos..."
        sleep 15
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "[ERROR] Falló la verificación luego de $MAX_RETRIES intentos."
    dcompose ps
    exit 1
fi

echo "=== Instalación Completada Exitosamente ==="
echo "Panel de admin accesible. Verifica las credenciales en la salida del comando bin/setup."
