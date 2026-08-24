#!/bin/bash
set -Eeuo pipefail
 
# ============================================================================== 
# INSTALADOR UNIVERSAL DEFINITIVO
# Docker / Docker Compose / MySQL / MariaDB / PostgreSQL
#
# Objetivos principales:
#   - Cada ejecución crea una instancia aislada: P1, P2, P3...
#   - Nunca elimina volúmenes automáticamente.
#   - Nunca reutiliza silenciosamente un volumen de otra instancia.
#   - No cambia MySQL <-> MariaDB sobre datos existentes.
#   - No sustituye una imagen existente por :latest en un despliegue nuevo.
#   - Detecta container_name, volumes, networks, bind mounts y puertos fijos
#     que puedan romper el aislamiento antes de ejecutar docker compose up.
#   - Los puertos/variables de instancia se generan en Pn/.env y se pasan a
#     Compose mediante --env-file, sin sobrescribir el .env del repositorio.
#   - Si una decisión es ambigua o peligrosa, se detiene y pregunta.
#
# IMPORTANTE:
#   Este script NO ejecuta `docker compose down -v`.
#   Una nueva instancia NO reutiliza los datos de una instancia anterior.
# ============================================================================== 
 
set +e
trap 'rc=$?; set -e; echo "❌ Error en la línea $LINENO. Código: $rc"; exit "$rc"' ERR
set -e
 
SUDO=""
if [ "${EUID:-0}" -ne 0 ]; then SUDO="sudo"; fi
 
command_exists() { command -v "$1" >/dev/null 2>&1; }
 
sanitize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g; s/^-*//; s/-*$//'
}
 
sql_escape() {
    printf '%s' "$1" | sed "s/'/''/g"
}
 
prompt_yes_no() {
    local prompt="$1" default="${2:-N}" answer
    read -r -p "$prompt" answer
    answer=${answer:-$default}
    [[ "$answer" =~ ^[SsYy]$ ]]
}
 
# ------------------------------------------------------------------------------
# 0. Docker y herramientas base
# ------------------------------------------------------------------------------
echo "================================================="
echo "🐳 0. Verificando Docker, Compose y herramientas..."
echo "================================================="
 
if ! command_exists docker; then
    echo "⚙️ Docker no está instalado. Instalando Docker..."
    $SUDO apt-get update -y
    $SUDO apt-get install -y ca-certificates curl gnupg git unzip iproute2 python3 sudo
    $SUDO install -m 0755 -d /etc/apt/keyrings
 
    . /etc/os-release
    case "${ID:-}" in
        debian)
            DOCKER_REPO="https://download.docker.com/linux/debian"
            ;;
        ubuntu)
            DOCKER_REPO="https://download.docker.com/linux/ubuntu"
            ;;
        *)
            echo "❌ Sistema no soportado automáticamente para instalar Docker: ${ID:-desconocido}"
            echo "   Instala Docker/Compose y vuelve a ejecutar el script."
            exit 1
            ;;
    esac
 
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "$DOCKER_REPO/gpg" | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $DOCKER_REPO ${VERSION_CODENAME} stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null
    $SUDO apt-get update -y
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    $SUDO systemctl enable --now docker
fi
 
for pkg in git unzip iproute2 python3; do
    if ! command_exists "$pkg"; then
        echo "⚙️ Instalando $pkg..."
        $SUDO apt-get update -y >/dev/null
        $SUDO apt-get install -y "$pkg"
    fi
done
 
if ! docker compose version >/dev/null 2>&1; then
    echo "❌ Docker Compose v2 no está disponible."
    exit 1
fi
 
if ! docker info >/dev/null 2>&1; then
    echo "⚡ Iniciando Docker..."
    $SUDO systemctl enable --now docker 2>/dev/null || $SUDO service docker start
fi
 
echo "✅ Docker: $(docker --version)"
echo "✅ Compose: $(docker compose version --short 2>/dev/null || docker compose version)"
 
# ------------------------------------------------------------------------------
# 0.1 Usuario administrativo
# ------------------------------------------------------------------------------
echo "================================================="
echo "👤 0.1 Configuración del usuario administrativo"
echo "================================================="
 
SUDO_USER_NAME="${1:-}"
if [ -z "$SUDO_USER_NAME" ]; then
    read -r -p "👉 Nombre del usuario sudo a crear/usar: " SUDO_USER_NAME
fi
[ -n "$SUDO_USER_NAME" ] || { echo "❌ Usuario vacío."; exit 1; }
 
if ! id "$SUDO_USER_NAME" >/dev/null 2>&1; then
    while :; do
        read -r -s -p "👉 Contraseña para '$SUDO_USER_NAME' (obligatoria): " SUDO_USER_PASS
        echo ""
        [ -n "$SUDO_USER_PASS" ] || { echo "❌ La contraseña del usuario sudo es obligatoria."; continue; }
        read -r -s -p "👉 Confirmar contraseña: " SUDO_USER_PASS_CONFIRM
        echo ""
        [ "$SUDO_USER_PASS" = "$SUDO_USER_PASS_CONFIRM" ] && break
        echo "❌ Las contraseñas no coinciden."
    done
    $SUDO useradd -m -s /bin/bash "$SUDO_USER_NAME"
    $SUDO usermod -aG sudo "$SUDO_USER_NAME"
    printf '%s:%s\n' "$SUDO_USER_NAME" "$SUDO_USER_PASS" | $SUDO chpasswd
else
    echo "✅ El usuario '$SUDO_USER_NAME' ya existe."
    if ! id -nG "$SUDO_USER_NAME" | grep -qw sudo; then
        $SUDO usermod -aG sudo "$SUDO_USER_NAME"
    fi
    # Un usuario sudo existente también debe tener contraseña.
    if sudo passwd -S "$SUDO_USER_NAME" 2>/dev/null | awk '{print $2}' | grep -q '^L$'; then
        echo "⚠️ La cuenta '$SUDO_USER_NAME' está bloqueada; se solicitará una contraseña nueva."
        while :; do
            read -r -s -p "👉 Nueva contraseña para '$SUDO_USER_NAME' (obligatoria): " SUDO_USER_PASS
            echo ""
            [ -n "$SUDO_USER_PASS" ] || { echo "❌ La contraseña es obligatoria."; continue; }
            read -r -s -p "👉 Confirmar contraseña: " SUDO_USER_PASS_CONFIRM
            echo ""
            [ "$SUDO_USER_PASS" = "$SUDO_USER_PASS_CONFIRM" ] && break
            echo "❌ Las contraseñas no coinciden."
        done
        printf '%s:%s\n' "$SUDO_USER_NAME" "$SUDO_USER_PASS" | $SUDO chpasswd
    fi
fi
 
for U in "${USER:-}" "$SUDO_USER_NAME"; do
    if [ -n "$U" ] && id "$U" >/dev/null 2>&1; then
        id -nG "$U" | grep -qw docker || $SUDO usermod -aG docker "$U" 2>/dev/null || true
    fi
done
 
# ------------------------------------------------------------------------------
# 0.2 Escritorio y repositorio
# ------------------------------------------------------------------------------
USER_HOME=$(getent passwd "$SUDO_USER_NAME" | cut -d: -f6 || true)
USER_HOME=${USER_HOME:-$HOME}
 
if [ -d "$USER_HOME/Desktop" ]; then
    ESCRITORIO="$USER_HOME/Desktop"
elif [ -d "$USER_HOME/Escritorio" ]; then
    ESCRITORIO="$USER_HOME/Escritorio"
else
    ESCRITORIO="$USER_HOME/Desktop"
    $SUDO mkdir -p "$ESCRITORIO"
    $SUDO chown "$SUDO_USER_NAME:$SUDO_USER_NAME" "$ESCRITORIO" 2>/dev/null || true
fi
 
read -r -p "👉 URL del repositorio Git: " REPO_URL
[ -n "$REPO_URL" ] || { echo "❌ Debes indicar una URL Git."; exit 1; }
 
# --------------------------------------------------------------------------
# Público / privado + credenciales (nunca se imprimen, nunca se guardan
# dentro del proyecto ni en el repo clonado). Se usan solo durante el clone
# mediante GIT_ASKPASS, y se destruyen inmediatamente después.
# --------------------------------------------------------------------------
REPO_VISIBILITY=""
REPO_AUTH_USER=""
REPO_AUTH_TOKEN=""
REPO_AUTH_REQUIRED=0
 
while [ "$REPO_VISIBILITY" != "1" ] && [ "$REPO_VISIBILITY" != "2" ]; do
    read -r -p "👉 ¿Repositorio público o privado? [1=Público / 2=Privado]: " REPO_VISIBILITY
done
 
if [ "$REPO_VISIBILITY" = "2" ]; then
    REPO_AUTH_REQUIRED=1
    read -r -p "👉 Usuario de acceso: " REPO_AUTH_USER
    read -r -s -p "👉 Token/contraseña de acceso: " REPO_AUTH_TOKEN
    echo ""
    [ -n "$REPO_AUTH_TOKEN" ] || { echo "❌ Debes indicar un token/contraseña para un repositorio privado."; exit 1; }
fi
 
clone_repository_remote() {
    # $1 = URL, $2 = destino. Siempre crea una instancia NUEVA: nunca reutiliza
    # ni actualiza (pull/reset/checkout) una copia local existente.
    local url="$1" dest="$2" askpass_file="" rc=0
 
    if [ "$REPO_AUTH_REQUIRED" -eq 1 ]; then
        askpass_file=$(mktemp)
        chmod 700 "$askpass_file"
        {
            echo '#!/bin/sh'
            echo 'case "$1" in'
            echo '  *sername*) printf "%s" "$GIT_ASKPASS_USER" ;;'
            echo '  *) printf "%s" "$GIT_ASKPASS_TOKEN" ;;'
            echo 'esac'
        } > "$askpass_file"
        chmod 700 "$askpass_file"
 
        set +e
        GIT_ASKPASS="$askpass_file" GIT_ASKPASS_USER="$REPO_AUTH_USER" GIT_ASKPASS_TOKEN="$REPO_AUTH_TOKEN" \
            GIT_TERMINAL_PROMPT=0 git clone "$url" "$dest"
        rc=$?
        set -e
 
        # El archivo temporal de credenciales se borra siempre, en cada
        # intento. El token en memoria (REPO_AUTH_TOKEN) NO se borra aquí:
        # si el clone falla y el usuario elige "Reintentar", el reintento
        # necesita seguir teniendo el token disponible. Se borra una única
        # vez, después de un clone exitoso (ver bucle de llamada más abajo).
        rm -f "$askpass_file"
    else
        set +e
        GIT_TERMINAL_PROMPT=0 git clone "$url" "$dest"
        rc=$?
        set -e
    fi
 
    return "$rc"
}
 
REPO_BASENAME=$(basename "${REPO_URL%/}")
REPO_BASENAME=${REPO_BASENAME%.git}
DEFAULT_SYSTEM_NAME=$(sanitize_name "$REPO_BASENAME")
DEFAULT_SYSTEM_NAME=${DEFAULT_SYSTEM_NAME:-sistema}
 
read -r -p "👉 Nombre del sistema [$DEFAULT_SYSTEM_NAME]: " SYSTEM_NAME
SYSTEM_NAME=${SYSTEM_NAME:-$DEFAULT_SYSTEM_NAME}
SYSTEM_NAME=$(sanitize_name "$SYSTEM_NAME")
[ -n "$SYSTEM_NAME" ] || { echo "❌ Nombre de sistema inválido."; exit 1; }
 
REPO_DIR="$ESCRITORIO/$SYSTEM_NAME"
 
# Cada despliegue exige una descarga NUEVA. Si ya existe una carpeta con ese
# nombre (de una ejecución anterior), nunca se reutiliza como origen: se pide
# borrarla, renombrar el sistema o cancelar.
if [ -e "$REPO_DIR" ]; then
    echo "⚠️ Ya existe '$REPO_DIR' de un despliegue anterior."
    echo "   El repositorio remoto debe descargarse siempre de nuevo; no se reutiliza código local."
    read -r -p "👉 ¿Eliminar esa copia y volver a descargar? [s/N]: " RESP_REPO_EXISTS
    case "${RESP_REPO_EXISTS,,}" in
        s|si|sí|y|yes)
            REPO_DIR_REAL=$(realpath -m "$REPO_DIR")
            ESCRITORIO_REAL=$(realpath -m "$ESCRITORIO")
            if [ "$REPO_DIR_REAL" = "/" ] || [ "$REPO_DIR_REAL" = "$USER_HOME" ] || \
               [ "$REPO_DIR_REAL" = "$ESCRITORIO_REAL" ] || [ "${REPO_DIR_REAL#$ESCRITORIO_REAL/}" = "$REPO_DIR_REAL" ]; then
                echo "❌ Ruta insegura para eliminar, abortando: $REPO_DIR_REAL"
                exit 1
            fi
            rm -rf "$REPO_DIR_REAL"
            ;;
        *)
            echo "❌ Cancelado. Elige otro nombre de sistema o elimina manualmente '$REPO_DIR'."
            exit 1
            ;;
    esac
fi
 
# ------------------------------------------------------------------------------
# 0.3 Descargar/clonar repositorio sin destruir una copia existente
# ------------------------------------------------------------------------------
echo "================================================="
echo "📥 0.3 Obteniendo repositorio"
echo "================================================="
 
extract_repository_zip() {
    local zip_file="$1" dest="$2" extract_dir top_dir depth rc
 
    # Validación mínima: que el archivo descargado exista y no esté vacío
    # antes de intentar descomprimir (evita fallos confusos de unzip).
    if [ ! -s "$zip_file" ]; then
        echo "❌ El archivo ZIP descargado está vacío o no existe: $zip_file"
        exit 1
    fi
 
    extract_dir=$(mktemp -d)
 
    echo "📦 Extrayendo repositorio ZIP..."
 
    # CORRECCIÓN CRÍTICA: unzip devuelve código 1 para simples ADVERTENCIAS
    # (bytes extra al inicio del zip, CRC no crítico, etc.), no solo para
    # errores fatales (código >=2). Como el script es "universal" y debe
    # aceptar zips generados por cualquier plataforma (GitHub, GitLab,
    # Bitbucket, paneles de exportación propios, etc.), tratar el código 1
    # como fallo total descartaba extracciones que en realidad SÍ habían
    # funcionado. Ahora solo se considera error fatal un código >=2, o que
    # el directorio de extracción quede vacío.
    set +e
    unzip -q -o "$zip_file" -d "$extract_dir"
    rc=$?
    set -e
 
    if [ "$rc" -ge 2 ] || [ -z "$(find "$extract_dir" -mindepth 1 -print -quit 2>/dev/null)" ]; then
        rm -rf "$extract_dir"
        echo "❌ No se pudo extraer el ZIP del repositorio (código de salida de unzip: $rc)."
        exit 1
    elif [ "$rc" -eq 1 ]; then
        echo "⚠️ unzip reportó advertencias no fatales (código 1) al extraer; se continúa porque el contenido sí se extrajo."
    fi
 
    # Eliminar basura típica de zips generados en macOS que rompe la
    # detección de "carpeta envolvente única" más abajo.
    find "$extract_dir" -maxdepth 2 -type d -name '__MACOSX' -exec rm -rf {} + 2>/dev/null || true
    find "$extract_dir" -maxdepth 2 -type f -name '.DS_Store' -delete 2>/dev/null || true
 
    # CORRECCIÓN: navegar recursivamente mientras el nivel actual sea
    # exactamente UNA carpeta envolvente sin archivos sueltos. Esto evita el
    # error de "el sistema quedó dentro de una carpeta" cuando el ZIP anida
    # el proyecto en dos o más niveles (p. ej. export/export/sistema-real/...).
    top_dir="$extract_dir"
    for depth in 1 2 3 4 5; do
        if [ "$(find "$top_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "1" ] && \
           [ "$(find "$top_dir" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" = "0" ]; then
            top_dir=$(find "$top_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)
            echo "   ↳ Carpeta envolvente detectada, navegando dentro: $(basename "$top_dir")"
        else
            break
        fi
    done
 
    if [ -z "$(find "$top_dir" -mindepth 1 -print -quit 2>/dev/null)" ]; then
        rm -rf "$extract_dir"
        echo "❌ El ZIP se extrajo pero no contiene archivos utilizables."
        exit 1
    fi
 
    # Normalizar permisos aditivamente ANTES de copiar al destino final: los
    # ZIP preservan el modo original de cada entrada, que puede venir
    # restrictivo (000, sin +x en directorios) según la herramienta que
    # generó el ZIP. Sin esto, el contenedor web puede levantar "sano" pero
    # Apache/Nginx responde 403 Forbidden al no poder leer/atravesar los
    # archivos, incluso después de un chown correcto en el Dockerfile.
    find "$top_dir" -type d -exec chmod u+rwx,go+rx {} \; 2>/dev/null || true
    find "$top_dir" -type f -exec chmod u+rw,go+r {} \; 2>/dev/null || true
 
    mkdir -p "$dest"
    tar -C "$top_dir" -cf - . | tar -C "$dest" -xf -
    rm -rf "$extract_dir"
 
    if [ -z "$(find "$dest" -mindepth 1 -print -quit 2>/dev/null)" ]; then
        echo "❌ La copia final del repositorio quedó vacía en '$dest'."
        exit 1
    fi
    echo "✅ ZIP descomprimido correctamente en: $dest"
}
 
REPO_URL_NO_QUERY="${REPO_URL%%\?*}"
 
# CORRECCIÓN: para que el script sea realmente "universal" no basta con mirar
# si la URL termina en ".zip" — muchos paneles/plataformas sirven ZIPs desde
# URLs sin esa extensión (p. ej. endpoints de exportación, enlaces firmados de
# S3, "/download?format=zip", etc.). Además de la extensión, se comprueban las
# cabeceras HTTP (Content-Type / Content-Disposition) y, como última
# comprobación, la firma binaria real del archivo ya descargado ("PK").
IS_ZIP_URL=0
case "${REPO_URL_NO_QUERY,,}" in
    *.zip) IS_ZIP_URL=1 ;;
