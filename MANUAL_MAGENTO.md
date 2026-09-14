# 📘 Manual de Operaciones Básicas: Magento en Docker

Este entorno de Magento está basado en la arquitectura de contenedores Docker (utilizando los scripts de Mark Shust). Como resultado, **no debes ejecutar los comandos de Magento directamente en tu servidor**, sino a través de los scripts proporcionados en la carpeta `bin/` que se comunican con los contenedores.

A continuación, tienes la lista de los comandos más importantes para el desarrollo y mantenimiento del día a día. Todos los comandos deben ejecutarse desde la raíz del proyecto (donde se encuentra la carpeta `bin`).

---

## 🚀 1. Control del Servidor (Docker)

Estos comandos controlan el encendido y apagado de los contenedores (Nginx, PHP, Base de Datos, Redis, etc.).

*   **Encender el entorno:**
    ```bash
    ./bin/start
    ```
    *(Nota: Si quieres arrancar sin montar los archivos locales de desarrollo, usa `./bin/start --no-dev`)*
*   **Apagar el entorno:**
    ```bash
    ./bin/stop
    ```
*   **Reiniciar todo el entorno:**
    ```bash
    ./bin/restart
    ```

---

## 🧹 2. Caché y Reindexación

Magento depende fuertemente de la caché y de los índices (Opensearch/Elasticsearch) para ser rápido.

*   **Limpiar TODA la caché (Cache Flush):**
    ```bash
    ./bin/clinotty bin/magento cache:flush
    ```
*   **Reindexar todos los datos (Productos, Precios, Categorías):**
    ```bash
    ./bin/clinotty bin/magento indexer:reindex
    ```
    *(Útil cuando agregas productos nuevos y no aparecen en el frontend).*

---

## 🛠️ 3. Despliegue (Deploy) y Compilación

Cuando instalas un módulo nuevo o haces cambios profundos en el código/diseño, debes recompilar Magento.

*   **Compilar el código (Inyección de Dependencias):**
    ```bash
    ./bin/clinotty bin/magento setup:di:compile
    ```
*   **Desplegar contenido estático (CSS, JS, Imágenes del tema):**
    ```bash
    ./bin/clinotty bin/magento setup:static-content:deploy -f
    ```
    *(El `-f` fuerza el despliegue incluso si estás en modo desarrollador).*
*   **Actualizar la base de datos tras instalar un módulo:**
    ```bash
    ./bin/clinotty bin/magento setup:upgrade
    ```

> **💡 Secuencia de Despliegue Completo (El Combo Maestro):**
> Si subes código nuevo o instalas un módulo, corre esta secuencia para asegurar que todo cargue perfecto:
> ```bash
> ./bin/clinotty bin/magento setup:upgrade
> ./bin/clinotty bin/magento setup:di:compile
> ./bin/clinotty bin/magento setup:static-content:deploy -f
> ./bin/clinotty bin/magento cache:flush
> ```

---

## 🔐 4. Permisos y Propietarios

Si notas errores 403 Forbidden, pantallas en blanco repentinas o problemas al subir imágenes, suele ser un problema de permisos en los archivos.

*   **Arreglar dueños de archivos (Ownership):**
    ```bash
    ./bin/fixowns
    ```
*   **Arreglar permisos de escritura (Permissions):**
    ```bash
    ./bin/fixperms
    ```

---

## ⚙️ 5. Modos de Magento

Magento tiene tres modos principales: `developer` (muestra errores, no usa caché estricta), `production` (ultra rápido, pero oculta errores) y `default`.

*   **Activar Modo Desarrollador:**
    ```bash
    ./bin/clinotty bin/magento deploy:mode:set developer
    ```
*   **Activar Modo Producción (Usa esto cuando lances tu tienda oficial):**
    ```bash
    ./bin/clinotty bin/magento deploy:mode:set production
    ```

---

## 💻 6. Acceso Directo al Contenedor (Avanzado)

Si deseas entrar directamente a la consola de Linux dentro del contenedor de PHP (donde vive Magento) para ejecutar comandos nativos:

*   **Entrar por SSH al contenedor web:**
    ```bash
    ./bin/bash
    ```
    *(Para salir, simplemente escribe `exit`).*

---

> **⚠️ Acerca de `./bin/clinotty`:** 
> Verás que muchos comandos empiezan con `./bin/clinotty`. Este es un script mágico que envía el comando `bin/magento` directamente al contenedor interno de PHP. ¡No lo omitas!

---

## ☁️ 7. Comandos de Magento Cloud CLI

Si estás trabajando con proyectos hosteados en **Adobe Commerce on Cloud**, utilizamos la herramienta `magento-cloud`. Esta herramienta **se ejecuta en tu máquina (o VPS)**, y no dentro del contenedor de Docker.

### Instalación Manual (Si olvidaste hacerlo en el script inicial)
Si olvidaste usar el flag `--install-cloud-cli` durante la instalación, puedes instalar la herramienta ejecutando este bloque de comandos en tu terminal (Host):
```bash
sudo apt-get update && sudo apt-get install -y php-cli php-curl php-xml php-mbstring curl git unzip
curl -sS https://accounts.magento.cloud/cli/installer | php
export PATH="$PATH:$HOME/.magento-cloud/bin"
echo 'export PATH="$PATH:$HOME/.magento-cloud/bin"' >> ~/.bashrc
```

### Comandos Cloud más utilizados:

*   **Iniciar sesión en tu cuenta de Cloud:**
    ```bash
    magento-cloud login
    ```
*   **Listar todos tus proyectos de la nube:**
    ```bash
    magento-cloud project:list
    ```
*   **Descargar (Clonar) un proyecto de la nube a tu servidor local:**
    ```bash
    magento-cloud get <ID_DEL_PROYECTO>
    ```
*   **Listar los entornos (ramas) del proyecto actual:**
    ```bash
    magento-cloud environment:list
    ```
*   **Conectarse por SSH a un entorno de la nube:**
    ```bash
    magento-cloud ssh
    ```
*   **Ver los logs del servidor en la nube (ej. errores de despliegue):**
    ```bash
    magento-cloud log
    ```
