#!/bin/bash

# Terminar ejecución si hay un error crítico
set -e

# ==============================================================================
# 0. INSTALACIÓN AUTOMÁTICA DE DOCKER (se omite si ya está instalado)
# ==============================================================================
echo "================================================="
echo "🐳 0. Verificando instalación de Docker..."
echo "================================================="

SUDO=""
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
fi

if ! command -v docker &> /dev/null; then
    echo "⚙️  Docker no está instalado. Instalando desde el repositorio oficial..."

    $SUDO apt-get update -y
    $SUDO apt-get install -y ca-certificates curl gnupg sudo

    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null

    $SUDO apt-get update -y
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    $SUDO systemctl enable --now docker
    echo "✅ Docker instalado y activo."
else
    echo "✅ Docker ya está instalado. Se omite instalación."
fi

# ==============================================================================
# 0.1 USUARIO ADMINISTRATIVO CON SUDO
# ==============================================================================
echo "================================================="
echo "👤 0.1 Configurando usuario administrativo..."
echo "================================================="

SUDO_USER_NAME="$1"
SUDO_USER_PASS="$2"

if [ -z "$SUDO_USER_NAME" ]; then
    read -p "👉 Nombre del usuario sudo a crear/usar: " SUDO_USER_NAME
fi

if [ -z "$SUDO_USER_PASS" ]; then
    read -s -p "👉 Contraseña para '$SUDO_USER_NAME': " SUDO_USER_PASS
    echo ""
fi

if [ -z "$SUDO_USER_NAME" ] || [ -z "$SUDO_USER_PASS" ]; then
    echo "❌ Debes indicar usuario y contraseña (por parámetro o interactivo). Abortando."
    exit 1
fi

if ! id "$SUDO_USER_NAME" &> /dev/null; then
    echo "⚙️  Creando usuario '$SUDO_USER_NAME'..."
    $SUDO useradd -m -s /bin/bash "$SUDO_USER_NAME"
    $SUDO usermod -aG sudo "$SUDO_USER_NAME"
    echo "✅ Usuario '$SUDO_USER_NAME' creado y añadido a sudo."
else
    echo "✅ El usuario '$SUDO_USER_NAME' ya existía."
    if ! id -nG "$SUDO_USER_NAME" | grep -qw sudo; then
        $SUDO usermod -aG sudo "$SUDO_USER_NAME"
        echo "   Se añadió a sudo (no lo estaba)."
    fi
fi

echo "$SUDO_USER_NAME:$SUDO_USER_PASS" | $SUDO chpasswd
echo "✅ Contraseña de '$SUDO_USER_NAME' establecida/actualizada."

for U in "$USER" "$SUDO_USER_NAME"; do
    if ! id -nG "$U" 2>/dev/null | grep -qw docker; then
        $SUDO usermod -aG docker "$U" 2>/dev/null || true
    fi
done

# ==============================================================================
# 0.2/0.3 CLONAR/ACTUALIZAR REPOSITORIO Y AUTO-RELANZAR
# ==============================================================================
REPO_URL="https://github.com/LXA21/nexora"
REPO_DIR="$HOME/nexora-repo"

SCRIPT_ACTUAL="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