esac
 
if [ "$IS_ZIP_URL" -eq 0 ]; then
    HEADERS=$(curl -fsIL --retry 2 --connect-timeout 10 "$REPO_URL" 2>/dev/null || true)
    if printf '%s' "$HEADERS" | tr -d '\r' | grep -qiE '^(content-type: .*zip|content-disposition: .*\.zip)'; then
        IS_ZIP_URL=1
    fi
fi
 
case "$IS_ZIP_URL" in
    1)
        ZIP_TMP=$(mktemp --suffix=.zip)
        echo "⬇️ Descargando ZIP: $REPO_URL"
        if ! curl -fL --retry 3 --connect-timeout 20 "$REPO_URL" -o "$ZIP_TMP"; then
            rm -f "$ZIP_TMP"
            echo "❌ No se pudo descargar el ZIP del repositorio."
            exit 1
        fi
        # Última verificación por firma binaria: un ZIP real empieza con "PK".
        # Si esto no coincide (p. ej. la URL devolvió una página HTML de error
        # o de login), se avisa claramente en vez de intentar descomprimir basura.
        if [ "$(head -c 2 "$ZIP_TMP" 2>/dev/null)" != "PK" ]; then
            echo "❌ El archivo descargado no es un ZIP válido (no empieza con la firma 'PK')."
            echo "   Verifica que la URL sea un enlace directo de descarga (no una página HTML)."
            rm -f "$ZIP_TMP"
            exit 1
        fi
        if [ -e "$REPO_DIR" ]; then
            echo "❌ Ya existe '$REPO_DIR'. Para un repositorio ZIP no se sobrescribirá una copia existente."
            rm -f "$ZIP_TMP"
            exit 1
        fi
        mkdir -p "$REPO_DIR"
        extract_repository_zip "$ZIP_TMP" "$REPO_DIR"
        rm -f "$ZIP_TMP"
        ;;
    *)
        # SIEMPRE una descarga nueva desde el remoto. Nunca se actualiza
        # (pull/reset/checkout) una copia local existente ni se usa una
        # instancia P# anterior como origen.
        CLONE_ATTEMPT_OK=0
        while [ "$CLONE_ATTEMPT_OK" -eq 0 ]; do
            if clone_repository_remote "$REPO_URL" "$REPO_DIR"; then
                CLONE_ATTEMPT_OK=1
                # Clone exitoso: ya no se necesita el token en memoria.
                unset REPO_AUTH_TOKEN
                REPO_AUTH_TOKEN=""
            else
                echo "❌ Falló la descarga del repositorio."
                echo "   URL: $REPO_URL"
                echo "   Destino: $REPO_DIR"
                echo "1) Reintentar"
                echo "2) Eliminar los archivos descargados"
                echo "3) Conservarlos para diagnóstico y salir"
                echo "4) Cancelar"
                read -r -p "👉 Opción: " CLONE_FAIL_OPT
                case "$CLONE_FAIL_OPT" in
                    1)
                        [ -n "$REPO_DIR" ] && [ "$REPO_DIR" != "/" ] && [ -e "$REPO_DIR" ] && rm -rf "$REPO_DIR"
                        ;;
                    2)
                        [ -n "$REPO_DIR" ] && [ "$REPO_DIR" != "/" ] && rm -rf "$REPO_DIR"
                        exit 1
                        ;;
                    3) exit 1 ;;
                    *) exit 1 ;;
                esac
            fi
        done
        ;;
esac
 
$SUDO chown -R "$SUDO_USER_NAME:$SUDO_USER_NAME" "$REPO_DIR" 2>/dev/null || true
 
# Ruta INMUTABLE del repositorio original. Nunca debe confundirse con Pn/source.
ORIGINAL_REPO_DIR="$REPO_DIR"
REPO_DIR_ORIGINAL="$ORIGINAL_REPO_DIR"
 
echo "✅ Código fuente: $REPO_DIR"
 
# ------------------------------------------------------------------------------
# 1. Detectar y entender la configuración Docker existente
# ------------------------------------------------------------------------------
COMPOSE_FILE=""
COMPOSE_FILES=()
# Prioridad de archivo base igual a la de Docker Compose nativo.
for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
    if [ -f "$REPO_DIR/$f" ]; then
        COMPOSE_FILE="$REPO_DIR/$f"
        COMPOSE_FILES+=("$COMPOSE_FILE")
        break
    fi
done
 
# Si existe, se añade automáticamente el override correspondiente: es el
# mismo comportamiento por defecto de `docker compose` (no es una decisión
# arbitraria del script, sino la semántica estándar de Compose).
if [ -n "$COMPOSE_FILE" ]; then
    for ov in compose.override.yaml compose.override.yml docker-compose.override.yaml docker-compose.override.yml; do
        if [ -f "$REPO_DIR/$ov" ]; then
            COMPOSE_FILES+=("$REPO_DIR/$ov")
            break
        fi
    done
fi
 
# Construye los argumentos -f repetidos para todas las llamadas a
# `docker compose`. Se recalcula más abajo una vez resuelto el Compose de
# instancia (INSTANCE_COMPOSE_FILE); ver bloque de instancia.
build_compose_f_args() {
    COMPOSE_F_ARGS=()
    local f
    for f in "${COMPOSE_FILES[@]}"; do
        COMPOSE_F_ARGS+=(-f "$f")
    done
}
build_compose_f_args
 
cd "$REPO_DIR"
 
# ------------------------------------------------------------------------------
# Resolver TODOS los build.context + build.dockerfile declarados por Compose.
# IMPORTANTE: esta función debe ejecutarse ANTES de consultar BUILD_TARGETS.
# ------------------------------------------------------------------------------
BUILD_TARGETS=""
resolve_compose_build_targets() {
    [ -n "$COMPOSE_FILE" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    local json_file="$REPO_DIR/.compose-resolved.json"
    if ! docker compose "${COMPOSE_F_ARGS[@]}" --project-directory "$REPO_DIR" config --format json > "$json_file" 2>/dev/null; then
        rm -f "$json_file"
        return 0
    fi
    BUILD_TARGETS=$(python3 - "$json_file" "$REPO_DIR" <<'PYJSON'
import json, os, sys
f, root = sys.argv[1:]
data=json.load(open(f, encoding='utf-8'))
for svc, spec in (data.get('services') or {}).items():
    b=spec.get('build')
    if not b: continue
    if isinstance(b, str):
        ctx=b; df='Dockerfile'
    else:
        ctx=b.get('context') or '.'
        df=b.get('dockerfile') or 'Dockerfile'
    ctx_abs=os.path.normpath(ctx if os.path.isabs(ctx) else os.path.join(root, ctx))
    df_abs=os.path.normpath(df if os.path.isabs(df) else os.path.join(ctx_abs, df))
    print(f"{svc}\t{ctx_abs}\t{df}\t{df_abs}")
PYJSON
)
    rm -f "$json_file"
}
resolve_compose_build_targets
 
# ------------------------------------------------------------------------------
# Resolver image: de cada servicio desde Compose.
# ------------------------------------------------------------------------------
 
resolve_compose_service_images() {
    [ -n "$COMPOSE_FILE" ] || return 0
 
    local json_file="$REPO_DIR/.compose-services.json"
 
    if ! docker compose \
        "${COMPOSE_F_ARGS[@]}" \
        --project-directory "$REPO_DIR" \
        config --format json > "$json_file" 2>/dev/null
    then
        rm -f "$json_file"
        echo "⚠️ No se pudo resolver Compose en formato JSON."
        return 0
    fi
 
    while IFS=$'\t' read -r svc image; do
        [ -n "$svc" ] || continue
        SERVICE_IMAGE["$svc"]="$image"
    done < <(
        python3 - "$json_file" <<'PY'
import json
import sys
 
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
 
for service, config in (data.get("services") or {}).items():
    print(f"{service}\t{config.get('image') or ''}")
PY
    )
 
    rm -f "$json_file"
}
 
resolve_compose_service_images
# ------------------------------------------------------------------------------
# MODELO UNIVERSAL DE BUILDS POR SERVICIO
# ------------------------------------------------------------------------------
 
declare -A SERVICE_HAS_BUILD
declare -A SERVICE_BUILD_CONTEXT
declare -A SERVICE_DOCKERFILE
declare -A SERVICE_IMAGE
 
DOCKERFILE_PATH=""
 
if [ -n "$BUILD_TARGETS" ]; then
    while IFS=$'\t' read -r svc ctx df eff; do
        [ -n "$svc" ] || continue
 
        SERVICE_HAS_BUILD["$svc"]="1"
        SERVICE_BUILD_CONTEXT["$svc"]="$ctx"
        SERVICE_DOCKERFILE["$svc"]="$eff"
 
        # Compatibilidad con código antiguo.
        # NO se utilizará para decidir el Dockerfile de cada servicio.
        if [ -z "$DOCKERFILE_PATH" ] && [ -f "$eff" ]; then
            DOCKERFILE_PATH="$eff"
        fi
    done <<< "$BUILD_TARGETS"
fi
 
echo "================================================="
echo "🔎 1. Analizando proyecto y configuración Docker"
echo "================================================="
 
if [ -n "$COMPOSE_FILE" ]; then
    echo "✅ Compose existente: $(basename "$COMPOSE_FILE")"
else
    echo "⚠️ No existe Compose en el repositorio."
fi
if [ -n "$DOCKERFILE_PATH" ]; then
    echo "✅ Dockerfile existente: ${DOCKERFILE_PATH#$REPO_DIR/}"
else
    echo "⚠️ No existe Dockerfile en el repositorio."
fi
 
# Analizar el Dockerfile existente sin modificarlo.
if [ -n "$DOCKERFILE_PATH" ]; then
    echo "🔍 Directivas Docker detectadas:"
    grep -E '^[[:space:]]*(FROM|ARG|ENV|WORKDIR|COPY|ADD|RUN|EXPOSE|USER|CMD|ENTRYPOINT)[[:space:]]' "$DOCKERFILE_PATH" \
        | sed 's/^/   • /' || true
fi
 
# Detectores básicos de tecnología para poder generar Docker cuando falte.
detect_project_type() {
    if [ -f package.json ]; then echo node; return; fi
    if [ -f composer.json ] || find . -maxdepth 2 -type f -name '*.php' -print -quit | grep -q .; then echo php; return; fi
    if [ -f manage.py ] || [ -f requirements.txt ] || [ -f pyproject.toml ]; then echo python; return; fi
    if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then echo java; return; fi
    if find . -maxdepth 2 -type f -name 'index.html' -print -quit | grep -q .; then echo static; return; fi
    echo unknown
}
GENERATED_DOCKERFILES=""
GENERATED_PHP_WEB_MODE=""
DOCKERFILE_WAS_GENERATED="0"
 
PROJECT_TYPE=$(detect_project_type)
echo "🧩 Tecnología detectada: $PROJECT_TYPE"
 
 
# Detectar tecnología de un servicio concreto cuando Compose tiene múltiples builds.
# La prioridad es: archivos del contexto -> nombre del servicio/contexto -> raíz del proyecto.
detect_service_type() {
    local svc="$1" ctx="$2" lower
    lower=$(printf '%s' "$svc $ctx" | tr '[:upper:]' '[:lower:]')
    if [ -d "$ctx" ]; then
        if [ -f "$ctx/composer.json" ] || find "$ctx" -maxdepth 2 -type f -name '*.php' -print -quit | grep -q .; then echo php; return; fi
        if [ -f "$ctx/package.json" ]; then echo node; return; fi
        if [ -f "$ctx/manage.py" ] || [ -f "$ctx/requirements.txt" ] || [ -f "$ctx/pyproject.toml" ]; then echo python; return; fi
        if [ -f "$ctx/pom.xml" ] || [ -f "$ctx/build.gradle" ] || [ -f "$ctx/build.gradle.kts" ]; then echo java; return; fi
        if find "$ctx" -maxdepth 2 -type f -name 'nginx.conf' -print -quit | grep -q .; then echo nginx; return; fi
        if find "$ctx" -maxdepth 2 -type f \( -name 'httpd.conf' -o -name 'apache2.conf' \) -print -quit | grep -q .; then echo apache; return; fi
    fi
    case "$lower" in
        *nginx*|*openresty*) echo nginx; return ;;
        *apache*|*httpd*) echo apache; return ;;
        *php*|*fpm*) echo php; return ;;
        *node*|*npm*) echo node; return ;;
        *python*|*django*|*flask*|*fastapi*) echo python; return ;;
        *java*|*spring*) echo java; return ;;
    esac
    echo "$PROJECT_TYPE"
}
 
# Determinar el servidor web cuando hay que GENERAR Docker y no existe Compose.
# Si la evidencia es contradictoria, no inventamos una arquitectura.
detect_local_web_stack() {
    local root="$1" n=0 a=0
    if find "$root" -maxdepth 4 -type f \
        \( -iname 'nginx.conf' -o -iname '*nginx*.conf' -o -iname 'openresty.conf' \) \
        -print -quit 2>/dev/null | grep -q .; then n=1; fi
    if find "$root" -maxdepth 4 -type f \
        \( -iname 'httpd.conf' -o -iname 'apache2.conf' -o -iname '*apache*.conf' \) \
        -print -quit 2>/dev/null | grep -q .; then a=1; fi
    if [ "$n" -eq 1 ] && [ "$a" -eq 1 ]; then echo nginx+apache;
    elif [ "$n" -eq 1 ]; then echo nginx;
    elif [ "$a" -eq 1 ]; then echo apache;
    else echo unknown; fi
}
 
# Añadir permisos SOLO para directorios que existen en el contexto real.
# La comprobación [ -d ] también protege el build si .dockerignore excluye alguno.
append_php_runtime_permissions() {
    local ctx="$1" target="$2" candidate paths=""
    for candidate in storage bootstrap/cache var runtime writable api/events; do
        if [ -d "$ctx/$candidate" ]; then
            paths="$paths /var/www/html/$candidate"
        fi
    done
    if [ -n "$paths" ]; then
        cat >> "$target" <<EOF
RUN set -eux; for d in $paths; do if [ -d "\$d" ]; then chown -R www-data:www-data "\$d"; chmod -R 775 "\$d"; fi; done
EOF
    fi
}
 
# Detectar un puerto ya declarado por el proyecto antes de inventar uno.
detect_app_port() {
    local p=""
    if [ -f package.json ]; then
        p=$(grep -RhoE 'PORT[[:space:]]*[=:][[:space:]]*[0-9]{2,5}' . --exclude-dir=.git --exclude-dir=node_modules 2>/dev/null | head -n1 | grep -oE '[0-9]{2,5}' || true)
    fi
    if [ -z "$p" ] && [ -f .env ]; then
        p=$(grep -E '^[[:space:]]*(PORT|APP_PORT)[[:space:]]*=' .env | head -n1 | grep -oE '[0-9]{2,5}' | head -n1 || true)
    fi
    echo "${p:-}"
}
APP_PORT_DETECTED=$(detect_app_port)
 
# Genera solamente el Dockerfile que falte. El Compose se genera más adelante,
# después de copiar la instancia, para que sus rutas sean las definitivas.
generate_dockerfile_if_missing() {
    [ -n "$DOCKERFILE_PATH" ] && return 0
 
    # Si Compose ya existe, NO generamos un Dockerfile genérico en la raíz.
    # Los Dockerfiles requeridos por cada servicio se resuelven después, respetando
    # exactamente build.context + build.dockerfile. Si Compose solo usa imágenes,
    # tampoco hace falta inventar un Dockerfile.
    if [ -n "$COMPOSE_FILE" ]; then
        echo "ℹ️ Compose existente: la generación de Dockerfiles se hará por servicio solo si algún build los requiere."
        return 0
    fi
 
    echo "🛠️ No existe Dockerfile ni Compose. Se generará un Dockerfile a partir de la estructura detectada."
    case "$PROJECT_TYPE" in
        node)
            if ! python3 - "$REPO_DIR/package.json" <<'PYNODE'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
scripts=p.get('scripts') or {}
if 'start' not in scripts:
    raise SystemExit(1)
PYNODE
            then
                echo "❌ Node detectado, pero package.json no define scripts.start."
                echo "   No se generará un CMD arbitrario que pueda dejar el contenedor en bucle de reinicio."
                exit 1
            fi
            cat > "$REPO_DIR/Dockerfile.generated" <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN if [ -f package-lock.json ]; then npm ci; elif [ -f package.json ]; then npm install; else echo 'No se encontró package.json'; exit 1; fi
ENV NODE_ENV=production
EXPOSE 3000
CMD ["npm", "start"]
EOF
            DOCKERFILE_PATH="$REPO_DIR/Dockerfile.generated"
            DOCKERFILE_WAS_GENERATED="1"
            GENERATED_DOCKERFILES="${GENERATED_DOCKERFILES}${DOCKERFILE_PATH}"$'\n'
            ;;
        php)
            # PHP generado de forma conservadora: nunca se asumen rutas de
            # Laravel/Symfony/u otro framework que no existan en el proyecto.
            php_web_mode=""
            if [ -n "$COMPOSE_FILE" ]; then
                if grep -Eqi 'nginx|openresty|php-fpm|fpm' "${COMPOSE_FILES[@]}" 2>/dev/null; then php_web_mode="fpm";
                elif grep -Eqi 'apache|httpd' "${COMPOSE_FILES[@]}" 2>/dev/null; then php_web_mode="apache"; fi
            else
                local_web_stack=$(detect_local_web_stack "$REPO_DIR")
                case "$local_web_stack" in
                    nginx) php_web_mode="fpm" ;;
                    apache) php_web_mode="apache" ;;
                    nginx+apache)
                        echo "⚠️ Se detectaron Nginx y Apache en el proyecto sin Compose."
                        read -r -p "👉 Arquitectura PHP [1=Apache, 2=Nginx+PHP-FPM]: " web_choice
                        case "${web_choice:-}" in 1) php_web_mode="apache" ;; 2) php_web_mode="fpm" ;; *) echo "❌ Selección inválida."; exit 1 ;; esac
                        ;;
                    *)
                        echo "⚠️ PHP detectado, pero no se encontró configuración web suficiente."
                        read -r -p "👉 Servidor web [1=Apache, 2=Nginx+PHP-FPM]: " web_choice
                        case "${web_choice:-}" in 1) php_web_mode="apache" ;; 2) php_web_mode="fpm" ;; *) echo "❌ Selección inválida."; exit 1 ;; esac
                        ;;
                esac
            fi
            if [ "$php_web_mode" = "fpm" ]; then
                cat > "$REPO_DIR/Dockerfile.generated" <<'EOF'
