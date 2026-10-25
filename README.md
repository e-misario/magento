# Instalador de Magento 2.4.8 con Docker

Este repositorio contiene un script automatizado para instalar **Magento 2.4.8** en un servidor Ubuntu utilizando el entorno Docker de Mark Shust.

## Requisitos Previos

- Servidor Ubuntu (probado en 24.04).
- Cuenta en Magento Marketplace para obtener claves de acceso (Public y Private Key).

## Uso

1. Clona este repositorio o copia el script `install-magento-docker.sh` en tu servidor:
   ```bash
   git clone git@github.com:e-misario/magento.git
   cd magento
   chmod +x install-magento-docker.sh
   ```

2. Ejecuta el script. Puedes proporcionar tu dominio y las claves como argumentos o de forma interactiva:
   ```bash
   ./install-magento-docker.sh -d mag.e-misario.com
   ```

### Parámetros Aceptados
- `-d, --domain`: Dominio para la tienda (por defecto: `mag.e-misario.com`)
- `-p, --path`: Directorio de instalación (por defecto: `$HOME/magento`)
- `-v, --version`: Versión de Magento (por defecto: `2.4.7-p2`)
- `--public-key`: Tu clave pública de Magento Marketplace.
- `--private-key`: Tu clave privada de Magento Marketplace.
- `--github-repo`: (Opcional) URL SSH de tu repositorio de GitHub para integrarlo automáticamente.
- `--cf-token`: (Opcional) Tu token de Cloudflare Zero Trust (Tunnel) para exponer la tienda sin abrir puertos.
- `--install-cloud-cli`: (Opcional) Instala la herramienta de línea de comandos `magento-cloud` para gestionar proyectos en Adobe Commerce Cloud.
- `--skip-vps-optimizations`: (Opcional) Omite la creación de Swap de 4GB y el ajuste del kernel `vm.max_map_count`.

Ejemplo completo automatizado:
```bash
./install-magento-docker.sh -d mag.e-misario.com -p /home/ubuntu/magento -v 2.4.7-p2 --public-key "TU_PUBLIC_KEY" --private-key "TU_PRIVATE_KEY"
```

## Estructura del Script

1. **Instalación de Docker**: Verifica e instala Docker y sus dependencias automáticamente si no están presentes.
2. **Optimizaciones para VPS**:
   - Ajusta y persiste `vm.max_map_count=262144` (imprescindible para el arranque de contenedores OpenSearch / Elasticsearch).
   - Crea y activa un archivo Swap de 4GB (`/swapfile`) con `swappiness=10` si el VPS tiene menos de 2GB de swap, evitando que el OOM-killer cierre procesos de compilación o instalación.
3. **Credenciales**: Configura las credenciales de Composer (`~/.composer/auth.json`) para el repositorio oficial de Magento.
4. **Configuración del Entorno**:
   - Descarga la plantilla de Mark Shust (`docker-magento`).
   - Configura el dominio personalizado.
   - Ajusta `PHP_MEMORY_LIMIT=4G` y `COMPOSER_MEMORY_LIMIT=-1` en `env/app.env` para evitar caídas de memoria durante `setup:di:compile`.
   - Inyecta Cloudflare Tunnel si se especificó el token.
5. **Descarga e Instalación**: Descarga la versión de Magento indicada y ejecuta el aprovisionamiento.
6. **Parche de Nginx**: Genera y recarga `nginx.conf` corrigiendo el bug de plantilla en producción.
7. **Git**: Inicializa y enlaza con repositorio remoto en GitHub si se especificó `--github-repo`.
8. **Verificación**: Bucle con reintentos para asegurar que el sitio responda en HTTP 200/301/302.
9. **Magento Cloud CLI**: Opcionalmente instala y configura la herramienta `magento-cloud`.

