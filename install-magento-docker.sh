#!/bin/bash
set -e

# Valores por defecto
DOMAIN="mag.e-misario.com"
INSTALL_DIR="$HOME/magento"
MAGENTO_VERSION="2.4.7-p2"
MAX_RETRIES=5
GITHUB_REPO=""
CF_TOKEN=""
INSTALL_CLOUD_CLI=false
CONFIGURE_VPS=true

# Parsear argumentos
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -d|--domain) DOMAIN="$2"; shift ;;
        -p|--path) INSTALL_DIR="$2"; shift ;;
        -v|--version) MAGENTO_VERSION="$2"; shift ;;
        --public-key) MAGENTO_PUBLIC_KEY="$2"; shift ;;
        --private-key) MAGENTO_PRIVATE_KEY="$2"; shift ;;
        --github-repo) GITHUB_REPO="$2"; shift ;;
        --cf-token) CF_TOKEN="$2"; shift ;;
        --install-cloud-cli) INSTALL_CLOUD_CLI=true ;;
        --skip-vps-optimizations) CONFIGURE_VPS=false ;;
        *) echo "Parámetro desconocido: $1"; exit 1 ;;
    esac
    shift
done

echo "=== Instalador Magento Docker ==="
echo "Dominio: $DOMAIN"
echo "Directorio: $INSTALL_DIR"
echo "Versión Magento: $MAGENTO_VERSION"
echo "Optimización VPS: $CONFIGURE_VPS"

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

# 2. Optimizaciones del Sistema para VPS (OpenSearch, Memoria y Swap)
if [ "$CONFIGURE_VPS" = true ]; then
    echo "=== Configurando optimizaciones del sistema para VPS ==="

    # 2.1 Ajustar vm.max_map_count (Requisito estricto para OpenSearch / Elasticsearch)
    if [ -f /proc/sys/vm/max_map_count ]; then
        CURRENT_MAP_COUNT=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 0)
        if [ "$CURRENT_MAP_COUNT" -lt 262144 ]; then
            echo "[*] Ajustando vm.max_map_count a 262144 para OpenSearch..."
            sudo sysctl -w vm.max_map_count=262144
            
            # Persistir en /etc/sysctl.d/ o /etc/sysctl.conf
            if [ -d /etc/sysctl.d ]; then
                echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-magento-opensearch.conf > /dev/null
            elif [ -f /etc/sysctl.conf ] && ! grep -q "vm.max_map_count" /etc/sysctl.conf; then
                echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf > /dev/null
            fi
            echo "[OK] vm.max_map_count persistido en 262144."
        else
            echo "[OK] vm.max_map_count ya configurado adecuadamente ($CURRENT_MAP_COUNT)."
        fi
    fi

    # 2.2 Configuración de memoria Swap (4GB para prevenir OOM durante instalación y compilación)
    if [ -f /proc/meminfo ]; then
        TOTAL_SWAP_KB=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
        # Si el swap es inferior a 2GB (2097152 KB), configuramos 4GB de swap
        if [ "$TOTAL_SWAP_KB" -lt 2097152 ]; then
            SWAPFILE="/swapfile"
            echo "[*] Swap detectado insuficiente (${TOTAL_SWAP_KB} kB). Configurando Swap de 4GB en $SWAPFILE..."
            if [ ! -f "$SWAPFILE" ]; then
                if command -v fallocate &> /dev/null; then
                    sudo fallocate -l 4G "$SWAPFILE" || sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=4096
                else
                    sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=4096
                fi
                sudo chmod 600 "$SWAPFILE"
                sudo mkswap "$SWAPFILE"
                sudo swapon "$SWAPFILE"

                # Persistir en /etc/fstab si no está presente
                if [ -f /etc/fstab ] && ! grep -q "$SWAPFILE" /etc/fstab; then
                    echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
                fi
                echo "[OK] Swap de 4GB creado y activado exitosamente."
            else
                echo "[!] El archivo $SWAPFILE ya existía. Asegurando activación..."
                sudo swapon "$SWAPFILE" 2>/dev/null || true
            fi

            # Ajustar swappiness a 10 para priorizar el uso de RAM física
            sudo sysctl -w vm.swappiness=10 2>/dev/null || true
            if [ -d /etc/sysctl.d ]; then
                echo "vm.swappiness=10" | sudo tee /etc/sysctl.d/99-magento-swappiness.conf > /dev/null
            elif [ -f /etc/sysctl.conf ] && ! grep -q "vm.swappiness" /etc/sysctl.conf; then
                echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null
            fi
        else
            echo "[OK] Swap suficiente detectado: $((TOTAL_SWAP_KB / 1024)) MB."
        fi
    fi
fi

# Alias temporal para usar docker con sudo si es necesario
dcompose() {
    if docker ps &>/dev/null; then
        docker compose "$@"
    else
        sudo docker compose "$@"
    fi
}

# 3. Claves de Composer
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