FROM php:8.2-fpm
WORKDIR /var/www/html
COPY . /var/www/html/
RUN if [ -f /var/www/html/composer.json ]; then \
      apt-get update && apt-get install -y --no-install-recommends git unzip libzip-dev && \
      docker-php-ext-install zip && \
      rm -rf /var/lib/apt/lists/* && \
      php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
      php composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
      rm composer-setup.php && \
      composer install --no-interaction --prefer-dist --no-dev; \
    fi
EXPOSE 9000
CMD ["php-fpm"]
EOF
            else
                cat > "$REPO_DIR/Dockerfile.generated" <<'EOF'
FROM php:8.2-apache
WORKDIR /var/www/html
COPY . /var/www/html/
RUN if [ -f /var/www/html/composer.json ]; then \
      apt-get update && apt-get install -y --no-install-recommends git unzip libzip-dev && \
      docker-php-ext-install zip && \
      rm -rf /var/lib/apt/lists/* && \
      php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
      php composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
      rm composer-setup.php && \
      composer install --no-interaction --prefer-dist --no-dev; \
    fi
EXPOSE 80
CMD ["apache2-foreground"]
EOF
            fi
            append_php_runtime_permissions "$REPO_DIR" "$REPO_DIR/Dockerfile.generated"
            GENERATED_PHP_WEB_MODE="$php_web_mode"
            DOCKERFILE_PATH="$REPO_DIR/Dockerfile.generated"
            DOCKERFILE_WAS_GENERATED="1"
            GENERATED_DOCKERFILES="${GENERATED_DOCKERFILES}${DOCKERFILE_PATH}"$'\n'
            ;;
        python)
            if [ ! -f "$REPO_DIR/app.py" ] && [ ! -f "$REPO_DIR/manage.py" ] && [ ! -f "$REPO_DIR/main.py" ]; then
                echo "❌ Python detectado, pero no se encontró un punto de entrada seguro (app.py, manage.py o main.py)."
                exit 1
            fi
            if [ -f "$REPO_DIR/manage.py" ]; then
                python_cmd='python manage.py runserver 0.0.0.0:8000'
            elif [ -f "$REPO_DIR/main.py" ]; then
                python_cmd='python main.py'
            else
                python_cmd='python app.py'
            fi
            cat > "$REPO_DIR/Dockerfile.generated" <<EOF
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi
EXPOSE 8000
CMD ["sh", "-c", "$python_cmd"]
EOF
            DOCKERFILE_PATH="$REPO_DIR/Dockerfile.generated"
            DOCKERFILE_WAS_GENERATED="1"
            GENERATED_DOCKERFILES="${GENERATED_DOCKERFILES}${DOCKERFILE_PATH}"$'\n'
            ;;
        static)
            cat > "$REPO_DIR/Dockerfile.generated" <<'EOF'
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
EOF
            DOCKERFILE_PATH="$REPO_DIR/Dockerfile.generated"
            DOCKERFILE_WAS_GENERATED="1"
            GENERATED_DOCKERFILES="${GENERATED_DOCKERFILES}${DOCKERFILE_PATH}"$'\n'
            ;;
        *)
            echo "❌ No se pudo determinar de forma segura cómo construir el proyecto."
            echo "   Añade un Dockerfile al repositorio o configura Docker manualmente."
            exit 1
            ;;
    esac
    echo "✅ Dockerfile generado: ${DOCKERFILE_PATH#$REPO_DIR/}"
}
 
generate_dockerfile_if_missing
 
# Genera solamente los archivos Docker que realmente faltan. Los existentes se respetan.
# Dockerfile generation is performed before the instance is copied.
 
# ------------------------------------------------------------------------------
# 2. Seleccionar instancia Pn sin tocar las anteriores
# ------------------------------------------------------------------------------
CONTADOR=1
while :; do
    CARPETA_DESTINO="$ESCRITORIO/P${CONTADOR}"
    PROJECT_CANDIDATE="p${CONTADOR}"
    if [ ! -e "$CARPETA_DESTINO" ] && \
       ! docker ps -a --format '{{.Names}}' | grep -q "^${PROJECT_CANDIDATE}_" && \
       ! docker network ls --format '{{.Name}}' | grep -q "^${PROJECT_CANDIDATE}_"; then
        break
    fi
    CONTADOR=$((CONTADOR + 1))
done
 
NOMBRE_CARPETA="P${CONTADOR}"
COMPOSE_PROJECT_NAME="$PROJECT_CANDIDATE"
mkdir -p "$CARPETA_DESTINO"
 
INSTANCE_SOURCE="$CARPETA_DESTINO/source"
INSTANCE_ENV="$CARPETA_DESTINO/.env"
MANIFEST="$CARPETA_DESTINO/deployment.env"
 
if [ -f "$REPO_DIR/.env" ]; then
    cp "$REPO_DIR/.env" "$INSTANCE_ENV"
else
    : > "$INSTANCE_ENV"
fi
printf '\nCOMPOSE_PROJECT_NAME=%s\nPREFIX_CONTENEDOR=%s\nPROJECT_NAME=%s\nPROJECT_SOURCE=%s\n' \
    "$COMPOSE_PROJECT_NAME" "$COMPOSE_PROJECT_NAME" "$SYSTEM_NAME" "$CARPETA_DESTINO/source" >> "$INSTANCE_ENV"
 
mkdir -p "$INSTANCE_SOURCE"
tar -C "$REPO_DIR" --exclude='./.git' -cf - . | tar -C "$INSTANCE_SOURCE" -xf -
 
# CORRECCIÓN CRÍTICA (permisos "403 Forbidden" en el contenedor web):
# COPY en un Dockerfile preserva LITERALMENTE los permisos que traían los
# archivos en el ZIP o repositorio original. Como este instalador es
# "universal" (acepta cualquier repo/ZIP de cualquier origen), no se puede
# asumir que todos vengan con permisos sanos: algunos paneles de exportación
# o ZIPs generados en otros sistemas guardan modos restrictivos (000, 600 sin
# +x en directorios, etc.). chown en el Dockerfile del proyecto cambia el
# dueño pero NO el modo, así que si Apache/Nginx corre como www-data pero el
# archivo quedó en modo 000, ni el nuevo dueño puede leerlo -> 403 Forbidden
# "You don't have permission to access this resource".
# Se normalizan permisos de forma ADITIVA (nunca se quita nada, solo se
# añade lectura a todos y ejecución/traspaso a directorios), para que
# cualquier imagen construida a partir de esta fuente sea servible sin
# depender de que el Dockerfile de cada proyecto lo corrija por su cuenta.
echo "🔐 Normalizando permisos de la fuente copiada (evita 403 Forbidden por permisos heredados del ZIP/repo)..."
find "$INSTANCE_SOURCE" -type d -exec chmod u+rwx,go+rx {} \; 2>/dev/null || true
find "$INSTANCE_SOURCE" -type f -exec chmod u+rw,go+r {} \; 2>/dev/null || true
 
# Mantener exactamente el/los Compose que venían en el repositorio (base +
# override si existía), pero apuntando a la copia de la instancia. Nunca
# sustituirlos por compose.generated.yml.
INSTANCE_COMPOSE_FILE=""
INSTANCE_COMPOSE_FILES=()
if [ -n "$COMPOSE_FILE" ]; then
    for cf in "${COMPOSE_FILES[@]}"; do
        compose_rel="${cf#$REPO_DIR/}"
        if [ "$compose_rel" = "$cf" ]; then
            echo "❌ El Compose detectado no pertenece al repositorio: $cf"
            exit 1
        fi
        if [ -f "$INSTANCE_SOURCE/$compose_rel" ]; then
            INSTANCE_COMPOSE_FILES+=("$INSTANCE_SOURCE/$compose_rel")
        else
            echo "❌ El Compose detectado no apareció en la copia de la instancia: $compose_rel"
            exit 1
        fi
    done
    INSTANCE_COMPOSE_FILE="${INSTANCE_COMPOSE_FILES[0]}"
fi
 
extract_embedded_zips() {
    local pass zip_file key out_dir found
    declare -A ZIP_DONE=()
 
    for pass in 1 2 3 4 5; do
        found=0
        while IFS= read -r -d '' zip_file; do
            key=$(printf '%s' "$zip_file" | sha256sum | awk '{print $1}')
            [ -n "${ZIP_DONE[$key]:-}" ] && continue
            ZIP_DONE[$key]=1
            found=1
 
            out_dir="$INSTANCE_SOURCE/.zip_extract/$key"
            mkdir -p "$out_dir"
            echo "📦 Extrayendo paquete interno: ${zip_file#$INSTANCE_SOURCE/}"
            if ! unzip -oq "$zip_file" -d "$out_dir"; then
                echo "❌ No se pudo extraer: ${zip_file#$INSTANCE_SOURCE/}"
                return 1
            fi
 
            # CORRECCIÓN: igual que con el ZIP del repositorio, navegar dentro
            # de carpetas envolventes anidadas para que el contenido real
            # (Dockerfile, compose, .sql, etc.) quede accesible y no atrapado
            # dentro de una subcarpeta extra.
            local inner_depth inner_dir="$out_dir"
            for inner_depth in 1 2 3 4 5; do
                if [ "$(find "$inner_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = "1" ] && \
                   [ "$(find "$inner_dir" -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')" = "0" ]; then
                    inner_dir=$(find "$inner_dir" -mindepth 1 -maxdepth 1 -type d -print -quit)
                else
                    break
                fi
            done
            if [ "$inner_dir" != "$out_dir" ]; then
                echo "   ↳ Carpeta envolvente detectada dentro del paquete, aplanando estructura."
                local flat_tmp
                flat_tmp=$(mktemp -d)
                tar -C "$inner_dir" -cf - . | tar -C "$flat_tmp" -xf -
                rm -rf "${out_dir:?}"/*
                tar -C "$flat_tmp" -cf - . | tar -C "$out_dir" -xf -
                rm -rf "$flat_tmp"
            fi
 
            # CORRECCIÓN CRÍTICA: dejar el contenido solo en .zip_extract/<hash>/
            # no sirve de nada si el Dockerfile del proyecto hace "COPY . ..."
            # desde la raíz de la instancia — el código real (index.php, etc.)
            # nunca llega al servidor web, que es exactamente lo que causaba el
            # 403/listado vacío. Se FUSIONA el contenido extraído hacia la raíz
            # de la instancia (sin pisar archivos que el propio repo ya trae,
            # como un Dockerfile o docker-compose.yml legítimos) para que quede
            # donde cualquier Dockerfile ("COPY . /var/www/html/", "COPY . .",
            # etc.) lo vaya a encontrar, sin importar la estructura del proyecto.
            echo "   ↳ Integrando contenido del paquete a la raíz de la instancia..."
            tar -C "$out_dir" -cf - . | tar -C "$INSTANCE_SOURCE" -k -xf - 2>/dev/null || true
 
            # El .zip original ya fue extraído e integrado: no debe terminar
            # dentro de la imagen de Docker (no aporta nada al contenedor y
            # puede confundirse con contenido real). Se marca para exclusión
            # vía .dockerignore más abajo; aquí solo se registra la ruta.
            EMBEDDED_ZIP_SOURCES="${EMBEDDED_ZIP_SOURCES}${zip_file#$INSTANCE_SOURCE/}"$'\n'
        done < <(find "$INSTANCE_SOURCE" -type f -iname '*.zip' ! -path '*/.git/*' ! -path '*/.zip_extract/*' -print0)
 
        [ "$found" -eq 0 ] && break
    done
}
 
EMBEDDED_ZIP_SOURCES=""
extract_embedded_zips
 
# ------------------------------------------------------------------------------
# 2.0 .dockerignore universal: evita que archivos del INSTALADOR (no de la
# app) terminen dentro de la imagen, sin importar el Dockerfile del proyecto.
# ------------------------------------------------------------------------------
# Esto es aditivo: si el repo ya trae su propio .dockerignore, se conserva y
# solo se le añaden estas líneas al final (nunca se sobrescribe).
DOCKERIGNORE_ADDITIONS=$(cat <<'EOF'
 
# --- Añadido automáticamente por el instalador universal ---
# Evita que archivos propios del instalador (no de la aplicación) terminen
# dentro de la imagen construida.
.zip_extract/
EOF
)
if [ -n "$EMBEDDED_ZIP_SOURCES" ]; then
    while IFS= read -r zrel; do
        [ -n "$zrel" ] && DOCKERIGNORE_ADDITIONS="${DOCKERIGNORE_ADDITIONS}"$'\n'"$zrel"
    done <<< "$EMBEDDED_ZIP_SOURCES"
fi
# Excluir el propio instalador si quedó copiado junto al código fuente.
for installer_name in iniciar.sh iniciar_universal_v6_corregido.sh install.sh deploy.sh; do
    [ -f "$INSTANCE_SOURCE/$installer_name" ] && DOCKERIGNORE_ADDITIONS="${DOCKERIGNORE_ADDITIONS}"$'\n'"$installer_name"
done
printf '%s\n' "$DOCKERIGNORE_ADDITIONS" >> "$INSTANCE_SOURCE/.dockerignore"
echo "✅ .dockerignore actualizado (excluye artefactos del instalador de la imagen)."
 
# ------------------------------------------------------------------------------
# Detectar la imagen base REAL del Dockerfile de un servicio.
# ------------------------------------------------------------------------------
 
detect_dockerfile_base_image() {
    local dockerfile="$1"
 
    [ -f "$dockerfile" ] || return 0
 
    awk '
        /^[[:space:]]*FROM[[:space:]]+/ {
            line=$0
            sub(/^[[:space:]]*FROM[[:space:]]+/, "", line)
            sub(/[[:space:]]+[Aa][Ss][[:space:]].*$/, "", line)
            print line
            exit
        }
    ' "$dockerfile"
}
 
# ------------------------------------------------------------------------------
# Clasificar la imagen base.
# ------------------------------------------------------------------------------
 
classify_base_image() {
    local base="$1"
    local lower
 
    lower=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
 
    case "$lower" in
        php:*|php)                         echo "php" ;;
        node:*|node)                       echo "node" ;;
        python:*|python)                   echo "python" ;;
        mariadb:*|mariadb)                 echo "mariadb" ;;
        mysql:*|mysql)                     echo "mysql" ;;
        postgres:*|postgres)               echo "postgres" ;;
        redis:*|redis)                     echo "redis" ;;
        nginx:*|nginx)                     echo "nginx" ;;
        httpd:*|httpd)                     echo "apache" ;;
        phpmyadmin:*|phpmyadmin)           echo "phpmyadmin" ;;
        adminer:*|adminer)                 echo "adminer" ;;
        rabbitmq:*|rabbitmq)               echo "rabbitmq" ;;
        memcached:*|memcached)             echo "memcached" ;;
        eclipse-temurin:*|openjdk:*|amazoncorretto:*|maven:*|gradle:*)
                                            echo "java" ;;
        *)                                  echo "unknown" ;;
    esac
}
 
# ------------------------------------------------------------------------------
# 2.1 Preparar Docker sin modificar la configuración existente
# ------------------------------------------------------------------------------
echo "================================================="
echo "🐳 2.1 Preparando configuración Docker de la instancia"
echo "================================================="
 
# La copia de la instancia debe contener exactamente la configuración que se va a desplegar.
# Si el proyecto ya tiene Dockerfile/Compose, se leen y se conservan.
INSTANCE_DOCKERFILE_PATH=""
# Respetar exactamente cada build.context + build.dockerfile del Compose.
if [ -n "$BUILD_TARGETS" ]; then
    while IFS=$'\t' read -r svc ctx df eff; do
        [ -n "$svc" ] || continue
        case "$eff" in
            "$REPO_DIR"/*)
                rel="${eff#$REPO_DIR/}"
                if [ -f "$INSTANCE_SOURCE/$rel" ]; then
                    echo "✅ $svc → Dockerfile existente: $rel"
                    [ -n "$INSTANCE_DOCKERFILE_PATH" ] || INSTANCE_DOCKERFILE_PATH="$INSTANCE_SOURCE/$rel"
                else
                    echo "⚠️ $svc requiere Dockerfile: $rel"
                    target="$INSTANCE_SOURCE/$rel"
                    mkdir -p "$(dirname "$target")"
                    service_type=""
 
if [ -f "$eff" ]; then
    base_image=$(detect_dockerfile_base_image "$eff")
    service_type=$(classify_base_image "$base_image")
fi
 
if [ -z "$service_type" ] || [ "$service_type" = "unknown" ]; then
    service_type=$(detect_service_type "$svc" "$ctx")
fi
 
echo "   🔧 Servicio: $svc"
echo "      Contexto : $ctx"
echo "      Dockerfile: $eff"
echo "      Base     : ${base_image:-desconocida}"
echo "      Tipo     : $service_type"   
                    echo "   🧩 Tecnología para '$svc': $service_type"
                    case "$service_type" in
                        node)
                            if ! python3 - "$ctx/package.json" <<'PYNODE'
import json, sys
p=json.load(open(sys.argv[1], encoding='utf-8'))
if 'start' not in (p.get('scripts') or {}):
    raise SystemExit(1)
PYNODE
                            then
                                echo "❌ Node en '$svc' no define scripts.start en package.json."
                                exit 1
                            fi
                            cat > "$target" <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN if [ -f package-lock.json ]; then npm ci; elif [ -f package.json ]; then npm install; else echo 'No se encontró package.json'; exit 1; fi
ENV NODE_ENV=production
EXPOSE 3000
CMD ["npm", "start"]
EOF
                            ;;
                        php)
                            # Nunca introducir chown/chmod sobre rutas asumidas.
                            # Las rutas de permisos se calculan desde el contexto real
                            # y, aun así, se protegen con [ -d ] durante el build.
                            php_web_mode=""
                            if grep -Eqi 'nginx|openresty|php-fpm|fpm' "${COMPOSE_FILES[@]}" 2>/dev/null || [[ "$svc" =~ nginx|fpm ]]; then
                                php_web_mode="fpm"
                            elif grep -Eqi 'apache|httpd' "${COMPOSE_FILES[@]}" 2>/dev/null || [[ "$svc" =~ apache|httpd ]]; then
                                php_web_mode="apache"
                            else
                                local_web_stack=$(detect_local_web_stack "$ctx")
                                case "$local_web_stack" in
                                    nginx) php_web_mode="fpm" ;;
                                    apache) php_web_mode="apache" ;;
                                    nginx+apache)
                                        echo "⚠️ $svc: se detectaron Nginx y Apache sin una indicación clara."
                                        read -r -p "👉 Arquitectura PHP para '$svc' [1=Apache, 2=Nginx+PHP-FPM]: " web_choice
                                        case "${web_choice:-}" in 1) php_web_mode="apache" ;; 2) php_web_mode="fpm" ;; *) echo "❌ Selección inválida."; exit 1 ;; esac
                                        ;;
                                    *)
                                        echo "⚠️ $svc: PHP sin servidor web determinable."
                                        read -r -p "👉 Servidor web para '$svc' [1=Apache, 2=Nginx+PHP-FPM]: " web_choice
                                        case "${web_choice:-}" in 1) php_web_mode="apache" ;; 2) php_web_mode="fpm" ;; *) echo "❌ Selección inválida."; exit 1 ;; esac
                                        ;;
                                esac
                            fi
                            if [ "$php_web_mode" = "fpm" ]; then
                                cat > "$target" <<'EOF'
FROM php:8.2-fpm
WORKDIR /var/www/html
COPY . /var/www/html/
RUN if [ -f /var/www/html/composer.json ]; then \
      apt-get update && apt-get install -y --no-install-recommends git unzip libzip-dev && \
      docker-php-ext-install zip && \
      rm -rf /var/lib/apt/lists/* && \
      php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
      php composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
      rm composer-setup.php && \
      composer install --no-interaction --prefer-dist --no-dev; \
    fi
EXPOSE 9000
CMD ["php-fpm"]
EOF
                            else
                                cat > "$target" <<'EOF'
FROM php:8.2-apache
WORKDIR /var/www/html
COPY . /var/www/html/
RUN if [ -f /var/www/html/composer.json ]; then \
      apt-get update && apt-get install -y --no-install-recommends git unzip libzip-dev && \
      docker-php-ext-install zip && \
      rm -rf /var/lib/apt/lists/* && \
      php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
      php composer-setup.php --install-dir=/usr/local/bin --filename=composer && \
      rm composer-setup.php && \
      composer install --no-interaction --prefer-dist --no-dev; \
    fi
EXPOSE 80
CMD ["apache2-foreground"]
EOF
                            fi
                            append_php_runtime_permissions "$ctx" "$target"
                            ;;
                        python)
                            if [ ! -f "$ctx/app.py" ] && [ ! -f "$ctx/manage.py" ] && [ ! -f "$ctx/main.py" ]; then
                                echo "❌ Python en '$svc' no tiene un punto de entrada seguro (app.py, manage.py o main.py)."
                                exit 1
                            fi
                            if [ -f "$ctx/manage.py" ]; then
                                python_cmd='python manage.py runserver 0.0.0.0:8000'
                            elif [ -f "$ctx/main.py" ]; then
                                python_cmd='python main.py'
                            else
                                python_cmd='python app.py'
                            fi
                            cat > "$target" <<EOF
FROM python:3.12-slim
WORKDIR /app
COPY . .
RUN if [ -f requirements.txt ]; then pip install --no-cache-dir -r requirements.txt; fi
EXPOSE 8000
CMD ["sh", "-c", "$python_cmd"]
EOF
                            ;;
                        static) cat > "$target" <<'EOF'
FROM nginx:alpine
COPY . /usr/share/nginx/html
EXPOSE 80
EOF
                            ;;
                        nginx)
                            if [ -f "$ctx/nginx.conf" ]; then
                                cat > "$target" <<'EOF'
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
EOF
                            else
                                echo "❌ No existe nginx.conf para el servicio '$svc'."
                                echo "   No se generará una configuración Nginx inventada porque podría romper el enrutamiento."
                                exit 1
                            fi
                            ;;
                        apache)
                            if [ -f "$ctx/httpd.conf" ]; then
                                cat > "$target" <<'EOF'
FROM httpd:2.4
COPY httpd.conf /usr/local/apache2/conf/httpd.conf
EXPOSE 80
EOF
                            elif [ -f "$ctx/apache2.conf" ]; then
                                cat > "$target" <<'EOF'
FROM httpd:2.4
COPY apache2.conf /usr/local/apache2/conf/httpd.conf
EXPOSE 80
EOF
                            else
                                cat > "$target" <<'EOF'
FROM httpd:2.4
COPY . /usr/local/apache2/htdocs/
EXPOSE 80
EOF
                            fi
                            ;;
                        java)
                            cat > "$target" <<'EOF'
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY . /app/
EXPOSE 8080
CMD ["sh", "-c", "if [ -f app.jar ]; then exec java -jar app.jar; elif jar=$(find target -maxdepth 1 -type f -name '*.jar' -print -quit 2>/dev/null) && [ -n \"$jar\" ]; then exec java -jar \"$jar\"; else echo 'No se encontró un JAR ejecutable'; exit 1; fi"]
EOF
                            ;;
                        *) echo "❌ No se puede generar de forma segura el Dockerfile de '$svc'."; exit 1;;
                    esac
                    GENERATED_DOCKERFILES="${GENERATED_DOCKERFILES}${target}"$'\n'
                    echo "✅ Dockerfile generado en la ruta exacta: $rel"
                    [ -n "$INSTANCE_DOCKERFILE_PATH" ] || INSTANCE_DOCKERFILE_PATH="$target"
                fi
                ;;
            *)
                echo "❌ Dockerfile de '$svc' está fuera del repositorio: $eff"
                echo "   Se detiene para no romper el aislamiento P${CONTADOR}."
                exit 1
                ;;
        esac
    done <<< "$BUILD_TARGETS"
else
    for f in Dockerfile dockerfile Dockerfile.generated; do
        if [ -f "$INSTANCE_SOURCE/$f" ]; then INSTANCE_DOCKERFILE_PATH="$INSTANCE_SOURCE/$f"; break; fi
    done
    if [ -z "$INSTANCE_DOCKERFILE_PATH" ] && [ -n "$DOCKERFILE_PATH" ] && [ -f "$DOCKERFILE_PATH" ]; then
        rel="${DOCKERFILE_PATH#$REPO_DIR/}"
        mkdir -p "$INSTANCE_SOURCE/$(dirname "$rel")"
        cp "$DOCKERFILE_PATH" "$INSTANCE_SOURCE/$rel"
        INSTANCE_DOCKERFILE_PATH="$INSTANCE_SOURCE/$rel"
    fi
fi
 
# Detectar Apache/Nginx sin sustituir la arquitectura existente.
detect_web_stack() {
    local text=""
    [ -n "$COMPOSE_FILE" ] && text=$(cat "${COMPOSE_FILES[@]}" 2>/dev/null || true)
    text="$text\n$(find "$INSTANCE_SOURCE" -maxdepth 5 -type f \( -name 'Dockerfile*' -o -name 'nginx.conf' -o -name 'httpd.conf' -o -name '*.conf' \) -print0 2>/dev/null | xargs -0 cat 2>/dev/null || true)"
    local n a
    n=$(printf '%s' "$text" | grep -Eic '(^|[^a-z])(nginx|openresty)([^a-z]|$)|nginx:' || true)
    a=$(printf '%s' "$text" | grep -Eic '(^|[^a-z])(apache|httpd)([^a-z]|$)|apache:' || true)
    if [ "$n" -gt 0 ] && [ "$a" -gt 0 ]; then echo "nginx+apache";
    elif [ "$n" -gt 0 ]; then echo "nginx";
    elif [ "$a" -gt 0 ]; then echo "apache";
    else echo "unknown"; fi
}
WEB_STACK=$(detect_web_stack)
echo "🌐 Arquitectura web detectada: $WEB_STACK"
 
INSTANCE_COMPOSE_FILE="${INSTANCE_COMPOSE_FILE:-}"
if [ -z "$INSTANCE_COMPOSE_FILE" ]; then
    # Si generamos PHP-FPM sin Compose, no es seguro inventar una topología HTTP: PHP-FPM
    # escucha FastCGI y necesita Nginx/otro servidor web delante. Detener aquí evita el
    # error predecible de publicar host:80 contra un contenedor que solo escucha 9000.
    if [ "$PROJECT_TYPE" = "php" ] && [ "${GENERATED_PHP_WEB_MODE:-apache}" = "fpm" ]; then
        echo "❌ Se detectó PHP-FPM pero el proyecto no trae Compose."
        echo "   Para no inventar una arquitectura Nginx/PHP-FPM incorrecta, el despliegue se detiene."
        echo "   Añade un Compose existente o una configuración Nginx/Apache completa para que el script pueda respetarla."
        exit 1
    fi
    # Generar Compose en la copia usando el Dockerfile que se va a desplegar.
    # Si el proyecto ya declara su propio puerto (p. ej. PORT=xxxx en package.json),
    # se respeta; solo se usa el valor por tecnología como último recurso.
    if [ -n "${APP_PORT_DETECTED:-}" ]; then
        container_port="$APP_PORT_DETECTED"
    else
        container_port=80
        case "$PROJECT_TYPE" in
            node) container_port=3000 ;;
            python) container_port=8000 ;;
            static|php) container_port=80 ;;
        esac
    fi
    cat > "$INSTANCE_SOURCE/compose.generated.yml" <<EOF
services:
  app:
    build:
      context: .
      dockerfile: $(basename "$INSTANCE_DOCKERFILE_PATH")
    ports:
      - "\${APP_PORT:-$((1080 + (CONTADOR - 1) * 2))}:$container_port"
    restart: unless-stopped
EOF
    INSTANCE_COMPOSE_FILE="$INSTANCE_SOURCE/compose.generated.yml"
    INSTANCE_COMPOSE_FILES=("$INSTANCE_COMPOSE_FILE")
    echo "✅ Compose generado para la instancia."
fi
 
# 🔴 Propagar el/los Compose de la instancia a partir de aquí: todo el resto
# del script (build, up, ps, logs, etc.) debe operar sobre la copia aislada
# Pn/source, nunca sobre el repositorio original clonado.
COMPOSE_FILE="$INSTANCE_COMPOSE_FILE"
COMPOSE_FILES=("${INSTANCE_COMPOSE_FILES[@]}")
build_compose_f_args
 
# ------------------------------------------------------------------------------
# Validación preventiva de Dockerfiles
# ------------------------------------------------------------------------------
# REGLA CRÍTICA:
#   - Dockerfile que ya existía en el repositorio: NO se modifica y NO se etiqueta
#     como "generado" aunque contenga chown/chmod específicos.
#   - Dockerfile generado por este instalador: se valida estrictamente.
#   - Si un Dockerfile EXISTENTE referencia una ruta de la imagen que no existe ni
#     se crea previamente, no se intenta "corregirlo" silenciosamente: se detiene
#     ANTES del build y se muestra la causa exacta.
validate_generated_dockerfile_copy_sources() {
    local dockerfile="$1" ctx="$2" line src src_abs
    [ -f "$dockerfile" ] || { echo "❌ No existe Dockerfile: $dockerfile"; return 1; }
    while IFS= read -r line; do
        src=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*(COPY|ADD)[[:space:]]+(--[^[:space:]]+[[:space:]]+)*([^[:space:]]+)([[:space:]]+[^[:space:]]+)?$/\3/')
        [ -n "$src" ] || continue
        case "$src" in
            .|./*) continue ;;
            http://*|https://*|--from=*) continue ;;
        esac
        src_abs="$ctx/$src"
        if [[ "$src" == *'*'* || "$src" == *'?'* || "$src" == *'['* ]]; then
            compgen -G "$src_abs" >/dev/null 2>&1 || { echo "❌ Dockerfile generado referencia un patrón inexistente: $src"; return 1; }
        elif [ ! -e "$src_abs" ]; then
            echo "❌ Dockerfile generado referencia una ruta inexistente en el contexto: $src"
            echo "   Contexto: $ctx"
            return 1
        fi
    done < <(grep -E '^[[:space:]]*(COPY|ADD)[[:space:]]+' "$dockerfile" || true)
    return 0
}
 
# Verifica RUN chown/chmod sobre rutas absolutas del DOCUMENTO existente.
# No modifica el archivo: solo evita llegar al build con un fallo determinista.
validate_existing_dockerfile_runtime_paths() {
    local svc ctx df eff rel path candidate source_rel
    [ -n "${BUILD_TARGETS:-}" ] || return 0
    while IFS=$'\t' read -r svc ctx df eff; do
        [ -n "$svc" ] || continue
        case "$eff" in
            "$REPO_DIR_ORIGINAL"/*) rel="${eff#$REPO_DIR_ORIGINAL/}" ;;
            *) continue ;;
        esac
        path="$INSTANCE_SOURCE/$rel"
        [ -f "$path" ] || continue
 
        # Este chequeo SOLO aplica a Dockerfiles que ya existían en el repositorio.
        if [ -f "$REPO_DIR_ORIGINAL/$rel" ]; then
            while IFS= read -r candidate; do
                [ -n "$candidate" ] || continue
                candidate="${candidate#/var/www/html/}"
                case "$candidate" in
                    storage|storage/*|api/events|api/events/*|bootstrap/cache|bootstrap/cache/*|var|var/*|runtime|runtime/*|writable|writable/*)
                        source_rel="$candidate"
                        if [ ! -e "$ctx/$source_rel" ] && ! grep -Eq "(mkdir|install)[[:space:]]+[^\n]*${source_rel}([[:space:]]|/|$)" "$path"; then
                            echo "❌ Dockerfile existente '$rel' intenta usar '/var/www/html/$source_rel', pero esa ruta no existe en el build.context."
                            echo "   Servicio : $svc"
                            echo "   Contexto : $ctx"
                            echo "   Archivo  : $rel"
                            echo "   El script NO modificará el Dockerfile del proyecto."
                            echo "   Corrige el repositorio o crea la ruta antes de volver a desplegar."
                            return 1
                        fi
                        ;;
                esac
            done < <(grep -Eo '/var/www/html/(storage|storage/[^[:space:]&;|]+|api/events|api/events/[^[:space:]&;|]+|bootstrap/cache|bootstrap/cache/[^[:space:]&;|]+|var|var/[^[:space:]&;|]+|runtime|runtime/[^[:space:]&;|]+|writable|writable/[^[:space:]&;|]+)' "$path" 2>/dev/null | sort -u || true)
        fi
    done <<< "$BUILD_TARGETS"
    return 0
}
 
validate_generated_dockerfiles() {
    local svc ctx df eff rel path
    local any_generated=0
    if [ -n "${BUILD_TARGETS:-}" ]; then
        while IFS=$'\t' read -r svc ctx df eff; do
            [ -n "$svc" ] || continue
            case "$eff" in
                "$REPO_DIR_ORIGINAL"/*) rel="${eff#$REPO_DIR_ORIGINAL/}" ;;
                *) continue ;;
            esac
            path="$INSTANCE_SOURCE/$rel"
            [ -f "$path" ] || { echo "❌ Falta el Dockerfile de '$svc': $rel"; return 1; }
 
            # La existencia en el repositorio ORIGINAL es la única fuente de verdad
            # para decidir si el Dockerfile era del proyecto.
            if [ -f "$REPO_DIR_ORIGINAL/$rel" ]; then
                echo "ℹ️ '$rel' es Dockerfile ORIGINAL del proyecto: se respeta sin modificar y no se aplican reglas del generador."
                continue
            fi
 
            any_generated=1
            if grep -qE 'chown -R www-data:www-data /var/www/html/(storage|api/events)' "$path"; then
                echo "❌ El generador produjo una instrucción de permisos estática en '$rel'."
                echo "   Esto no debe ocurrir: los permisos generados deben ser dinámicos."
                return 1
            fi
            if grep -qE 'php:[^[:space:]]+' "$path" && grep -qE 'chown -R www-data:www-data' "$path"; then
                grep -q '\[ -d "\$d" \]' "$path" || { echo "❌ Permisos PHP no protegidos contra directorios inexistentes: $rel"; return 1; }
            fi
            validate_generated_dockerfile_copy_sources "$path" "$ctx" || return 1
        done <<< "$BUILD_TARGETS"
    elif [ -n "${INSTANCE_DOCKERFILE_PATH:-}" ] && [ -f "$INSTANCE_DOCKERFILE_PATH" ]; then
        if [ "${DOCKERFILE_WAS_GENERATED:-0}" = "1" ]; then
            any_generated=1
            if grep -qE 'chown -R www-data:www-data /var/www/html/(storage|api/events)' "$INSTANCE_DOCKERFILE_PATH"; then
                echo "❌ El generador produjo una instrucción de permisos estática en el Dockerfile."
                return 1
            fi
            if grep -qE 'php:[^[:space:]]+' "$INSTANCE_DOCKERFILE_PATH" && grep -qE 'chown -R www-data:www-data' "$INSTANCE_DOCKERFILE_PATH"; then
                grep -q '\[ -d "\$d" \]' "$INSTANCE_DOCKERFILE_PATH" || { echo "❌ Permisos PHP no protegidos contra directorios inexistentes."; return 1; }
            fi
            validate_generated_dockerfile_copy_sources "$INSTANCE_DOCKERFILE_PATH" "$REPO_DIR_ORIGINAL" || return 1
        fi
    fi
    [ "$any_generated" -eq 0 ] && echo "ℹ️ No hay Dockerfiles generados por el instalador que requieran validación adicional."
    return 0
}
 
validate_generated_dockerfiles
validate_existing_dockerfile_runtime_paths
 
if ! docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" config >/dev/null; then
    echo "❌ El Compose existente/generado no pudo ser resuelto por Docker Compose."
    echo "   No se realizará ningún despliegue."
    exit 1
fi
 
COMPOSE_CONFIG=$(docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" config)
mapfile -t SERVICES < <(docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" config --services)
[ "${#SERVICES[@]}" -gt 0 ] || { echo "❌ Compose no contiene servicios."; exit 1; }
 
echo "✅ Compose válido. Servicios detectados:"
printf '   • %s\n' "${SERVICES[@]}"
 
 
[ -f "$REPO_DIR/.env.example" ] && cp "$REPO_DIR/.env.example" "$CARPETA_DESTINO/.env.example" || true
 
# Compatibilidad con el resto del instalador: a partir de aquí se trabaja sobre la instancia.
# ------------------------------------------------------------------------------
# 3. Analizar servicio de BD e imagen exacta
# ------------------------------------------------------------------------------
 
DB_SERVICE=""
DB_ENGINE=""
DB_IMAGE=""
DB_NAME_DETECTED=""
DB_USER_DETECTED=""
DB_PASSWORD_DETECTED=""
DB_ADMIN_USER_DETECTED=""
DB_ADMIN_PASSWORD_DETECTED=""
ROOT_PASSWORD_DETECTED=""
 
for preferred in mysql mariadb db database postgres postgresql; do
    for svc in "${SERVICES[@]}"; do
        if [ "$(printf '%s' "$svc" | tr '[:upper:]' '[:lower:]')" = "$preferred" ]; then
            DB_SERVICE="$svc"
            break 2
        fi
    done
done
 
if [ -z "$DB_SERVICE" ]; then
    for svc in "${SERVICES[@]}"; do
        lower=$(printf '%s' "$svc" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower" =~ (mysql|mariadb|postgres|database|db) ]]; then
            DB_SERVICE="$svc"
            break
        fi
    done
fi
 
service_block() {
    local svc="$1"
    printf '%s\n' "$COMPOSE_CONFIG" | awk -v svc="$svc" '
        $0 == "  " svc ":" {inside=1; next}
        inside && /^  [A-Za-z0-9_.-]+:$/ {exit}
        inside {print}
    '
}
 
if [ -n "$DB_SERVICE" ]; then
    SERVICE_BLOCK=$(service_block "$DB_SERVICE")
    DB_IMAGE=$(printf '%s\n' "$SERVICE_BLOCK" | awk '/^[[:space:]]+image:/ {sub(/^[^:]+:[[:space:]]*/, ""); print; exit}' | sed 's/^"//;s/"$//' || true)
 
    DB_NAME_DETECTED=$(printf '%s\n' "$SERVICE_BLOCK" | grep -E '^[[:space:]]+(MYSQL_DATABASE|MARIADB_DATABASE|POSTGRES_DB):' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
    DB_USER_DETECTED=$(printf '%s\n' "$SERVICE_BLOCK" | grep -E '^[[:space:]]+(MYSQL_USER|MARIADB_USER|POSTGRES_USER):' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
    DB_PASSWORD_DETECTED=$(printf '%s\n' "$SERVICE_BLOCK" | grep -E '^[[:space:]]+(MYSQL_PASSWORD|MARIADB_PASSWORD|POSTGRES_PASSWORD):' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
    ROOT_PASSWORD_DETECTED=$(printf '%s\n' "$SERVICE_BLOCK" | grep -E '^[[:space:]]+(MYSQL_ROOT_PASSWORD|MARIADB_ROOT_PASSWORD):' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
    DB_ADMIN_USER_DETECTED=$(printf '%s\n' "$SERVICE_BLOCK" | grep -E '^[[:space:]]+POSTGRES_USER:' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
    DB_ADMIN_PASSWORD_DETECTED=$(printf '%s\n' "$SERVICE_BLOCK" | grep -E '^[[:space:]]+POSTGRES_PASSWORD:' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
 
    case "${DB_IMAGE,,}" in
        *mariadb*) DB_ENGINE="mariadb" ;;
        *mysql*) DB_ENGINE="mysql" ;;
        *postgres*) DB_ENGINE="postgres" ;;
    esac
 
    if [ -z "$DB_ENGINE" ]; then
        if printf '%s\n' "$SERVICE_BLOCK" | grep -qE 'MARIADB_(DATABASE|USER|PASSWORD|ROOT_PASSWORD)'; then
            DB_ENGINE="mariadb"
        elif printf '%s\n' "$SERVICE_BLOCK" | grep -qE 'POSTGRES_(DB|USER|PASSWORD)'; then
            DB_ENGINE="postgres"
        elif printf '%s\n' "$SERVICE_BLOCK" | grep -qE 'MYSQL_(DATABASE|USER|PASSWORD|ROOT_PASSWORD)'; then
            echo "⚠️ El servicio '$DB_SERVICE' usa variables MYSQL_* pero su imagen no identifica el motor."
            echo "   No se adivinará silenciosamente entre MySQL y MariaDB."
            echo "1) MySQL"
            echo "2) MariaDB"
            read -r -p "👉 Selección [1]: " engine_choice
            engine_choice=${engine_choice:-1}
            case "$engine_choice" in
                1) DB_ENGINE="mysql" ;;
                2) DB_ENGINE="mariadb" ;;
                *) echo "❌ Selección inválida."; exit 1 ;;
            esac
        fi
    fi
    if [ "$DB_ENGINE" = "postgres" ]; then
        # POSTGRES_USER/POSTGRES_PASSWORD son credenciales administrativas de la imagen oficial,
        # no deben tratarse automáticamente como usuario/contraseña de la aplicación.
        DB_USER_DETECTED=""
        DB_PASSWORD_DETECTED=""
        ROOT_PASSWORD_DETECTED="$DB_ADMIN_PASSWORD_DETECTED"
    fi