echo "================================================="
echo "📥 0.3 Sincronizando repositorio nexora..."
echo "================================================="
if [ -d "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" pull "$REPO_URL"
else
    git clone "$REPO_URL" "$REPO_DIR"
fi
echo "✅ Repositorio listo y actualizado en $REPO_DIR."
chmod +x "$REPO_DIR/iniciar.sh"

if [ "$SCRIPT_ACTUAL" != "$REPO_DIR" ]; then
    echo "🔁 Relanzando desde la copia actualizada..."
    exec "$REPO_DIR/iniciar.sh" "$SUDO_USER_NAME" "$SUDO_USER_PASS"
fi

echo "✅ Ejecutando desde el repositorio sincronizado y actualizado ($REPO_DIR)."

# ==============================================================================
# 0.35 EXTRACCIÓN DEL CÓDIGO FUENTE EMPAQUETADO EN .ZIP
# ==============================================================================
echo "================================================="
echo "📦 0.35 Extrayendo código fuente del proyecto (.zip)..."
echo "================================================="

if ! command -v unzip &> /dev/null; then
    echo "⚙️  Instalando unzip..."
    $SUDO apt-get install -y unzip
fi

ZIP_FILE=$(find "$REPO_DIR" -maxdepth 1 -name "*.zip" | head -n 1)

if [ -n "$ZIP_FILE" ]; then
    echo "📥 Descomprimiendo $(basename "$ZIP_FILE")..."
    TMP_EXTRACT="$REPO_DIR/.extract_tmp"
    rm -rf "$TMP_EXTRACT"
    mkdir -p "$TMP_EXTRACT"
    unzip -oq "$ZIP_FILE" -d "$TMP_EXTRACT"

    CONTENIDO_ZIP=($(ls -A "$TMP_EXTRACT"))
    if [ "${#CONTENIDO_ZIP[@]}" -eq 1 ] && [ -d "$TMP_EXTRACT/${CONTENIDO_ZIP[0]}" ]; then
        cp -rf "$TMP_EXTRACT/${CONTENIDO_ZIP[0]}/." "$REPO_DIR/"
    else
        cp -rf "$TMP_EXTRACT/." "$REPO_DIR/"
    fi

    rm -rf "$TMP_EXTRACT"
    echo "✅ Código fuente descomprimido en $REPO_DIR."
else
    echo "ℹ️  No se encontró ningún .zip en el repositorio."
fi

# ==============================================================================
# 0.4 VERIFICACIÓN Y LIMPIEZA PREVIA DE DOCKER
# ==============================================================================
echo "================================================="
echo "🧹 0.4 Verificando Docker y ejecutando limpieza previa..."
echo "================================================="
if ! docker info > /dev/null 2>&1; then
    echo "⚡ Iniciando el servicio de Docker..."
    sudo service docker start
fi

docker container prune -f > /dev/null 2>&1 || true
docker network prune -f > /dev/null 2>&1 || true
echo "✅ Limpieza global previa completada."

# ==============================================================================
# 1. CONFIGURACIÓN DE DIRECTORIO DE TRABAJO
# ==============================================================================
RUTA_ORIGEN="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DIR_PADRE="$(dirname "$RUTA_ORIGEN")"

cd "$RUTA_ORIGEN"

# ==============================================================================
# 1.1 VERIFICACIÓN DEL CÓDIGO FUENTE
# ==============================================================================
echo "================================================="
echo "📦 1.1 Verificando código fuente..."
echo "================================================="

if [ -f "$RUTA_ORIGEN/Dockerfile" ]; then
    echo "✅ Código fuente presente (Dockerfile encontrado en el repo)."
else
    echo "⚠️  No se encontró Dockerfile en el repositorio clonado."
fi

# ==============================================================================
# 1.2 CONSTRUCCIÓN/ETIQUETADO DE IMÁGENES
# ==============================================================================
echo "================================================="
echo "🏗️  1.2 Verificando imágenes Docker necesarias..."
echo "================================================="

if [ -f "$RUTA_ORIGEN/Dockerfile" ]; then
    echo "🔨 Reconstruyendo mi_p1_web:latest desde $RUTA_ORIGEN..."
    docker image rm mi_p1_web:latest > /dev/null 2>&1 || true
    docker build -t mi_p1_web:latest "$RUTA_ORIGEN"
    echo "✅ mi_p1_web:latest reconstruida con el código más reciente."
else
    echo "❌ No se encontró Dockerfile para construir mi_p1_web:latest. Abortando."
    exit 1
fi

if ! docker image inspect mi_p1_mysql:latest > /dev/null 2>&1; then
    echo "⬇️  mi_p1_mysql:latest no existe. Descargando..."
    docker pull mariadb:latest
    docker tag mariadb:latest mi_p1_mysql:latest
    echo "✅ mi_p1_mysql:latest lista."
else
    echo "✅ mi_p1_mysql:latest ya existe. Se omite descarga."
fi

if ! docker image inspect mi_p1_pma:latest > /dev/null 2>&1; then
    echo "⬇️  mi_p1_pma:latest no existe. Descargando..."
    docker pull phpmyadmin:latest
    docker tag phpmyadmin:latest mi_p1_pma:latest
    echo "✅ mi_p1_pma:latest lista."
else
    echo "✅ mi_p1_pma:latest ya existe. Se omite descarga."
fi

# ==============================================================================
# 2. CREACIÓN SECUENCIAL DE CARPETA Y ENTORNO
# ==============================================================================
CONTADOR=1
CARPETA_DESTINO="$DIR_PADRE/P${CONTADOR}"

while [ -d "$CARPETA_DESTINO" ] || docker ps -a --format '{{.Names}}' | grep -q "^P${CONTADOR}_"; do
    CONTADOR=$((CONTADOR + 1))
    CARPETA_DESTINO="$DIR_PADRE/P${CONTADOR}"
done

NOMBRE_CARPETA=$(basename "$CARPETA_DESTINO")

echo "================================================="
echo "📁 1. Creando entorno en: $CARPETA_DESTINO"
echo "================================================="
mkdir -p "$CARPETA_DESTINO"

cp docker-compose.yml "$CARPETA_DESTINO/"
cd "$CARPETA_DESTINO"

# ==============================================================================
# 3. ASIGNACIÓN MATEMÁTICA Y VERIFICACIÓN DE PUERTOS
# ==============================================================================
echo "🔍 2. Calculando bloques y verificando disponibilidad..."

NUM_INSTANCIA=$((CONTADOR - 1))

PUERTO_WEB_ORIGINAL=$((1080 + (NUM_INSTANCIA * 2)))
PUERTO_PMA_ORIGINAL=$((8081 + (NUM_INSTANCIA * 2)))
PUERTO_DB_ORIGINAL=$((3307 + NUM_INSTANCIA))
PUERTO_SSL_ORIGINAL=$((8443 + (NUM_INSTANCIA * 2)))

verificar_y_corregir() {
    local puerto=$1
    local incremento=$2
    while ss -tuln | grep -q ":$puerto "; do
        puerto=$((puerto + incremento))
    done
    echo "$puerto"
}

PUERTO_WEB=$(verificar_y_corregir $PUERTO_WEB_ORIGINAL 2)
PUERTO_PMA=$(verificar_y_corregir $PUERTO_PMA_ORIGINAL 2)
PUERTO_DB=$(verificar_y_corregir $PUERTO_DB_ORIGINAL 1)
PUERTO_SSL=$(verificar_y_corregir $PUERTO_SSL_ORIGINAL 2)

export PUERTO_WEB
export PUERTO_DB
export PUERTO_PMA
export PUERTO_SSL
export PREFIX_CONTENEDOR="${NOMBRE_CARPETA}"

cat > .env <<EOF
PUERTO_WEB=${PUERTO_WEB}
PUERTO_DB=${PUERTO_DB}
PUERTO_PMA=${PUERTO_PMA}
PUERTO_SSL=${PUERTO_SSL}
PREFIX_CONTENEDOR=${PREFIX_CONTENEDOR}
EOF

# ==============================================================================
# 4. LEVANTAMIENTO DE CONTENEDORES
# ==============================================================================
echo "🐳 3. Desplegando contenedores ($NOMBRE_CARPETA)..."

docker compose down > /dev/null 2>&1 || true
docker compose up -d --force-recreate -V --remove-orphans

# ==============================================================================
# 5. ESPERA ACTIVA Y ASIGNACIÓN AUTOMÁTICA DE PERMISOS
# ==============================================================================
echo "⏳ 4. Esperando a que el motor de MySQL esté totalmente listo..."

until docker exec "${NOMBRE_CARPETA}_db" mysqladmin ping -u root --silent > /dev/null 2>&1; do
    echo "   ... MySQL aún se está inicializando, esperando 2 segundos más..."
    sleep 2
done

echo "⚡ MySQL detectado y listo. Verificando autenticación de root..."

if docker exec "${NOMBRE_CARPETA}_db" mysql -u root -e "SELECT 1;" > /dev/null 2>&1; then
    echo "   ✅ root autenticado sin contraseña."
else
    echo "❌ No se pudo autenticar como root en MySQL."
    exit 1
fi

# ==============================================================================
# 4.1 IMPORTACIÓN DEL ESQUEMA Y CREACIÓN DEL USUARIO
# ==============================================================================
echo "================================================="
echo "📜 4.1 Verificando/Importando esquema de 'sistema_facturacion' (database.sql)..."
echo "================================================="

FULL_SQL="$RUTA_ORIGEN/database.sql"

if [ ! -f "$FULL_SQL" ]; then
    echo "❌ No se encontró $FULL_SQL. Abortando importación de esquema."
    exit 1
fi

# Asegurar la creación de la base de datos por si no se creó automáticamente
docker exec "${NOMBRE_CARPETA}_db" mysql -u root -e "CREATE DATABASE IF NOT EXISTS sistema_facturacion;"

TABLAS_EXISTENTES=$(docker exec "${NOMBRE_CARPETA}_db" mysql -u root -N -B \
    -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='sistema_facturacion';" 2>/dev/null || echo "0")

if [ "$TABLAS_EXISTENTES" = "0" ] || [ "$TABLAS_EXISTENTES" = "" ]; then
    echo "⚙️  Base de datos vacía. Importando esquema y datos iniciales desde database.sql..."
    docker exec -i "${NOMBRE_CARPETA}_db" mysql -u root sistema_facturacion < "$FULL_SQL"
    echo "✅ Esquema y datos importados correctamente."
else
    echo "✅ El esquema ya existe. Se omite importación para no duplicar datos."
fi

echo "⚡ Otorgando permisos a 'comanda'..."
docker exec "${NOMBRE_CARPETA}_db" mysql -u root -e \
    "CREATE USER IF NOT EXISTS 'comanda'@'%' IDENTIFIED BY ''; \
    GRANT ALL PRIVILEGES ON *.* TO 'comanda'@'%'; \
    FLUSH PRIVILEGES;"
echo "✅ Permisos de la base de datos otorgados correctamente al usuario 'comanda'."

# ==============================================================================
# 6. REPORTE FINAL CON IP DINÁMICA
# ==============================================================================
IP_SERVIDOR=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}')

if [ -z "$IP_SERVIDOR" ]; then
    IP_SERVIDOR=$(hostname -I | tr ' ' '\n' | grep -vE '^172\.|^127\.' | head -n 1)
fi

if [ -z "$IP_SERVIDOR" ]; then
    IP_SERVIDOR=$(hostname -I | awk '{print $1}')
fi

echo ""
echo "================================================="
echo "🎉 ¡DESPLIEGUE EXITOSO EN LA CARPETA: $NOMBRE_CARPETA!"
echo "================================================="
echo "📌 DETALLE DE ASIGNACIÓN DE PUERTOS:"
echo "-------------------------------------------------"
echo "🌐 Web (App)      -> Asignado: $PUERTO_WEB"
echo "🔐 Web (SSL)      -> Asignado: $PUERTO_SSL"
echo "🗄️  phpMyAdmin     -> Asignado: $PUERTO_PMA"
echo "💾 Base de Datos  -> Asignado: Puerto $PUERTO_DB"
echo "-------------------------------------------------"
echo "🔗 URLs de acceso directo:"
echo "   - Web          : http://$IP_SERVIDOR:$PUERTO_WEB"
echo "   - Web (HTTPS)  : https://$IP_SERVIDOR:$PUERTO_SSL  (certificado autofirmado)"
echo "   - phpMyAdmin   : http://$IP_SERVIDOR:$PUERTO_PMA"
echo "================================================="