# 4. Descargar Plantilla Docker Magento
echo "[*] Configurando entorno Docker en $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [ ! -f "compose.yaml" ] && [ ! -f "docker-compose.yml" ]; then
    echo "[*] Descargando template..."
    curl -s https://raw.githubusercontent.com/markshust/docker-magento/master/lib/template | bash
fi

# Reemplazar dominio y optimizar límites de memoria de PHP
if [ -f "env/app.env" ]; then
    sed -i "s/magento.test/$DOMAIN/g" env/app.env

    # Asegurar límite de memoria de PHP en 4G para evitar OOM en setup:di:compile
    if grep -q "^PHP_MEMORY_LIMIT=" env/app.env; then
        sed -i "s/^PHP_MEMORY_LIMIT=.*/PHP_MEMORY_LIMIT=4G/g" env/app.env
    else
        echo "PHP_MEMORY_LIMIT=4G" >> env/app.env
    fi

    # Desactivar límite de memoria para Composer
    if ! grep -q "COMPOSER_MEMORY_LIMIT" env/app.env; then
        echo "COMPOSER_MEMORY_LIMIT=-1" >> env/app.env
    fi
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

# 4.2 Inject Cloudflare Tunnel si se proveyó el token
if [ -n "$CF_TOKEN" ]; then
    echo "[*] Inyectando servicio Cloudflare Tunnel (cloudflared) a compose.yaml..."
    cat <<EOF >> compose.yaml

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel --no-autoupdate run
    environment:
      - TUNNEL_TOKEN=$CF_TOKEN
    restart: unless-stopped
EOF
fi

# 5. Descargar Magento y Levantarlo
echo "[*] Descargando Magento $MAGENTO_VERSION..."
./bin/download community "$MAGENTO_VERSION" || true

echo "[*] Levantando contenedores..."
./bin/start

echo "[*] Ejecutando instalación de Magento (esto tomará varios minutos)..."
# Usamos un modo no interactivo si es posible. Permitimos que falle al final (|| true) 
# porque bin/setup intenta editar /etc/hosts con sudo al terminar, lo cual falla en VPS sin TTY.
./bin/setup "$DOMAIN" || true

echo "[*] Aplicando correcciones finales de permisos post-instalación (por fallos del script original)..."
./bin/fixowns
./bin/fixperms
./bin/clinotty bin/magento cache:flush
./bin/clinotty bin/magento cron:install
./bin/clinotty bin/magento deploy:mode:set developer

# 6. Parche crítico: En producción sin compose.dev.yaml, nginx.conf nunca se genera dentro del contenedor
echo "[*] Parcheando nginx.conf dentro del contenedor (Bug de plantilla en modo producción)..."
docker compose exec -T app cp /var/www/html/nginx.conf.sample /var/www/html/nginx.conf || true
docker compose exec -T app sed -E -i "s/fastcgi_pass[[:space:]]+fastcgi_backend;/fastcgi_pass \$fastcgi_backend;/g" /var/www/html/nginx.conf || true
docker compose exec -T app nginx -s reload || true

# 7. Integración con repositorio GitHub para desarrollo (Opcional)
if [ -n "$GITHUB_REPO" ]; then
    echo "[*] Configurando repositorio GitHub para desarrollo en $GITHUB_REPO..."
    # Mark Shust template ya inicializa un git local, agregamos el remoto
    git remote add origin "$GITHUB_REPO" || git remote set-url origin "$GITHUB_REPO"
    git branch -M main
    git add .
    git commit -m "Initial Magento $MAGENTO_VERSION Docker setup" || true
    git push -u origin main || echo "[WARN] No se pudo hacer push al repositorio. Asegúrate de tener configuradas tus llaves SSH de GitHub en el VPS."
fi

# 8. Bucle de Verificación
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

# 9. Integración de Magento Cloud CLI (Opcional)
if [ "$INSTALL_CLOUD_CLI" = true ]; then
    echo "[*] Instalando dependencias para Magento Cloud CLI en el Host..."
    sudo apt-get update && sudo apt-get install -y php-cli php-curl php-xml php-mbstring curl git unzip || echo "[!] Advertencia: No se pudieron instalar dependencias de PHP. El CLI podría no funcionar."
    echo "[*] Descargando e instalando Magento Cloud CLI..."
    curl -sS https://accounts.magento.cloud/cli/installer | php
    
    # Agregar al path si no existe
    if ! grep -q "magento-cloud/bin" ~/.bashrc; then
        echo 'export PATH="$PATH:$HOME/.magento-cloud/bin"' >> ~/.bashrc
    fi
    echo "[*] Magento Cloud CLI instalado. Reinicia tu terminal o ejecuta 'source ~/.bashrc' y luego 'magento-cloud login'."
fi

echo "=== Instalación Completada Exitosamente ==="
echo "Panel de admin accesible. Verifica las credenciales en la salida del comando bin/setup."