fi
 
# ------------------------------------------------------------------------------
# 4. Elegir modo BD / SQL
# ------------------------------------------------------------------------------
DB_MODE="none"
DB_NAME="$DB_NAME_DETECTED"
DB_APP_USER=""
DB_APP_PASS=""
GRANT_MODE="none"
CREATE_DB_USER="2"
SQL_FILE=""
 
if [ -n "$DB_SERVICE" ]; then
    # Para PostgreSQL, buscar las credenciales de aplicación en los servicios que consumen la BD.
    # Nunca se reutiliza POSTGRES_USER como usuario de aplicación por defecto.
    if [ "$DB_ENGINE" = "postgres" ]; then
        for svc in "${SERVICES[@]}"; do
            [ "$svc" = "$DB_SERVICE" ] && continue
            APP_BLOCK=$(service_block "$svc" || true)
            candidate_user=$(printf '%s\n' "$APP_BLOCK" | grep -E '^[[:space:]]+(DB_USERNAME|DB_USER|DATABASE_USER):' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
            candidate_pass=$(printf '%s\n' "$APP_BLOCK" | grep -E '^[[:space:]]+(DB_PASSWORD|DATABASE_PASSWORD):' | head -n1 | sed -E 's/^[^:]+:[[:space:]]*//;s/^"//;s/"$//' || true)
            if [ -n "$candidate_user" ]; then DB_USER_DETECTED="$candidate_user"; DB_PASSWORD_DETECTED="$candidate_pass"; break; fi
        done
    fi
    echo "================================================="
    echo "🗄️ 2. Configuración de base de datos"
    echo "================================================="
    echo "Servicio : $DB_SERVICE"
    echo "Motor    : ${DB_ENGINE:-no determinado}"
    echo "Imagen   : ${DB_IMAGE:-no especificada}"
    echo ""
    echo "1) Crear/usar BD y no importar SQL"
    echo "2) Crear/usar BD e importar SQL si está vacía"
    echo "3) No gestionar la BD desde este instalador"
    read -r -p "👉 Selección [1]: " DB_MODE
    DB_MODE=${DB_MODE:-1}
    [[ "$DB_MODE" =~ ^[123]$ ]] || { echo "❌ Selección inválida."; exit 1; }
 
    if [ -z "$DB_NAME" ]; then
        read -r -p "👉 Nombre de la base de datos: " DB_NAME
    else
        read -r -p "👉 Nombre de la base de datos [$DB_NAME]: " tmp
        DB_NAME=${tmp:-$DB_NAME}
    fi
 
    if [ "$DB_MODE" = "2" ]; then
        # CORRECCIÓN: la búsqueda debe hacerse sobre $INSTANCE_SOURCE, porque
        # es ahí (no en $REPO_DIR) donde los ZIP internos ya fueron
        # descomprimidos por extract_embedded_zips (carpeta .zip_extract).
        # Buscar en $REPO_DIR se saltaba cualquier .sql que viniera empaquetado
        # dentro de un .zip del repositorio.
        echo "🔎 Buscando archivos SQL dentro del contenido ya descomprimido (incluidos paquetes ZIP internos)..."
        mapfile -t SQL_FILES < <(find "$INSTANCE_SOURCE" -type f \( -iname '*.sql' -o -iname '*.sql.gz' \) ! -path '*/.git/*' | sort)
 
        if [ "${#SQL_FILES[@]}" -eq 0 ]; then
            echo "⚠️ Se seleccionó importar SQL, pero no se encontró ningún archivo .sql/.sql.gz."
            echo "   La BD '$DB_NAME' se creará/usará normalmente y NO se realizará ninguna importación."
            echo "   El despliegue continuará; no se considera un error fatal."
            SQL_FILE=""
        else
            PREFERRED_SQL=""
            for candidate in "${SQL_FILES[@]}"; do
                base=$(basename "$candidate")
                case "${base,,}" in
                    base.sql|base.sql.gz)
                        PREFERRED_SQL="$candidate"
                        break
                        ;;
                esac
            done
 
            if [ -n "$PREFERRED_SQL" ]; then
                SQL_FILE="$PREFERRED_SQL"
                echo "📄 SQL inicial detectado: ${SQL_FILE#$INSTANCE_SOURCE/}"
            elif [ "${#SQL_FILES[@]}" -eq 1 ]; then
                SQL_FILE="${SQL_FILES[0]}"
                echo "📄 SQL detectado: ${SQL_FILE#$INSTANCE_SOURCE/}"
            else
                echo "📄 SQL encontrados en el contenido descomprimido:"
                for i in "${!SQL_FILES[@]}"; do
                    echo "   $((i+1))) ${SQL_FILES[$i]#$INSTANCE_SOURCE/}"
                done
                read -r -p "👉 Selección [1]: " SQL_INDEX
                SQL_INDEX=${SQL_INDEX:-1}
                [[ "$SQL_INDEX" =~ ^[0-9]+$ ]] && [ "$SQL_INDEX" -ge 1 ] && [ "$SQL_INDEX" -le "${#SQL_FILES[@]}" ] || { echo "❌ Selección inválida."; exit 1; }
                SQL_FILE="${SQL_FILES[$((SQL_INDEX-1))]}"
            fi
        fi
    fi
