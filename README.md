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

Ejemplo completo automatizado:
```bash
./install-magento-docker.sh -d mag.e-misario.com -p /home/ubuntu/magento -v 2.4.8 --public-key "TU_PUBLIC_KEY" --private-key "TU_PRIVATE_KEY"
```

## Estructura del Script

- Verifica e instala **Docker** automáticamente si no está presente.
- Configura las credenciales de Composer.
- Descarga el template base de **Mark Shust's Docker Magento**.
- Ajusta el entorno y arranca los contenedores.
- Realiza un bucle de verificación de 5 intentos para confirmar que el sitio responda con un HTTP `200` o redirección `301/302`.