fi
 
if [ -n "$DB_SERVICE" ] && [ "$DB_MODE" != "3" ] && [ -n "$DB_ENGINE" ]; then
    echo "================================================="
    echo "👤 3. Usuario de base de datos"
    echo "================================================="
    echo "1) Crear/configurar usuario de aplicación"
    echo "2) No crear usuario"
    read -r -p "👉 Selección [1]: " CREATE_DB_USER
    CREATE_DB_USER=${CREATE_DB_USER:-1}
 
    if [ "$CREATE_DB_USER" = "1" ]; then
        DB_APP_USER="$DB_USER_DETECTED"
        if [ -n "$DB_USER_DETECTED" ]; then
            echo "🔎 Docker Compose ya declara el usuario BD '$DB_USER_DETECTED'."
            if [ -n "$DB_PASSWORD_DETECTED" ]; then echo "   También se detectó una contraseña configurada en Docker (no se mostrará)."; fi
            echo "1) Usar exactamente las credenciales declaradas por Docker"
            echo "2) Crear/configurar otro usuario"
            read -r -p "👉 Selección [1]: " USE_DETECTED_DB_CREDS
            USE_DETECTED_DB_CREDS=${USE_DETECTED_DB_CREDS:-1}
        else
            USE_DETECTED_DB_CREDS=2
        fi
 
        if [ "$USE_DETECTED_DB_CREDS" = "1" ]; then
            DB_APP_USER="$DB_USER_DETECTED"
            DB_APP_PASS="$DB_PASSWORD_DETECTED"
            echo "✅ Se reutilizarán las credenciales de Docker para evitar desincronizar la aplicación y la BD."
        else
            read -r -p "👉 Usuario BD [${DB_APP_USER:-app}]: " tmp
            DB_APP_USER=${tmp:-${DB_APP_USER:-app}}
            read -r -s -p "👉 Contraseña BD (ENTER = sin contraseña): " DB_APP_PASS
            echo ""
            if [ -n "$DB_APP_PASS" ]; then
                read -r -s -p "👉 Confirmar contraseña BD: " DB_APP_PASS_CONFIRM
                echo ""
                [ "$DB_APP_PASS" = "$DB_APP_PASS_CONFIRM" ] || { echo "❌ Las contraseñas de BD no coinciden."; exit 1; }
            else
                DB_APP_PASS=""
                echo "✅ El usuario de BD se configurará sin contraseña."
            fi
        fi
 
        if [[ "$DB_ENGINE" == "mysql" || "$DB_ENGINE" == "mariadb" || "$DB_ENGINE" == "postgres" ]]; then
            echo "1) Todos los permisos solo sobre '$DB_NAME'"
            echo "2) Permisos básicos de aplicación"
            echo "3) Crear usuario sin otorgar permisos"
            read -r -p "👉 Permisos [1]: " GRANT_MODE
            GRANT_MODE=${GRANT_MODE:-1}
            [[ "$GRANT_MODE" =~ ^[123]$ ]] || { echo "❌ Selección inválida."; exit 1; }
        fi
    fi
fi
 
# ------------------------------------------------------------------------------
# 4.1 Preflight de credenciales BD antes de tocar Docker
# ------------------------------------------------------------------------------
validate_db_credentials_plan() {
    [ -n "$DB_SERVICE" ] || return 0
    [ "$DB_MODE" != "3" ] || return 0
    if [ -z "$DB_ENGINE" ]; then
        echo "❌ No se pudo determinar el motor de BD de '$DB_SERVICE'."
        echo "   No se crearán usuarios ni se intentará una conexión a ciegas."
        return 1
    fi
    if [ -z "$DB_NAME" ]; then
        echo "❌ No se definió el nombre de la base de datos."
        return 1
    fi
    if [ "$CREATE_DB_USER" = "1" ] && [ -z "$DB_APP_USER" ]; then
        echo "❌ Se solicitó crear usuario BD pero el nombre quedó vacío."
        return 1
    fi
    # Para MySQL/MariaDB, si Docker ya declara MYSQL/MARIADB_USER, una contraseña
    # diferente solo es válida si el usuario será alterado explícitamente después.
    # La opción de reutilizar credenciales evita esa desincronización.
    if [[ "$DB_ENGINE" == "mysql" || "$DB_ENGINE" == "mariadb" ]] && [ -n "$DB_USER_DETECTED" ] && [ "$CREATE_DB_USER" = "1" ]; then
        if [ "$DB_APP_USER" = "$DB_USER_DETECTED" ] && [ -n "$DB_PASSWORD_DETECTED" ] && [ "$DB_APP_PASS" != "$DB_PASSWORD_DETECTED" ]; then
            echo "❌ El usuario BD '$DB_APP_USER' ya está declarado por Docker con una contraseña diferente."
            echo "   Debes reutilizar las credenciales declaradas por Docker o cambiar conscientemente la configuración de la aplicación/Compose."
            return 1
        fi
    fi
    return 0
}
validate_db_credentials_plan
 
# ------------------------------------------------------------------------------
# 5. Generar variables de instancia
# ------------------------------------------------------------------------------
NUM_INSTANCIA=$((CONTADOR - 1))
BASE_WEB=$((1080 + NUM_INSTANCIA * 2))
BASE_PMA=$((8081 + NUM_INSTANCIA * 2))
BASE_DB=$((3307 + NUM_INSTANCIA))
BASE_SSL=$((8443 + NUM_INSTANCIA * 2))
 
next_free_port() {
    local p="$1" step="$2"
    while ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\.)${p}$"; do
        p=$((p + step))
    done
    echo "$p"
}
 
PUERTO_WEB=$(next_free_port "$BASE_WEB" 2)
PUERTO_PMA=$(next_free_port "$BASE_PMA" 2)
PUERTO_DB=$(next_free_port "$BASE_DB" 1)
PUERTO_SSL=$(next_free_port "$BASE_SSL" 2)
 
python3 - "$INSTANCE_ENV" "$COMPOSE_PROJECT_NAME" "$SYSTEM_NAME" "$INSTANCE_SOURCE" "$PUERTO_WEB" "$PUERTO_PMA" "$PUERTO_DB" "$PUERTO_SSL" "$DB_NAME" "$DB_APP_USER" "$DB_APP_PASS" "$CREATE_DB_USER" <<'PY'
import sys, os
p=sys.argv[1]
managed={
    "COMPOSE_PROJECT_NAME": sys.argv[2],
    "PREFIX_CONTENEDOR": sys.argv[2],
    "PROJECT_NAME": sys.argv[3],
    "PROJECT_SOURCE": sys.argv[4],
    "PUERTO_WEB": sys.argv[5],
    "PUERTO_PMA": sys.argv[6],
    "PUERTO_DB": sys.argv[7],
    "PUERTO_SSL": sys.argv[8],
}
# No sobrescribir credenciales existentes del proyecto con cadenas vacías.
# Solo gestionamos las variables genéricas de BD cuando el usuario pidió crear
# explícitamente un usuario de aplicación.
if sys.argv[9]:
    managed["DB_DATABASE"] = sys.argv[9]
if sys.argv[10] and sys.argv[12] == "1":
    managed["DB_USERNAME"] = sys.argv[10]
    managed["DB_PASSWORD"] = sys.argv[11]
lines=open(p).read().splitlines() if __import__('os').path.exists(p) else []
out=[]
seen=set()
for line in lines:
    if not line or line.lstrip().startswith('#') or '=' not in line:
        out.append(line); continue
    key=line.split('=',1)[0]
    if key in managed:
        if key not in seen:
            out.append(f'{key}={managed[key]}'); seen.add(key)
    else:
        out.append(line)
for k,v in managed.items():
    if k not in seen:
        out.append(f'{k}={v}')
open(p,'w').write('\n'.join(out)+'\n')
PY
 
# ------------------------------------------------------------------------------
# 6. Renderizar Compose para esta instancia y analizar aislamiento
# ------------------------------------------------------------------------------
render_compose() {
    docker compose \
        --env-file "$INSTANCE_ENV" \
        "${COMPOSE_F_ARGS[@]}" \
        --project-directory "$INSTANCE_SOURCE" \
        -p "$COMPOSE_PROJECT_NAME" \
        config --format json
}
 
RENDERED_JSON=$(render_compose)
 
# Persistir en disco SOLO una versión saneada: `docker compose config` resuelve
# todas las variables de entorno, así que el JSON crudo puede contener
# contraseñas/tokens en texto plano. El JSON crudo se mantiene solo en memoria
# ($RENDERED_JSON) para el análisis interno del propio script; a disco va
# siempre la versión redactada.
# Se escribe primero a un archivo temporal y se lee por argv/archivo (nunca
# interpolado dentro del heredoc): el contenido del Compose viene del
# repositorio remoto y no es de confianza; interpolarlo directamente en un
# heredoc sin comillas permitiría inyección de comandos ($(), backticks).
RENDERED_JSON_TMP=$(mktemp)
printf '%s\n' "$RENDERED_JSON" > "$RENDERED_JSON_TMP"
python3 - "$RENDERED_JSON_TMP" "$CARPETA_DESTINO/compose.rendered.json" <<'PYSAFE'
import json, re, sys
src, out = sys.argv[1], sys.argv[2]
with open(src) as fh:
    data = json.load(fh)
SENSITIVE = re.compile(r'(PASSWORD|TOKEN|SECRET|_KEY|CREDENTIAL|PRIVATE_KEY)', re.IGNORECASE)
 
def redact_env(env):
    if isinstance(env, dict):
        return {k: ("***REDACTED***" if SENSITIVE.search(k) else v) for k, v in env.items()}
    if isinstance(env, list):
        result = []
        for item in env:
            if isinstance(item, str) and "=" in item:
                k, _, v = item.partition("=")
                result.append(f"{k}=***REDACTED***" if SENSITIVE.search(k) else item)
            else:
                result.append(item)
        return result
    return env
 
for svc in (data.get("services") or {}).values():
    if "environment" in svc:
        svc["environment"] = redact_env(svc["environment"])
 
with open(out, "w") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PYSAFE
rm -f "$RENDERED_JSON_TMP"
 
# Detectar si los servicios de aplicación tienen una configuración de conexión a BD
# que contradiga el servicio DB. No se modifica el Compose: se informa y se detiene
# únicamente cuando la contradicción es inequívoca.
validate_app_db_configuration() {
    [ -n "$DB_SERVICE" ] || return 0
    python3 - "$RENDERED_JSON" "$DB_SERVICE" "$DB_NAME" "$DB_APP_USER" "$DB_APP_PASS" "$INSTANCE_SOURCE/.env" <<'PYDB'
import json,sys,re,os
j=json.loads(sys.argv[1]); dbsvc=sys.argv[2]; dbname=sys.argv[3]; dbuser=sys.argv[4]; dbpass=sys.argv[5]
project_env=sys.argv[6]
services=j.get('services') or {}
errors=[]; warnings=[]
 
def env_map(c):
    env=c.get('environment') or {}
    if isinstance(env,list):
        env={x.split('=',1)[0]:x.split('=',1)[1] if '=' in x else '' for x in env}
    return {str(k): '' if v is None else str(v) for k,v in env.items()}
 
def project_env_map(path):
    out={}
    if not os.path.isfile(path): return out
    for raw in open(path,encoding='utf-8',errors='ignore'):
        line=raw.strip()
        if not line or line.startswith('#') or '=' not in line: continue
        k,v=line.split('=',1); out[k.strip()]=v.strip().strip('"').strip("'")
    return out
 
def first(env, keys):
    for k in keys:
        if k in env and env[k] != '': return env[k]
    return ''
 
db=services.get(dbsvc) or {}
dbenv=env_map(db)
db_port=''
for p in db.get('ports') or []:
    if isinstance(p,dict) and str(p.get('target','')) in {'3306','5432'}:
        db_port=str(p.get('target'))
        break
# container's native port is preferable to the published host port
if not db_port:
    db_port='5432' if 'POSTGRES' in ' '.join(dbenv.keys()) else '3306'
 
db_networks=set((db.get('networks') or {}).keys())
if not db_networks:
    db_networks={'default'}
 
host_keys={'DB_HOST','DATABASE_HOST','MYSQL_HOST','MARIADB_HOST','POSTGRES_HOST'}
port_keys={'DB_PORT','DATABASE_PORT','MYSQL_PORT','MARIADB_PORT','POSTGRES_PORT'}
name_keys={'DB_DATABASE','DATABASE_NAME','MYSQL_DATABASE','MARIADB_DATABASE','POSTGRES_DB'}
user_keys={'DB_USERNAME','DB_USER','DATABASE_USER','MYSQL_USER','MARIADB_USER','POSTGRES_USER'}
pass_keys={'DB_PASSWORD','DATABASE_PASSWORD','MYSQL_PASSWORD','MARIADB_PASSWORD','POSTGRES_PASSWORD'}
project_env=project_env_map(project_env)
 
for name,c in services.items():
    if name==dbsvc: continue
    env=env_map(c)
    # Also inspect the project's .env because frameworks such as Laravel often read it inside the app.
    merged=dict(project_env)
    merged.update({k:v for k,v in env.items() if v!=''})
    host=first(merged,host_keys)
    port=first(merged,port_keys)
    database=first(merged,name_keys)
    user=first(merged,user_keys)
    password=first(merged,pass_keys)
 
    # Soporte universal para DATABASE_URL / DATABASE_URI usados por muchos frameworks.
    database_url=first(merged,{'DATABASE_URL','DATABASE_URI'})
    if database_url:
        try:
            from urllib.parse import urlparse, unquote
            u=urlparse(database_url)
            if not host: host=u.hostname or ''
            if not port: port=str(u.port or '')
            if not database: database=(u.path or '').lstrip('/')
            if not user: user=unquote(u.username or '')
            if not password: password=unquote(u.password or '')
        except Exception:
            warnings.append(f"{name}: DATABASE_URL no pudo analizarse automáticamente; se respetará sin modificarla.")
 
    if not any([host,port,database,user,password]):
        continue
 
    if host in {'localhost','127.0.0.1','::1'} and len(services)>1:
        errors.append(f"{name}: DB_HOST='{host}' apunta al propio contenedor; debe usar el nombre del servicio Docker '{dbsvc}'.")
    elif host and host != dbsvc and host not in {str(db.get('container_name','')), dbsvc}:
        warnings.append(f"{name}: DB_HOST='{host}'. No se modificará porque podría ser un host externo válido.")
 
    if database and dbname and database != dbname:
        errors.append(f"{name}: base configurada='{database}' pero la BD gestionada='{dbname}'.")
    if user and dbuser and user != dbuser:
        errors.append(f"{name}: usuario configurado='{user}' pero usuario gestionado='{dbuser}'.")
    if password and dbpass and password != dbpass:
        errors.append(f"{name}: la contraseña configurada para la BD no coincide con la del usuario gestionado.")
 
    if port and host == dbsvc and port.isdigit() and port != db_port:
        errors.append(f"{name}: DB_PORT={port} usa el puerto publicado/incorrecto; el servicio '{dbsvc}' escucha internamente en {db_port}.")
 
    app_networks=set((c.get('networks') or {}).keys()) or {'default'}
    if not (app_networks & db_networks):
        errors.append(f"{name}: no comparte ninguna red Docker con '{dbsvc}'.")
 
if warnings:
    print('⚠️ Advertencias de conexión BD:')
    for x in warnings: print('   '+x)
if errors:
    print('❌ Inconsistencias de conexión BD detectadas antes del despliegue:')
    for x in errors: print('   '+x)
    print('   No se modificará automáticamente el Compose ni el .env del proyecto.')
    sys.exit(2)
PYDB
    local rc=$?
    if [ "$rc" -eq 2 ]; then
        echo "🛑 Se detiene antes de docker compose up para evitar un fallo de conexión a la BD." 
        return 1
    fi
    return "$rc"
}
 
validate_app_db_configuration
 
# SOLO después de validar la topología app↔BD y las credenciales declaradas se permite construir.
# Así un error de DB_HOST/DB_PORT/usuario/red se detecta antes de gastar tiempo en el build.
if grep -qE '^\s*build:' <<<"$COMPOSE_CONFIG"; then
    echo "🔨 Validando/build de los Dockerfiles declarados por Compose..."
    if ! docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" build; then
        echo "❌ Falló la construcción de una imagen declarada por Compose."
        exit 1
    fi
fi
 
ANALYSIS_FILE="$CARPETA_DESTINO/resource-analysis.txt"
printf "%s\n" "$RENDERED_JSON" > "$CARPETA_DESTINO/compose.rendered.json.tmp"
python3 - "$CARPETA_DESTINO/compose.rendered.json.tmp" "$ANALYSIS_FILE" <<'PY'
import json, sys
src=sys.argv[1]
out=sys.argv[2]
d=json.load(open(src))
lines=[]
services=d.get('services') or {}
volumes=d.get('volumes') or {}
networks=d.get('networks') or {}
 
lines.append('[SERVICES]')
for s,c in services.items():
    if c.get('container_name'):
        lines.append(f'CONTAINER_NAME|{s}|{c["container_name"]}')
    for p in c.get('ports') or []:
        if isinstance(p, dict):
            host=p.get('published','')
            target=p.get('target','')
            proto=p.get('protocol','tcp')
            lines.append(f'PORT|{s}|{host}|{target}|{proto}')
    for m in c.get('volumes') or []:
        if isinstance(m, dict):
            typ=m.get('type','')
            source=m.get('source','')
            target=m.get('target','')
            lines.append(f'MOUNT|{s}|{typ}|{source}|{target}')
 
lines.append('[VOLUMES]')
for name,v in volumes.items():
    lines.append(f'VOLUME|{name}|name={v.get("name","")}|external={v.get("external",False)}')
 
lines.append('[NETWORKS]')
for name,n in networks.items():
    lines.append(f'NETWORK|{name}|name={n.get("name","")}|external={n.get("external",False)}')
 
open(out,'w').write('\n'.join(lines)+'\n')
PY
rm -f "$CARPETA_DESTINO/compose.rendered.json.tmp"
 
# ------------------------------------------------------------------------------
# 7. Verificación estricta de aislamiento
# ------------------------------------------------------------------------------
echo "================================================="
echo "🛡️ 4. Verificando aislamiento de la instancia $NOMBRE_CARPETA"
echo "================================================="
 
CONFLICT=0
 
while IFS='|' read -r kind svc cname; do
    [ "$kind" = "CONTAINER_NAME" ] || continue
    if docker ps -a --format '{{.Names}}' | grep -Fxq "$cname"; then
        echo "❌ CONFLICTO: el container_name '$cname' ya existe."
        echo "   El Compose debe usar un nombre derivado de COMPOSE_PROJECT_NAME o eliminar container_name."
        CONFLICT=1
    fi
done < "$ANALYSIS_FILE"
 
while IFS='|' read -r kind vname namepart externalpart; do
    [ "$kind" = "VOLUME" ] || continue
    fixed_name="${namepart#name=}"
    external="${externalpart#external=}"
    if [ "$external" = "True" ] || [ "$external" = "true" ]; then
        echo "❌ CONFLICTO: volumen externo '$vname'."
        echo "   Una nueva instancia no puede reutilizar automáticamente un volumen externo."
        CONFLICT=1
    elif [ -n "$fixed_name" ] && [[ "$fixed_name" != "${COMPOSE_PROJECT_NAME}_"* ]]; then
        echo "❌ CONFLICTO: volumen '$vname' tiene nombre explícito '$fixed_name'."
        echo "   Un nombre explícito solo es seguro si queda aislado bajo '$COMPOSE_PROJECT_NAME'."
        CONFLICT=1
    fi
done < "$ANALYSIS_FILE"
 
while IFS='|' read -r kind nname namepart externalpart; do
    [ "$kind" = "NETWORK" ] || continue
    fixed_name="${namepart#name=}"
    external="${externalpart#external=}"
    if [ "$external" = "True" ] || [ "$external" = "true" ]; then
        echo "❌ CONFLICTO: red externa '$nname'."
        echo "   Una nueva instancia no puede compartirla automáticamente."
        CONFLICT=1
    elif [ -n "$fixed_name" ] && [[ "$fixed_name" != "${COMPOSE_PROJECT_NAME}_"* ]]; then
        echo "❌ CONFLICTO: red '$nname' tiene nombre explícito '$fixed_name'."
        echo "   Un nombre explícito solo es seguro si queda aislado bajo '$COMPOSE_PROJECT_NAME'."
        CONFLICT=1
    fi
done < "$ANALYSIS_FILE"
 
while IFS='|' read -r kind svc typ source target; do
    [ "$kind" = "MOUNT" ] || continue
    if [ "$typ" = "bind" ]; then
        case "$source" in
            "$REPO_DIR"|"$REPO_DIR"/*|"$CARPETA_DESTINO"|"$CARPETA_DESTINO"/*) ;;
            *)
                echo "❌ CONFLICTO: bind mount externo en '$svc': '$source' -> '$target'"
                echo "   No se puede garantizar aislamiento entre P1/P2/P3."
                CONFLICT=1
                ;;
        esac
    fi
done < "$ANALYSIS_FILE"
 
while IFS='|' read -r kind svc host target proto; do
    [ "$kind" = "PORT" ] || continue
    [ -n "$host" ] || continue
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\.)${host}$"; then
        echo "❌ CONFLICTO: el puerto host $host/$proto de '$svc' ya está ocupado."
        echo "   El Compose debe consumir una variable de instancia para poder asignar otro puerto."
        CONFLICT=1
    fi
done < "$ANALYSIS_FILE"
 
while IFS='|' read -r kind svc host target proto; do
    [ "$kind" = "PORT" ] || continue
    [ -n "$host" ] || continue
    owners=$(docker ps --format '{{.Names}}' --filter "publish=$host" 2>/dev/null || true)
    if [ -n "$owners" ]; then
        echo "❌ CONFLICTO Docker: $svc intenta publicar $host y ya existe: $owners"
        CONFLICT=1
    fi
done < "$ANALYSIS_FILE"
 
if [ "$CONFLICT" -ne 0 ]; then
    echo ""
    echo "🛑 DESPLIEGUE DETENIDO ANTES DE docker compose up."
    echo "   No se eliminaron volúmenes, contenedores ni redes."
    echo "   Revisa '$CARPETA_DESTINO/resource-analysis.txt'."
    exit 1
fi
 
echo "✅ No se detectaron recursos fijos/external que puedan colisionar."
 
# ------------------------------------------------------------------------------
# 8. Preflight de imágenes: conservar exactamente la imagen declarada
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# 8. PREFLIGHT DE IMÁGENES
#
# REGLAS UNIVERSALES:
#
#   Servicio con build:
#       -> Compose construirá usando SU context + SU Dockerfile.
#
#   Servicio sin build + image:
#       -> usar imagen local
#       -> si no existe, intentar pull
#       -> si tampoco existe, ERROR
#
# NUNCA:
#       -> buscar otro Dockerfile arbitrariamente
#       -> construir una image desde un Dockerfile que pertenece a otro servicio
# ------------------------------------------------------------------------------
 
preflight_images() {
    local svc
    local image
    local has_build
    local dockerfile
 
    for svc in "${SERVICES[@]}"; do
 
        image="${SERVICE_IMAGE[$svc]:-}"
        has_build="${SERVICE_HAS_BUILD[$svc]:-0}"
        dockerfile="${SERVICE_DOCKERFILE[$svc]:-}"
 
        echo ""
        echo "🔎 Preflight: $svc"
        echo "   image : ${image:-(ninguna)}"
        echo "   build : $has_build"
 
        # ------------------------------------------------------------------
        # 1. BUILD DECLARADO
        # ------------------------------------------------------------------
        if [ "$has_build" = "1" ]; then
 
            if [ -z "$dockerfile" ]; then
                echo "❌ $svc declara build pero no tiene Dockerfile resuelto."
                echo "   Contexto: ${SERVICE_BUILD_CONTEXT[$svc]:-(desconocido)}"
                return 1
            fi
 
            if [ ! -f "$dockerfile" ]; then
                echo "❌ Dockerfile inexistente para '$svc':"
                echo "   $dockerfile"
                return 1
            fi
 
            echo "   ✅ Build válido."
            echo "   Contexto   : ${SERVICE_BUILD_CONTEXT[$svc]}"
            echo "   Dockerfile : $dockerfile"
 
            continue
        fi
 
        # ------------------------------------------------------------------
        # 2. NO HAY BUILD -> DEBE EXISTIR IMAGE
        # ------------------------------------------------------------------
        if [ -z "$image" ]; then
            echo "❌ El servicio '$svc' no tiene ni 'build' ni 'image'."
            return 1
        fi
 
        # ------------------------------------------------------------------
        # 3. IMAGE LOCAL
        # ------------------------------------------------------------------
        if docker image inspect "$image" >/dev/null 2>&1; then
            echo "   ✅ Imagen local disponible: $image"
            continue
        fi
 
        # ------------------------------------------------------------------
        # 4. IMAGE REMOTA
        # ------------------------------------------------------------------
        echo "   ⬇️ Imagen no encontrada localmente."
        echo "   Intentando descargar: $image"
 
        if docker pull "$image"; then
            echo "   ✅ Imagen descargada correctamente."
            continue
        fi
 
        # ------------------------------------------------------------------
        # 5. ERROR REAL
        # ------------------------------------------------------------------
        echo ""
        echo "❌ No se pudo resolver la imagen del servicio '$svc'."
        echo ""
        echo "   image : $image"
        echo "   build : no"
        echo ""
        echo "   El Bash universal NO buscará otro Dockerfile."
        echo "   Debes declarar un build o proporcionar una image válida."
        echo ""
 
        return 1
    done
 
    return 0
}
preflight_images || exit 1
 
# ------------------------------------------------------------------------------
# 9. Guardar manifiesto ANTES del despliegue
# ------------------------------------------------------------------------------
cat > "$MANIFEST" <<EOF
SYSTEM_NAME=$SYSTEM_NAME
INSTANCE=$NOMBRE_CARPETA
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME
REPOSITORY_ROOT=$REPO_DIR_ORIGINAL
INSTANCE_SOURCE=$INSTANCE_SOURCE
COMPOSE_FILE=$COMPOSE_FILE
DB_SERVICE=$DB_SERVICE
DB_ENGINE=$DB_ENGINE
DB_IMAGE=$DB_IMAGE
DB_DATABASE=$DB_NAME
SQL_FILE=${SQL_FILE:-}
SQL_IMPORT_REQUESTED=$([ "$DB_MODE" = "2" ] && echo yes || echo no)
CREATED_AT=$(date -Is)
VOLUME_POLICY=INSTANCE_ISOLATED
DESTRUCTIVE_VOLUME_OPERATION=NEVER_AUTOMATIC
DOCKERFILE_SOURCE=$(basename "${INSTANCE_DOCKERFILE_PATH:-}")
DOCKERFILE_GENERATED=$([[ "${INSTANCE_DOCKERFILE_PATH:-}" == *.generated ]] && echo yes || echo no)
COMPOSE_SOURCE=$(basename "${COMPOSE_FILE:-}")
COMPOSE_GENERATED=$([[ "${COMPOSE_FILE:-}" == *.generated.yml ]] && echo yes || echo no)
EOF
 
{
    echo "# Recursos renderizados para $NOMBRE_CARPETA"
    cat "$ANALYSIS_FILE"
} >> "$MANIFEST"
 
# ------------------------------------------------------------------------------
# 9.1 Manifiesto estructurado (deployment-manifest.json)
# ------------------------------------------------------------------------------
# Solo información operacional. Nunca contiene credenciales, tokens ni
# contraseñas: DB_APP_PASS, REPO_AUTH_TOKEN, etc. quedan fuera a propósito.
# Se genera al final (tras verificar el stack) con el estado real; aquí solo
# se capturan datos del commit desplegado, que no cambian.
DEPLOY_COMMIT=""
DEPLOY_BRANCH=""
if [ -d "$REPO_DIR_ORIGINAL/.git" ]; then
    DEPLOY_COMMIT=$(git -C "$REPO_DIR_ORIGINAL" rev-parse HEAD 2>/dev/null || true)
    DEPLOY_BRANCH=$(git -C "$REPO_DIR_ORIGINAL" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi
 
write_deployment_manifest() {
    # $1 = status ("success" | "failed")
    local status="$1"
    local out="$CARPETA_DESTINO/deployment-manifest.json"
    COMPOSE_FILES_JOINED=$(printf '%s\x1f' "${COMPOSE_FILES[@]}") \
    SERVICES_JOINED=$(printf '%s\x1f' "${SERVICES[@]:-}") \
    python3 - "$out" "$SYSTEM_NAME" "$NOMBRE_CARPETA" "$REPO_URL" "$DEPLOY_COMMIT" "$DEPLOY_BRANCH" "$COMPOSE_PROJECT_NAME" "$status" <<'PYMANIFEST'
import json, sys, subprocess, os
 
out, system_name, instance, repo_url, commit, branch, project_name, status = sys.argv[1:9]
compose_files = [c for c in os.environ.get("COMPOSE_FILES_JOINED", "").split("\x1f") if c]
services = [s for s in os.environ.get("SERVICES_JOINED", "").split("\x1f") if s]
 
data = {
    "system": system_name,
    "instance": instance,
    "repository": repo_url,
    "branch": branch,
    "commit": commit,
    "compose_files": [os.path.basename(c) for c in compose_files],
    "services": services,
    "project_name": project_name,
    "created_at": subprocess.check_output(["date", "-Is"]).decode().strip(),
    "status": status,
}
with open(out, "w") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
PYMANIFEST
}
 
# ------------------------------------------------------------------------------
# 10. Levantar instancia NUEVA
# ------------------------------------------------------------------------------
echo "================================================="
echo "🐳 5. Desplegando $SYSTEM_NAME como $NOMBRE_CARPETA"
echo "================================================="
echo "📦 Proyecto Compose : $COMPOSE_PROJECT_NAME"
echo "💾 Política         : volumen nuevo/aislado"
echo "🛑 No se ejecutará  : docker compose down -v"
echo ""
 
docker compose \
    --env-file "$INSTANCE_ENV" \
    "${COMPOSE_F_ARGS[@]}" \
    --project-directory "$INSTANCE_SOURCE" \
    -p "$COMPOSE_PROJECT_NAME" \
    up -d --build --remove-orphans
 
# ------------------------------------------------------------------------------
# 10.1 CORRECCIÓN UNIVERSAL DE PERMISOS (evita 403 Forbidden en cualquier stack)
# ------------------------------------------------------------------------------
# No se puede confiar en que el Dockerfile de CADA proyecto (distintos repos,
# distintos autores, distintos ZIP de origen) haga chmod correctamente después
# de copiar el código. La única forma verdaderamente universal de garantizar
# que el servidor web pueda leer sus propios archivos es corregir los permisos
# DENTRO del contenedor ya en ejecución, sin importar su imagen base ni su
# Dockerfile. No requiere editar nada de cada proyecto ni reconstruir nada.
echo "================================================="
echo "🔐 5.1 Normalizando permisos dentro de los contenedores (evita 403 Forbidden)..."
echo "================================================="
COMMON_WEBROOTS="/var/www/html /var/www /usr/share/nginx/html /app /srv/www /home/site/wwwroot"
RUNNING_CONTAINERS=$(docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" -p "$COMPOSE_PROJECT_NAME" ps -q 2>/dev/null || true)
for cid in $RUNNING_CONTAINERS; do
    cname=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##')
    for webroot in $COMMON_WEBROOTS; do
        # a+rX: añade lectura a todos y ejecución/traspaso SOLO a directorios
        # (o archivos que ya eran ejecutables). Nunca quita permisos
        # existentes, así que es seguro sin importar qué usuario use el
        # proceso del contenedor (www-data, node, app, root, etc.).
        docker exec "$cid" sh -c "[ -d '$webroot' ] && chmod -R a+rX '$webroot' 2>/dev/null" >/dev/null 2>&1 && \
            echo "   ✅ Permisos normalizados en $cname:$webroot" || true
    done
done
 
# ------------------------------------------------------------------------------
# 11. Esperar BD
# ------------------------------------------------------------------------------
DB_CONTAINER=""
if [ -n "$DB_SERVICE" ] && [ "$DB_MODE" != "3" ]; then
    echo "================================================="
    echo "⏳ 6. Esperando BD '$DB_SERVICE'"
    echo "================================================="
 
    for intento in $(seq 1 60); do
        DB_CONTAINER=$(docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" -p "$COMPOSE_PROJECT_NAME" ps -q "$DB_SERVICE" 2>/dev/null || true)
        [ -n "$DB_CONTAINER" ] && break
        sleep 2
done
    [ -n "$DB_CONTAINER" ] || { echo "❌ No se encontró el contenedor de BD."; exit 1; }
 
    DB_READY=0
    for intento in $(seq 1 60); do
        DB_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo desconocido)
        if [ "$DB_STATUS" != "running" ]; then
            echo ""
            echo "❌ El contenedor de BD no está en ejecución (estado: $DB_STATUS)."
            echo "-------------------------------------------------"
            LOGS=$(docker logs --tail 80 "$DB_CONTAINER" 2>&1 || true)
            printf '%s\n' "$LOGS" | sed 's/^/    /'
            echo "-------------------------------------------------"
            if printf '%s\n' "$LOGS" | grep -qiE 'got signal 6|assertion|innodb.*(corrupt|error)|tablespace.*(corrupt|error)'; then
                echo "⚠️ Se detectó un patrón de fallo de InnoDB/SIGABRT."
                echo "   Posibles causas: incompatibilidad/corrupción del datadir o problema de imagen."
                echo "   Esta instancia NO borrará el volumen automáticamente."
            fi
            exit 1
        fi
 
        case "$DB_ENGINE" in
            mysql|mariadb)
                if docker exec "$DB_CONTAINER" mariadb-admin ping -u root --silent >/dev/null 2>&1 || \
                   docker exec "$DB_CONTAINER" mysqladmin ping -u root --silent >/dev/null 2>&1 || \
                   { [ -n "$ROOT_PASSWORD_DETECTED" ] && docker exec "$DB_CONTAINER" mariadb-admin ping -u root -p"$ROOT_PASSWORD_DETECTED" --silent >/dev/null 2>&1; } || \
                   { [ -n "$ROOT_PASSWORD_DETECTED" ] && docker exec "$DB_CONTAINER" mysqladmin ping -u root -p"$ROOT_PASSWORD_DETECTED" --silent >/dev/null 2>&1; }; then
                    DB_READY=1
                fi
                ;;
            postgres)
                docker exec "$DB_CONTAINER" pg_isready >/dev/null 2>&1 && DB_READY=1 || true
                ;;
            *)
                DB_READY=1
                ;;
        esac
 
        [ "$DB_READY" -eq 1 ] && break
        echo "   ... BD aún no está lista ($intento/60)"
        sleep 2
    done
 
    [ "$DB_READY" -eq 1 ] || { echo "❌ La BD no llegó a estar disponible."; exit 1; }
 
    # CORRECCIÓN CRUCIAL: un ping exitoso no garantiza que la BD esté lista
    # para enlazar. MySQL/MariaDB arrancan primero un servidor TEMPORAL para
    # ejecutar la inicialización (creación de datadir, scripts, etc.) y luego
    # se reinician para levantar el servidor DEFINITIVO. Si el ping atrapa el
    # servidor temporal, la conexión puede caerse segundos después justo
    # cuando se intenta crear la BD o importar el SQL.
    #
    # Por eso: tras el primer ping exitoso, esperamos el tiempo de enlace
    # (10-15s) y volvemos a verificar que la BD SIGA respondiendo antes de
    # continuar. Si en ese lapso el servidor se reinició, se reintenta la
    # espera completa.
    echo "⏳ Primer ping recibido. Esperando estabilización del enlace (10-15s) antes de continuar..."
    DB_STABLE=0
    for intento_estable in 1 2 3; do
        sleep 12
        case "$DB_ENGINE" in
            mysql|mariadb)
                if docker exec "$DB_CONTAINER" mariadb-admin ping -u root --silent >/dev/null 2>&1 || \
                   docker exec "$DB_CONTAINER" mysqladmin ping -u root --silent >/dev/null 2>&1 || \
                   { [ -n "$ROOT_PASSWORD_DETECTED" ] && docker exec "$DB_CONTAINER" mariadb-admin ping -u root -p"$ROOT_PASSWORD_DETECTED" --silent >/dev/null 2>&1; } || \
                   { [ -n "$ROOT_PASSWORD_DETECTED" ] && docker exec "$DB_CONTAINER" mysqladmin ping -u root -p"$ROOT_PASSWORD_DETECTED" --silent >/dev/null 2>&1; }; then
                    DB_STABLE=1
                fi
                ;;
            postgres)
                docker exec "$DB_CONTAINER" pg_isready >/dev/null 2>&1 && DB_STABLE=1 || true
                ;;
            *)
                DB_STABLE=1
                ;;
        esac
        if [ "$DB_STABLE" -eq 1 ]; then
            DB_STATUS=$(docker inspect -f '{{.State.Status}}' "$DB_CONTAINER" 2>/dev/null || echo desconocido)
            [ "$DB_STATUS" = "running" ] && break
            DB_STABLE=0
        fi
        echo "   ⚠️ La BD aún se está reiniciando/estabilizando (intento $intento_estable/3)..."
    done
    [ "$DB_STABLE" -eq 1 ] || { echo "❌ La BD no logró estabilizarse tras el enlace inicial."; exit 1; }
    echo "✅ Base de datos lista y enlace estable."
 
    # --------------------------------------------------------------------------
    # 11.1 Comprobación REAL de red app -> BD
    # --------------------------------------------------------------------------
    # No basta con que el contenedor DB esté healthy: la aplicación puede seguir
    # teniendo DB_HOST/DB_PORT incorrectos o estar aislada en otra red.
    validate_live_app_db_network() {
        local svc cid host port
        [ -n "$DB_SERVICE" ] || return 0
        [ "$DB_MODE" != "3" ] || return 0
        while IFS=$'\t' read -r svc host port; do
            [ -n "$svc" ] || continue
            [ "$svc" = "$DB_SERVICE" ] && continue
            [ "$host" = "$DB_SERVICE" ] || continue
            cid=$(docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" -p "$COMPOSE_PROJECT_NAME" ps -q "$svc" 2>/dev/null || true)
            [ -n "$cid" ] || continue
            echo "🔌 Probando conectividad $svc -> $DB_SERVICE ($host:$port)..."
 
            # Intentos en orden: nc, bash /dev/tcp, PHP, Python, Node.
            if docker exec "$cid" sh -c "command -v nc >/dev/null 2>&1 && nc -z -w 5 '$host' '$port'" >/dev/null 2>&1; then
                echo "   ✅ TCP accesible desde '$svc'."
                continue
            fi
            if docker exec "$cid" sh -c "command -v bash >/dev/null 2>&1 && bash -lc 'echo > /dev/tcp/$host/$port'" >/dev/null 2>&1; then
                echo "   ✅ TCP accesible desde '$svc'."
                continue
            fi
            if docker exec "$cid" sh -c "command -v php >/dev/null 2>&1 && php -r '\$f=@fsockopen(\"$host\",$port,\$e,\$m,5); exit(\$f?0:1);'" >/dev/null 2>&1; then
                echo "   ✅ TCP accesible desde '$svc'."
                continue
            fi
            if docker exec "$cid" sh -c "command -v python3 >/dev/null 2>&1 && python3 -c 'import socket; s=socket.create_connection((\"$host\",$port),5); s.close()'" >/dev/null 2>&1; then
                echo "   ✅ TCP accesible desde '$svc'."
                continue
            fi
            if docker exec "$cid" sh -c "command -v node >/dev/null 2>&1 && node -e 'const net=require(\"net\");let s=net.createConnection($port,\"$host\");s.setTimeout(5000);s.on(\"connect\",()=>{s.destroy();process.exit(0)});s.on(\"error\",()=>process.exit(1));s.on(\"timeout\",()=>process.exit(1))'" >/dev/null 2>&1; then
                echo "   ✅ TCP accesible desde '$svc'."
                continue
            fi
 
            echo "❌ '$svc' no puede alcanzar '$DB_SERVICE' en $host:$port."
            echo "   Verifica DB_HOST, DB_PORT y las networks del Compose."
            return 1
        done < <(python3 - "$RENDERED_JSON" "$DB_SERVICE" "$INSTANCE_SOURCE/.env" <<'PYLIVE'
import json,sys,os
from urllib.parse import urlparse
j=json.loads(sys.argv[1]); dbsvc=sys.argv[2]; envpath=sys.argv[3]
services=j.get('services') or {}
project={}
if os.path.isfile(envpath):
    for raw in open(envpath,encoding='utf-8',errors='ignore'):
        line=raw.strip()
        if line and not line.startswith('#') and '=' in line:
            k,v=line.split('=',1); project[k.strip()]=v.strip().strip('"').strip("'")
 
def envmap(c):
    e=c.get('environment') or {}
    if isinstance(e,list): e={x.split('=',1)[0]:x.split('=',1)[1] if '=' in x else '' for x in e}
    return {str(k): '' if v is None else str(v) for k,v in e.items()}
def first(e,keys):
    for k in keys:
        if e.get(k): return e[k]
    return ''
for name,c in services.items():
    if name==dbsvc: continue
    e=dict(project); e.update({k:v for k,v in envmap(c).items() if v})
    host=first(e,('DB_HOST','DATABASE_HOST','MYSQL_HOST','MARIADB_HOST','POSTGRES_HOST'))
    port=first(e,('DB_PORT','DATABASE_PORT','MYSQL_PORT','MARIADB_PORT','POSTGRES_PORT'))
    url=first(e,('DATABASE_URL','DATABASE_URI'))
    if url:
        try:
            u=urlparse(url); host=host or (u.hostname or ''); port=port or str(u.port or '')
        except Exception: pass
    if host==dbsvc:
        if not port: port='5432' if 'POSTGRES' in str(services.get(dbsvc,{}).get('environment','')) else '3306'
        print(f'{name}\t{host}\t{port}')
PYLIVE
)
    }
    validate_live_app_db_network
 
    # --------------------------------------------------------------------------
    # 12. Inicialización MySQL/MariaDB sin destruir datos
    # --------------------------------------------------------------------------
    if [[ "$DB_ENGINE" == "mysql" || "$DB_ENGINE" == "mariadb" ]] && [ -n "$DB_NAME" ]; then
        if docker exec "$DB_CONTAINER" mariadb --version >/dev/null 2>&1; then
            MYSQL_BIN=mariadb
        else
            MYSQL_BIN=mysql
        fi
 
        root_exec() {
            if [ -n "$ROOT_PASSWORD_DETECTED" ]; then
                docker exec "$DB_CONTAINER" "$MYSQL_BIN" -u root -p"$ROOT_PASSWORD_DETECTED" "$@"
            else
                docker exec "$DB_CONTAINER" "$MYSQL_BIN" -u root "$@"
            fi
        }
 
        # Verificación de compatibilidad de credenciales antes de crear el usuario.
        # Si Compose ya define MYSQL/MARIADB_USER+PASSWORD y el usuario eligió credenciales
        # diferentes, la aplicación podría intentar entrar con otras credenciales y fallar.
        if [ -n "$DB_USER_DETECTED" ] && [ "$CREATE_DB_USER" = "1" ]; then
            if [ "$DB_APP_USER" != "$DB_USER_DETECTED" ]; then
                echo "⚠️ El usuario BD elegido ('$DB_APP_USER') no coincide con el usuario declarado por Docker ('$DB_USER_DETECTED')."
                echo "   No se modificará el Compose existente automáticamente."
                echo "   La aplicación solo funcionará si su configuración apunta al usuario elegido."
            elif [ -n "$DB_PASSWORD_DETECTED" ] && [ "$DB_APP_PASS" != "$DB_PASSWORD_DETECTED" ]; then
                echo "❌ La contraseña elegida para '$DB_APP_USER' no coincide con la contraseña declarada por Docker."
                echo "   Para evitar un fallo posterior de conexión, selecciona 'usar las credenciales declaradas por Docker' o actualiza la configuración de la aplicación de forma consciente."
                exit 1
            elif [ -z "$DB_PASSWORD_DETECTED" ] && [ -n "$DB_APP_PASS" ]; then
                echo "⚠️ Docker declara el usuario '$DB_APP_USER' sin contraseña, pero se eligió una contraseña."
                echo "   No se modificará el Compose existente automáticamente."
                echo "   El despliegue se detendrá para evitar una aplicación desincronizada."
                exit 1
            fi
        fi
 
        DB_EXISTS=$(root_exec -N -B -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$(sql_escape "$DB_NAME")';" 2>/dev/null || true)
        if [ "$DB_EXISTS" != "$DB_NAME" ]; then
            root_exec -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;"
            echo "✅ BD '$DB_NAME' creada."
        else
            echo "✅ BD '$DB_NAME' ya existe; no se elimina ni reinicializa."
        fi
if [ "$DB_MODE" = "2" ] && [ -n "$SQL_FILE" ]; then
            TABLE_COUNT=$(root_exec -N -B -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$(sql_escape "$DB_NAME")';" 2>/dev/null || echo 0)
            if [ "$TABLE_COUNT" = "0" ]; then
                echo "📥 Importando $(basename "$SQL_FILE")..."
                
                # 1. Copiamos el archivo físicamente dentro del contenedor para evitar errores de buffer o SSL
                docker cp "$SQL_FILE" "$DB_CONTAINER:/tmp/archivo_import.sql"
                
                # 2. Ejecutamos la importación directamente desde adentro del contenedor
                if [[ "$SQL_FILE" == *.gz ]]; then
                    if [ -n "$ROOT_PASSWORD_DETECTED" ]; then
                        docker exec "$DB_CONTAINER" sh -c "gzip -dc /tmp/archivo_import.sql | $MYSQL_BIN -u root -p\"$ROOT_PASSWORD_DETECTED\" \"$DB_NAME\""
                    else
                        docker exec "$DB_CONTAINER" sh -c "gzip -dc /tmp/archivo_import.sql | $MYSQL_BIN -u root \"$DB_NAME\""
                    fi
                else
                    if [ -n "$ROOT_PASSWORD_DETECTED" ]; then
                        docker exec "$DB_CONTAINER" sh -c "$MYSQL_BIN -u root -p\"$ROOT_PASSWORD_DETECTED\" \"$DB_NAME\" < /tmp/archivo_import.sql"
                    else
                        docker exec "$DB_CONTAINER" sh -c "$MYSQL_BIN -u root \"$DB_NAME\" < /tmp/archivo_import.sql"
                    fi
                fi
                
                # 3. Limpiamos el archivo temporal
                docker exec "$DB_CONTAINER" rm -f /tmp/archivo_import.sql
                
                echo "✅ SQL importado."
            else
                echo "ℹ️ La BD ya tiene $TABLE_COUNT tabla(s); se omite SQL para evitar duplicados."
            fi
        fi
 
        if [ -n "$DB_APP_USER" ] && [ "$CREATE_DB_USER" = "1" ]; then
            USER_ESC=$(sql_escape "$DB_APP_USER")
            PASS_ESC=$(sql_escape "$DB_APP_PASS")
            if [ -n "$DB_APP_PASS" ]; then
                root_exec -e "CREATE USER IF NOT EXISTS '$USER_ESC'@'%' IDENTIFIED BY '$PASS_ESC'; ALTER USER '$USER_ESC'@'%' IDENTIFIED BY '$PASS_ESC';"
            else
                root_exec -e "CREATE USER IF NOT EXISTS '$USER_ESC'@'%' IDENTIFIED BY ''; ALTER USER '$USER_ESC'@'%' IDENTIFIED BY '';"
            fi
            case "$GRANT_MODE" in
                1) root_exec -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$USER_ESC'@'%'; FLUSH PRIVILEGES;" ;;
                2) root_exec -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, DROP ON \`$DB_NAME\`.* TO '$USER_ESC'@'%'; FLUSH PRIVILEGES;" ;;
            esac
            echo "✅ Usuario de aplicación configurado."
 
            # Comprobación real de autenticación con las credenciales creadas/reutilizadas.
            # Esto detecta antes del cierre del instalador un usuario inexistente, contraseña
            # desincronizada o permisos insuficientes.
            if ! root_exec -N -B -e "SELECT 1;" >/dev/null 2>&1; then
                echo "❌ La conexión administrativa a la BD dejó de estar disponible."
                exit 1
            fi
            if [ "$GRANT_MODE" != "none" ]; then
                if [ -n "$DB_APP_PASS" ]; then
                    if ! docker exec "$DB_CONTAINER" "$MYSQL_BIN" -u "$DB_APP_USER" -p"$DB_APP_PASS" -N -B -e "SELECT 1 FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='$(sql_escape "$DB_NAME")' LIMIT 1;" >/dev/null 2>&1; then
                        echo "⚠️ No se pudo autenticar al usuario '$DB_APP_USER' con la contraseña configurada."
                        echo "   Verifica que la aplicación use exactamente esas credenciales."
                        exit 1
                    fi
                else
                    if ! docker exec "$DB_CONTAINER" "$MYSQL_BIN" -u "$DB_APP_USER" -N -B -e "SELECT 1;" >/dev/null 2>&1; then
                        echo "⚠️ El usuario '$DB_APP_USER' no pudo autenticarse sin contraseña."
                        exit 1
                    fi
                fi
            fi
        fi
    elif [ "$DB_ENGINE" = "postgres" ] && [ -n "$DB_NAME" ]; then
        PG_BIN="psql"
        pg_admin_exec() {
            if [ -n "$DB_ADMIN_PASSWORD_DETECTED" ]; then
                docker exec -e PGPASSWORD="$DB_ADMIN_PASSWORD_DETECTED" "$DB_CONTAINER" "$PG_BIN" -U "${DB_ADMIN_USER_DETECTED:-postgres}" "$@"
            else
                docker exec "$DB_CONTAINER" "$PG_BIN" -U "${DB_ADMIN_USER_DETECTED:-postgres}" "$@"
            fi
        }
 
        PG_DB_IDENT=$(printf '%s' "$DB_NAME" | sed 's/"/""/g')
        DB_EXISTS=$(pg_admin_exec -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$(sql_escape "$DB_NAME")';" 2>/dev/null | tr -d '[:space:]' || true)
        if [ "$DB_EXISTS" != "1" ]; then
            pg_admin_exec -d postgres -c "CREATE DATABASE \"$PG_DB_IDENT\";"
            echo "✅ BD '$DB_NAME' creada en PostgreSQL."
        else
            echo "✅ BD '$DB_NAME' ya existe; no se elimina ni reinicializa."
        fi
 
        if [ -n "$DB_APP_USER" ] && [ "$CREATE_DB_USER" = "1" ]; then
            PG_USER_IDENT=$(printf '%s' "$DB_APP_USER" | sed 's/"/""/g')
            if pg_admin_exec -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='$(sql_escape "$DB_APP_USER")';" 2>/dev/null | grep -q '^1$'; then
                if [ -n "$DB_APP_PASS" ]; then
                    pg_admin_exec -d postgres -c "ALTER ROLE \"$PG_USER_IDENT\" WITH LOGIN PASSWORD '$(sql_escape "$DB_APP_PASS")';"
                else
                    pg_admin_exec -d postgres -c "ALTER ROLE \"$PG_USER_IDENT\" WITH LOGIN PASSWORD NULL;"
                fi
            else
                if [ -n "$DB_APP_PASS" ]; then
                    pg_admin_exec -d postgres -c "CREATE ROLE \"$PG_USER_IDENT\" LOGIN PASSWORD '$(sql_escape "$DB_APP_PASS")';"
                else
                    pg_admin_exec -d postgres -c "CREATE ROLE \"$PG_USER_IDENT\" LOGIN;"
                fi
            fi
            case "$GRANT_MODE" in
                1) pg_admin_exec -d postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"$PG_DB_IDENT\" TO \"$PG_USER_IDENT\";"; pg_admin_exec -d "$DB_NAME" -c "GRANT ALL ON SCHEMA public TO \"$PG_USER_IDENT\";" ;;
                2) pg_admin_exec -d postgres -c "GRANT CONNECT ON DATABASE \"$PG_DB_IDENT\" TO \"$PG_USER_IDENT\";"; pg_admin_exec -d "$DB_NAME" -c "GRANT USAGE ON SCHEMA public TO \"$PG_USER_IDENT\"; GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO \"$PG_USER_IDENT\";" ;;
            esac
            echo "✅ Usuario PostgreSQL '$DB_APP_USER' configurado."
            if [ -n "$DB_APP_PASS" ]; then
                docker exec -e PGPASSWORD="$DB_APP_PASS" "$DB_CONTAINER" "$PG_BIN" -U "$DB_APP_USER" -d "$DB_NAME" -tAc 'SELECT 1;' >/dev/null 2>&1 || { echo "❌ El usuario PostgreSQL no pudo autenticarse con la contraseña configurada."; exit 1; }
            else
                echo "ℹ️ Usuario PostgreSQL creado sin contraseña; la autenticación remota dependerá de pg_hba.conf." 
            fi
        fi
    fi
fi
 
# ------------------------------------------------------------------------------
# 13. Validación final de aislamiento y estado
# ------------------------------------------------------------------------------
# No basta con "cantidad running == cantidad esperada": un contenedor puede
# estar RUNNING con healthcheck en FAILING (app caída dentro de un proceso
# vivo). Regla real: si el servicio declara healthcheck, exigir HEALTHY;
# si no lo declara, exigir RUNNING. EXITED/RESTARTING/UNHEALTHY = fallo.
FINAL_PS=$(docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" -p "$COMPOSE_PROJECT_NAME" ps --format json 2>/dev/null || true)
printf '%s\n' "$FINAL_PS" > "$CARPETA_DESTINO/containers.json"
 
VERIFY_FAILED=0
declare -A SERVICE_STATUS_MAP=()
declare -A SERVICE_HEALTH_MAP=()
 
verify_all_services() {
    local svc cid state health has_healthcheck
    for svc in "${SERVICES[@]}"; do
        cid=$(docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" -p "$COMPOSE_PROJECT_NAME" ps -q "$svc" 2>/dev/null || true)
        if [ -z "$cid" ]; then
            echo "❌ $svc  NO SE CREÓ EL CONTENEDOR"
            SERVICE_STATUS_MAP["$svc"]="MISSING"
            VERIFY_FAILED=1
            continue
        fi
        state=$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo "unknown")
        has_healthcheck=$(docker inspect -f '{{if .State.Health}}yes{{else}}no{{end}}' "$cid" 2>/dev/null || echo "no")
        health=""
        [ "$has_healthcheck" = "yes" ] && health=$(docker inspect -f '{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "")
 
        SERVICE_STATUS_MAP["$svc"]="$state"
        SERVICE_HEALTH_MAP["$svc"]="$health"
 
        if [ "$has_healthcheck" = "yes" ]; then
            if [ "$health" = "healthy" ]; then
                echo "$svc       ✓ HEALTHY"
            else
                echo "❌ $svc  UNHEALTHY (health=${health:-desconocido}, estado=$state)"
                VERIFY_FAILED=1
            fi
        else
            case "$state" in
                running) echo "$svc       ✓ RUNNING" ;;
                *)
                    echo "❌ $svc  $state"
                    VERIFY_FAILED=1
                    ;;
            esac
        fi
 
        if [ "$state" = "exited" ] || [ "$state" = "dead" ] || [ "$state" = "restarting" ] || \
           { [ "$has_healthcheck" = "yes" ] && [ "$health" != "healthy" ]; }; then
            echo "   ↳ Diagnóstico ($svc):"
            docker compose --env-file "$INSTANCE_ENV" "${COMPOSE_F_ARGS[@]}" --project-directory "$INSTANCE_SOURCE" -p "$COMPOSE_PROJECT_NAME" logs --tail=100 "$svc" 2>/dev/null | sed 's/^/   /' || true
        fi
    done
}
verify_all_services
 
if [ "$VERIFY_FAILED" -eq 1 ]; then
    echo "⚠️ La instancia fue creada pero no todos los servicios están HEALTHY/RUNNING."
    echo "   Revisa: docker compose --env-file '$INSTANCE_ENV' ${COMPOSE_F_ARGS[*]} -p '$COMPOSE_PROJECT_NAME' ps"
    echo "   Logs:   docker compose --env-file '$INSTANCE_ENV' ${COMPOSE_F_ARGS[*]} -p '$COMPOSE_PROJECT_NAME' logs"
    write_deployment_manifest "failed"
    exit 1
fi
 
write_deployment_manifest "success"
 
# ------------------------------------------------------------------------------
# 14. Reporte final
# ------------------------------------------------------------------------------
IP_SERVIDOR=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}' || true)
IP_SERVIDOR=${IP_SERVIDOR:-localhost}
 
cat > "$CARPETA_DESTINO/README-DEPLOY.txt" <<EOF
INSTANCIA: $NOMBRE_CARPETA
PROYECTO COMPOSE: $COMPOSE_PROJECT_NAME
SISTEMA: $SYSTEM_NAME
REPOSITORIO_ORIGINAL: $REPO_DIR_ORIGINAL
FUENTE_DE_INSTANCIA: $INSTANCE_SOURCE
COMPOSE: ${COMPOSE_FILES[*]}
ENV DE INSTANCIA: $INSTANCE_ENV
MANIFIESTO: $MANIFEST
 
POLÍTICA:
- Esta instancia es independiente de P1/P2/P3 anteriores.
- No se ejecuta docker compose down -v automáticamente.
- No se reutilizan volúmenes externos o con nombre fijo.
- No se cambia automáticamente MySQL <-> MariaDB.
- Los datos persistentes de esta instancia pertenecen a su proyecto Compose.
 
COMANDOS:
cd "$INSTANCE_SOURCE"
docker compose --env-file "$INSTANCE_ENV" ${COMPOSE_F_ARGS[*]} -p "$COMPOSE_PROJECT_NAME" ps
docker compose --env-file "$INSTANCE_ENV" ${COMPOSE_F_ARGS[*]} -p "$COMPOSE_PROJECT_NAME" logs -f
docker compose --env-file "$INSTANCE_ENV" ${COMPOSE_F_ARGS[*]} -p "$COMPOSE_PROJECT_NAME" restart
docker compose --env-file "$INSTANCE_ENV" ${COMPOSE_F_ARGS[*]} -p "$COMPOSE_PROJECT_NAME" down
# Para borrar datos persistentes: NO hacerlo desde este instalador; requiere una operación explícita.
EOF
 
chmod 600 "$INSTANCE_ENV" 2>/dev/null || true
chown "$SUDO_USER_NAME:$SUDO_USER_NAME" "$CARPETA_DESTINO" "$INSTANCE_ENV" "$MANIFEST" "$ANALYSIS_FILE" "$CARPETA_DESTINO/README-DEPLOY.txt" 2>/dev/null || true
 
echo ""
echo "================================================="
echo "🎉 ¡DESPLIEGUE EXITOSO!"
echo "================================================="
echo "📦 Sistema             : $SYSTEM_NAME"
echo "📁 Repositorio base     : $REPO_DIR_ORIGINAL"
echo "📁 Fuente de instancia  : $INSTANCE_SOURCE"
echo "🚀 Instancia            : $NOMBRE_CARPETA"
echo "🐳 Proyecto Docker      : $COMPOSE_PROJECT_NAME"
echo "🗄️ Servicio BD          : ${DB_SERVICE:-No detectado}"
echo "🔧 Motor BD             : ${DB_ENGINE:-No determinado}"
echo "💾 Base de datos        : ${DB_NAME:-No gestionada}"
if [ "$DB_MODE" = "2" ]; then
    if [ -n "$SQL_FILE" ]; then
        echo "📄 SQL inicial          : ${SQL_FILE#$INSTANCE_SOURCE/}"
    else
        echo "📄 SQL inicial          : No encontrado (se omitió importación)"
    fi
fi
echo "🌐 IP servidor          : $IP_SERVIDOR"
echo "🔌 Puerto web           : $PUERTO_WEB"
echo "🔐 Puerto SSL           : $PUERTO_SSL"
echo "🗄️ Puerto BD            : $PUERTO_DB"
echo "🧰 Puerto PMA           : $PUERTO_PMA"
echo "-------------------------------------------------"
echo "📌 Recursos de auditoría:"
echo "   $MANIFEST"
echo "   $ANALYSIS_FILE"
echo "   $CARPETA_DESTINO/README-DEPLOY.txt"
echo "-------------------------------------------------"
echo "🔗 URLs de acceso directo:"
echo "   - Web          : http://$IP_SERVIDOR:$PUERTO_WEB"
echo "   - Web (HTTPS)  : https://$IP_SERVIDOR:$PUERTO_SSL  (certificado autofirmado)"
echo "   - phpMyAdmin   : http://$IP_SERVIDOR:$PUERTO_PMA"
echo "-------------------------------------------------"
