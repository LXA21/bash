#!/usr/bin/env bash
###############################################################################
# reverse-proxy.sh
#
# Herramienta única de administración de un Reverse Proxy basado en NGINX
# (NGINX + Certbot) sobre Docker, para publicar múltiples
# dominios/subdominios apuntando a contenedores Docker en el mismo servidor
# Linux, con emisión y renovación automática de SSL (Let's Encrypt).
#
# Todo el ciclo de vida se maneja desde este único archivo mediante
# subcomandos:
#
#   sudo ./reverse-proxy.sh install -e <email>
#   sudo ./reverse-proxy.sh add     -n <app> -H <dominio> -p <puerto> -m <email> (-i <imagen> | -c <contenedor>)
#   sudo ./reverse-proxy.sh remove  -n <app>
#   sudo ./reverse-proxy.sh list
#   sudo ./reverse-proxy.sh status
#   sudo ./reverse-proxy.sh logs    [-n <app>|proxy|acme]
#   sudo ./reverse-proxy.sh uninstall
#
# Compatible con: Ubuntu/Debian (apt) y RHEL/CentOS/Alma/Rocky (dnf/yum)
###############################################################################

set -euo pipefail
IFS=$'\n\t'

# ============================================================================
# CONFIGURACIÓN GLOBAL
# ============================================================================
BASE_DIR="/opt/reverse-proxy"
NETWORK_NAME="proxy"
STATE_FILE="${BASE_DIR}/.state/apps.tsv"   # registro de apps: id<TAB>dominio<TAB>puerto<TAB>tipo
NGINX_IMAGE="nginx:stable-alpine"
CERTBOT_IMAGE="certbot/dns-cloudflare:latest"
CF_CRED_FILE="${BASE_DIR}/nginx/certbot/cloudflare.ini"
DEFAULT_CF_TOKEN="cfut_6pOvks6l6SihKT7uzey62vEMFcPsCdzupZvXqetq878a3668"

# ============================================================================
# UTILIDADES DE SALIDA / LOG
# ============================================================================
C_OK="\033[1;32m"; C_ERR="\033[1;31m"; C_INFO="\033[1;34m"; C_WARN="\033[1;33m"; C_RESET="\033[0m"
log_info()  { echo -e "${C_INFO}[INFO]${C_RESET}  $*"; }
log_ok()    { echo -e "${C_OK}[OK]${C_RESET}    $*"; }
log_warn()  { echo -e "${C_WARN}[WARN]${C_RESET}  $*"; }
log_err()   { echo -e "${C_ERR}[ERROR]${C_RESET} $*" >&2; }
die()       { log_err "$*"; exit 1; }

require_root() {
  [[ "$EUID" -eq 0 ]] || die "Este comando debe ejecutarse como root (usa sudo)."
}

# ============================================================================
# ============================================================================
# AYUDA GENERAL
# ============================================================================
print_main_usage() {
  cat <<EOF
reverse-proxy.sh — Administrador de Proxy Inverso NGINX sobre Docker

USO:
  sudo $0                    Modo interactivo
  sudo $0 <comando> [opciones]

COMANDOS:
  install     Instala Docker, la red compartida, NGINX y Certbot
  add         Publica un dominio/subdominio hacia un contenedor (nuevo o existente)
  redirect    Crea una redirección 301 pura de un dominio hacia otra URL
  remove      Elimina una publicación previamente creada
  list        Lista las apps/dominios publicados
  status      Muestra el estado de NGINX y de las apps
  logs        Muestra logs de NGINX, Certbot o una app
  certs       Muestra el estado y vencimiento de los certificados SSL
  renew       Fuerza la renovación de un certificado (o de todos)
  uninstall   Detiene y elimina NGINX (no borra las apps)
  help        Muestra esta ayuda

EJEMPLOS:
  sudo $0 install -e admin@midominio.com -t "TU_TOKEN_DE_CLOUDFLARE"
  sudo $0 add -n blog -H blog.midominio.com -p 80 -m admin@midominio.com -i wordpress:latest
  sudo $0 add -n web -H midominio.com -a www.midominio.com -p 80 -i mi-app:latest
  sudo $0 add -n api -H api.midominio.com -p 3000 -m admin@midominio.com -c mi-api-existente
  sudo $0 redirect -n old-blog -H viejo.midominio.com -t https://nuevo.midominio.com
  sudo $0 list
  sudo $0 certs
  sudo $0 renew -n blog
  sudo $0 renew -n all
  sudo $0 logs -n blog
  sudo $0 remove -n blog
EOF
}

# ============================================================================
# ESTADO / UTILIDADES
# ============================================================================
ensure_state_file() {
  mkdir -p "$(dirname "$STATE_FILE")"
  [[ -f "$STATE_FILE" ]] || touch "$STATE_FILE"
}

state_add() {
  # id, dominio, puerto, tipo(nuevo|existente|redirect), referencia, aliases
  ensure_state_file
  state_remove_silent "$1"
  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$4" "$5" "${6:--}" >> "$STATE_FILE"
}

state_remove_silent() {
  ensure_state_file
  grep -v -P "^${1}\t" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
  mv -f "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true
}

state_get() {
  ensure_state_file
  grep -P "^${1}\t" "$STATE_FILE" || true
}

reload_nginx() {
  if docker inspect nginx-proxy >/dev/null 2>&1; then
    docker exec nginx-proxy nginx -t >/dev/null 2>&1 || die "La configuración generada de NGINX es inválida."
    docker exec nginx-proxy nginx -s reload >/dev/null 2>&1 || die "No se pudo recargar NGINX."
  fi
}

certbot_run() {
  docker run --rm \
    -v "${BASE_DIR}/nginx/certbot:/etc/letsencrypt" \
    -v "${BASE_DIR}/nginx/html:/var/www/certbot" \
    -v "${BASE_DIR}/nginx/logs:/var/log/letsencrypt" \
    "${CERTBOT_IMAGE}" "$@"
}

certbot_cert_name() {
  local domain="$1"
  echo "$domain"
}

all_hosts() {
  local domain="$1" aliases="$2"
  if [[ -n "$aliases" && "$aliases" != "-" ]]; then
    echo "${domain},${aliases}"
  else
    echo "$domain"
  fi
}

hosts_to_args() {
  local hosts="$1" h
  IFS=',' read -ra _hs <<< "$hosts"
  for h in "${_hs[@]}"; do
    h="$(echo "$h" | xargs)"
    [[ -n "$h" ]] && printf -- '-d\n%s\n' "$h"
  done
}

# NGINX se configura centralmente. Cada publicación tiene un bloque propio
# y comparte el mismo directorio para el desafío HTTP-01 de Certbot.
generate_nginx_config() {
  ensure_state_file
  # Garantiza las rutas antes de crear managed.conf.tmp. Esto permite usar
  # add/remove incluso si la instalación existente quedó incompleta o proviene
  # de una versión anterior del script.
  mkdir -p "${BASE_DIR}/nginx/conf.d" "${BASE_DIR}/nginx/html/.well-known/acme-challenge" \
           "${BASE_DIR}/nginx/certbot" "${BASE_DIR}/nginx/logs" "${BASE_DIR}/nginx/certs"
  local out="${BASE_DIR}/nginx/conf.d/managed.conf"
  local tmp="${out}.tmp"
  : > "$tmp"

  while IFS=$'\t' read -r id domain port tipo ref aliases; do
    [[ -z "$id" ]] && continue
    local hosts; hosts="$(all_hosts "$domain" "$aliases")"
    local backend="$ref"
    [[ "$tipo" == "nuevo" ]] && backend="$id"

    local crt="${BASE_DIR}/nginx/certbot/live/${domain}/fullchain.pem"
    local key="${BASE_DIR}/nginx/certbot/live/${domain}/privkey.pem"
    local has_cert="false"
    [[ -f "$crt" && -f "$key" ]] && has_cert="true"

    if [[ "$has_cert" == "true" ]]; then
      # HTTP solo mantiene disponible el desafío ACME y redirige el tráfico real a HTTPS.
      cat >> "$tmp" <<EOF
server {
    listen 80;
    server_name ${hosts};
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
        try_files \$uri =404;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

      if [[ "$tipo" == "redirect" ]]; then
        cat >> "$tmp" <<EOF
server {
    listen 443 ssl;
    http2 on;
    server_name ${hosts};
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
        try_files \$uri =404;
    }
    location / {
        return 301 ${ref}\$request_uri;
    }
}
EOF
      else
        cat >> "$tmp" <<EOF
server {
    listen 443 ssl;
    http2 on;
    server_name ${hosts};
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    location / {
        proxy_pass http://${backend}:${port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF
      fi
    else
      # Antes de emitir: HTTP accesible para HTTP-01 y backend/redirect funcional.
      if [[ "$tipo" == "redirect" ]]; then
        cat >> "$tmp" <<EOF
server {
    listen 80;
    server_name ${hosts};
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
        try_files \$uri =404;
    }
    location / {
        return 301 ${ref}\$request_uri;
    }
}
EOF
      else
        cat >> "$tmp" <<EOF
server {
    listen 80;
    server_name ${hosts};
    location /.well-known/acme-challenge/ {
        root /usr/share/nginx/html;
        try_files \$uri =404;
    }
    location / {
        proxy_pass http://${backend}:${port};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
    }
}
EOF
      fi
    fi
  done < "$STATE_FILE"

  cat >> "$tmp" <<'EOF'
server {
    listen 80 default_server;
    server_name _;
    location /.well-known/acme-challenge/ { root /usr/share/nginx/html; try_files $uri =404; }
    return 444;
}
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/certs/default.crt;
    ssl_certificate_key /etc/nginx/certs/default.key;
    return 444;
}
EOF

  mv -f "$tmp" "$out"
}
# Certificado autofirmado solo para el default_server de 443. Nunca se utiliza
# como certificado de una publicación real.
ensure_default_cert() {
  mkdir -p "${BASE_DIR}/nginx/certs"
  if [[ ! -f "${BASE_DIR}/nginx/certs/default.crt" || ! -f "${BASE_DIR}/nginx/certs/default.key" ]]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 2 \
      -subj "/CN=nginx-default.invalid" \
      -keyout "${BASE_DIR}/nginx/certs/default.key" \
      -out "${BASE_DIR}/nginx/certs/default.crt" >/dev/null 2>&1
    chmod 600 "${BASE_DIR}/nginx/certs/default.key"
  fi
}

cleanup_domain_artifacts() {
  local HOSTS="$1"
  local d
  local _domains
  IFS=',' read -ra _domains <<< "$HOSTS"

  for d in "${_domains[@]}"; do
    d="$(echo "$d" | xargs)"
    [[ -z "$d" ]] && continue

    local HOST_IN_USE=""
    HOST_IN_USE="$(awk -F '\t' -v host="$d" -v current="${APP_ID:-}" '
      $1 != current {
        if ($2 == host) { print "yes"; exit }
        n = split($6, a, ",")
        for (i = 1; i <= n; i++) {
          gsub(/^ +| +$/, "", a[i])
          if (a[i] == host) { print "yes"; exit }
        }
      }
    ' "$STATE_FILE" 2>/dev/null || true)"
    if [[ "$HOST_IN_USE" == "yes" ]]; then
      log_warn "'${d}' todavía aparece en otra publicación; se conserva su certificado/configuración."
      continue
    fi

    log_info "Limpiando certificado y configuración de '${d}'..."
    certbot_run delete --cert-name "$(certbot_cert_name "$d")" --non-interactive >/dev/null 2>&1 || true
    rm -f \
      "${BASE_DIR}/nginx/certs/${d}.crt" \
      "${BASE_DIR}/nginx/certs/${d}.key" \
      "${BASE_DIR}/nginx/certs/${d}.chain.pem" \
      "${BASE_DIR}/nginx/certs/${d}.fullchain.pem" \
      "${BASE_DIR}/nginx/certs/${d}.dhparam.pem" 2>/dev/null || true
    rm -f \
      "${BASE_DIR}/nginx/vhost.d/${d}" \
      "${BASE_DIR}/nginx/vhost.d/${d}.conf" 2>/dev/null || true
  done

  generate_nginx_config
  reload_nginx || true
}

issue_certificate() {
  local domain="$1" aliases="$2" email="$3"
  local hosts; hosts="$(all_hosts "$domain" "$aliases")"
  local args=()
  IFS=',' read -ra _hs <<< "$hosts"
  local h
  for h in "${_hs[@]}"; do
    h="$(echo "$h" | xargs)"
    [[ -n "$h" ]] && args+=( -d "$h" )
  done

  log_info "Solicitando certificado para: ${hosts}"
  
  # Forzamos la creación del archivo de credenciales aquí mismo para evitar errores si el usuario salta la instalación
  if [[ -n "${DEFAULT_CF_TOKEN}" ]]; then
    mkdir -p "$(dirname "$CF_CRED_FILE")"
    echo "dns_cloudflare_api_token = ${DEFAULT_CF_TOKEN}" > "$CF_CRED_FILE"
    chmod 600 "$CF_CRED_FILE"
  fi

  local cert_cmd=(
    "certonly"
    "${args[@]}"
    "--email" "$email"
    "--agree-tos"
    "--non-interactive"
    "--keep-until-expiring"
    "--no-eff-email"
  )

  if [[ -f "$CF_CRED_FILE" ]]; then
    log_info "Token de Cloudflare detectado. Usando validación DNS-01..."
    cert_cmd+=(
      "--dns-cloudflare"
      "--dns-cloudflare-credentials" "/etc/letsencrypt/cloudflare.ini"
      "--dns-cloudflare-propagation-seconds" "20"
    )
  else
    log_info "Usando validación HTTP-01 (Requiere nube gris en Cloudflare)..."
    cert_cmd+=(
      "--webroot"
      "-w" "/var/www/certbot"
    )
  fi

  certbot_run "${cert_cmd[@]}" 
}

# ============================================================================
# COMANDO: install
# ============================================================================
cmd_install() {
  local LE_EMAIL=""
  local OPTIND opt
  local CF_TOKEN="${DEFAULT_CF_TOKEN}"
  while getopts ":e:b:t:h" opt; do
    case "$opt" in
      e) LE_EMAIL="$OPTARG" ;;
      b) BASE_DIR="$OPTARG" ;;
      t) CF_TOKEN="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 install -e <email-letsencrypt> [-t <cloudflare_token>] [-b <directorio-base>]
  -e   Email por defecto para el registro ACME de Let's Encrypt (obligatorio)
  -t   Token de API de Cloudflare para validación DNS (opcional pero recomendado)
  -b   Directorio base de instalación (default: /opt/reverse-proxy)
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done

  [[ -z "$LE_EMAIL" ]] && die "Debes indicar -e <email>. Usa: $0 install -h"
  require_root
  [[ -f /etc/os-release ]] || die "No se pudo detectar la distribución (/etc/os-release no existe)."
  . /etc/os-release
  local DISTRO_ID="${ID:-unknown}"
  log_info "Distribución detectada: $DISTRO_ID"

  if command -v docker &>/dev/null; then
    log_ok "Docker ya está instalado ($(docker --version))."
  else
    log_info "Instalando Docker Engine..."
    case "$DISTRO_ID" in
      ubuntu|debian)
        apt-get update -y
        apt-get install -y ca-certificates curl gnupg openssl
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        local ARCH CODENAME
        ARCH="$(dpkg --print-architecture)"
        CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
        echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
      rhel|centos|rocky|almalinux|fedora)
        local PKG_MGR="dnf"; command -v dnf &>/dev/null || PKG_MGR="yum"
        $PKG_MGR install -y yum-utils openssl
        $PKG_MGR config-manager --add-repo https://download.docker.com/linux/${DISTRO_ID}/docker-ce.repo 2>/dev/null \
          || $PKG_MGR config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
      *) die "Distribución no soportada automáticamente: $DISTRO_ID. Instala Docker manualmente." ;;
    esac
    systemctl enable --now docker
    log_ok "Docker instalado correctamente."
  fi

  docker compose version &>/dev/null || die "El plugin 'docker compose' (v2) no está disponible."
  docker info &>/dev/null || die "Docker no está operativo."

  log_info "Creando estructura de directorios en ${BASE_DIR}..."
  mkdir -p "${BASE_DIR}/nginx/certs" "${BASE_DIR}/nginx/conf.d" "${BASE_DIR}/nginx/vhost.d" \
           "${BASE_DIR}/nginx/html/.well-known/acme-challenge" "${BASE_DIR}/nginx/certbot" \
           "${BASE_DIR}/nginx/logs" "${BASE_DIR}/apps" "${BASE_DIR}/.state"
  ensure_state_file
  echo "$LE_EMAIL" > "${BASE_DIR}/.state/default_email"
  ensure_default_cert

  if [[ -n "$CF_TOKEN" ]]; then
    log_info "Guardando credenciales de Cloudflare en $CF_CRED_FILE..."
    echo "dns_cloudflare_api_token = ${CF_TOKEN}" > "$CF_CRED_FILE"
    chmod 600 "$CF_CRED_FILE"
    log_ok "Token configurado. Certbot usará validación DNS-01."
  fi

  if docker network inspect "${NETWORK_NAME}" &>/dev/null; then
    log_ok "La red '${NETWORK_NAME}' ya existe."
  else
    log_info "Creando red Docker externa '${NETWORK_NAME}'..."
    docker network create "${NETWORK_NAME}"
  fi

  # Migración segura desde una instalación anterior con acme-companion.
  # Solo se retira el contenedor obsoleto; no se toca ninguna app ni volumen.
  if docker inspect nginx-proxy-acme >/dev/null 2>&1; then
    log_info "Retirando el contenedor antiguo 'nginx-proxy-acme'..."
    docker rm -f nginx-proxy-acme >/dev/null 2>&1 || true
  fi

  log_info "Generando docker-compose.yml de NGINX + almacenamiento Certbot..."
  cat > "${BASE_DIR}/docker-compose.yml" <<EOF
services:
  nginx-proxy:
    image: ${NGINX_IMAGE}
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    networks:
      - ${NETWORK_NAME}
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/certs:/etc/nginx/certs:ro
      - ./nginx/certbot:/etc/letsencrypt:ro
      - ./nginx/html:/usr/share/nginx/html:ro
      - ./nginx/logs:/var/log/nginx

networks:
  ${NETWORK_NAME}:
    external: true
EOF

  generate_nginx_config
  log_info "Levantando NGINX..."
  (cd "${BASE_DIR}" && docker compose up -d)
  sleep 2
  reload_nginx
  setup_renewal_timer

  docker run --rm "${CERTBOT_IMAGE}" --version
  log_ok "¡Proxy inverso NGINX instalado y corriendo!"
  echo
  echo "--------------------------------------------------------------"
  echo " Directorio de instalación : ${BASE_DIR}"
  echo " Red Docker compartida     : ${NETWORK_NAME}"
  echo " Email Let's Encrypt       : ${LE_EMAIL}"
  echo " Emisor ACME               : Certbot (${CERTBOT_IMAGE})"
  echo "--------------------------------------------------------------"
  echo
  echo "Siguiente paso: sudo $0 add -n <app> -H <dominio> -p <puerto> -m <email> -i <imagen>"
}

# ============================================================================
# COMANDO: add
# ============================================================================
cmd_add() {
  local APP_NAME="" DOMAIN="" PORT="" IMAGE="" EXISTING_CONTAINER="" LE_EMAIL="" ALIASES=""
  local OPTIND opt
  while getopts ":n:H:p:m:i:c:a:h" opt; do
    case "$opt" in
      n) APP_NAME="$OPTARG" ;;
      H) DOMAIN="$OPTARG" ;;
      p) PORT="$OPTARG" ;;
      m) LE_EMAIL="$OPTARG" ;;
      i) IMAGE="$OPTARG" ;;
      c) EXISTING_CONTAINER="$OPTARG" ;;
      a) ALIASES="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 add -n <app> -H <dominio> -p <puerto> [-m <email>] [-a <alias1,alias2,...>] (-i <imagen> | -c <contenedor-existente>)
  -n   Nombre corto/identificador de la app
  -H   Dominio o subdominio PRINCIPAL
  -p   Puerto interno del backend
  -m   Email para Let's Encrypt (opcional; usa el de install si se omite)
  -a   Dominios/subdominios ADICIONALES separados por coma. Se incluyen como SAN.
  -i   Imagen Docker a desplegar (crea un contenedor nuevo)
  -c   Nombre de un contenedor Docker YA EXISTENTE a conectar a la red proxy
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done

  [[ -z "$APP_NAME" ]] && die "Falta -n (nombre de app). Usa: $0 add -h"
  [[ -z "$DOMAIN" ]] && die "Falta -H (dominio). Usa: $0 add -h"
  [[ -z "$PORT" ]] && die "Falta -p (puerto). Usa: $0 add -h"
  [[ -n "$IMAGE" && -n "$EXISTING_CONTAINER" ]] && die "Indica solo -i o -c, no ambos."
  [[ -z "$IMAGE" && -z "$EXISTING_CONTAINER" ]] && die "Debes indicar -i (imagen) o -c (contenedor existente)."
  require_root
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no está instalado. Ejecuta primero: sudo $0 install -e <email>"
  docker network inspect "${NETWORK_NAME}" &>/dev/null || die "La red '${NETWORK_NAME}' no existe. Ejecuta 'install' primero."

  if [[ -z "$LE_EMAIL" ]]; then
    [[ -f "${BASE_DIR}/.state/default_email" ]] || die "No hay email por defecto. Indícalo con -m."
    LE_EMAIL="$(cat "${BASE_DIR}/.state/default_email")"
    log_info "Usando email por defecto de la instalación: ${LE_EMAIL}"
  fi

  local _domain_regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$'
  [[ "$DOMAIN" =~ $_domain_regex ]] || die "El dominio '${DOMAIN}' no tiene un formato válido."
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "El puerto '${PORT}' debe ser numérico."

  local ALL_HOSTS="$DOMAIN"
  if [[ -n "$ALIASES" ]]; then
    IFS=',' read -ra _alias_arr <<< "$ALIASES"
    for a in "${_alias_arr[@]}"; do
      a="$(echo "$a" | xargs)"
      [[ -z "$a" ]] && continue
      [[ "$a" =~ $_domain_regex ]] || die "El alias '${a}' no tiene un formato de dominio válido."
      [[ "$a" == "$DOMAIN" ]] && die "El alias '${a}' duplica el dominio principal."
      ALL_HOSTS="${ALL_HOSTS},${a}"
    done
  fi

  local APP_ID
  APP_ID="$(echo "${APP_NAME}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
  [[ -z "$APP_ID" ]] && die "El nombre de app resultó vacío tras sanitizar."
  [[ -n "$(state_get "$APP_ID")" ]] && die "Ya existe una app registrada con el id '${APP_ID}'. Usa 'remove' primero o elige otro nombre."

  # Evita reutilizar un dominio/alias que ya pertenece a otra publicación.
  while IFS=$'\t' read -r id domain port tipo ref aliases; do
    [[ -z "$id" ]] && continue
    local existing_hosts="$(all_hosts "$domain" "$aliases")"
    IFS=',' read -ra eh <<< "$existing_hosts"
    IFS=',' read -ra nh <<< "$ALL_HOSTS"
    for x in "${eh[@]}"; do for y in "${nh[@]}"; do
      [[ "$(echo "$x" | xargs)" == "$(echo "$y" | xargs)" ]] && die "El dominio '${y}' ya está asignado a la app '${id}'."
    done; done
  done < "$STATE_FILE"

  local APP_DIR="${BASE_DIR}/apps/${APP_ID}"
  mkdir -p "$APP_DIR"

  if [[ -n "$EXISTING_CONTAINER" ]]; then
    docker inspect "$EXISTING_CONTAINER" &>/dev/null || die "El contenedor '${EXISTING_CONTAINER}' no existe."
    log_info "Conectando '${EXISTING_CONTAINER}' a la red '${NETWORK_NAME}'..."
    docker network connect "${NETWORK_NAME}" "${EXISTING_CONTAINER}" 2>/dev/null || true
    state_add "$APP_ID" "$DOMAIN" "$PORT" "existente" "$EXISTING_CONTAINER" "${ALIASES:--}"
  else
    cat > "${APP_DIR}/docker-compose.yml" <<EOF
services:
  ${APP_ID}:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    networks:
      - ${NETWORK_NAME}
networks:
  ${NETWORK_NAME}:
    external: true
EOF
    log_info "Levantando el contenedor '${APP_ID}'..."
    (cd "$APP_DIR" && docker compose up -d)
    state_add "$APP_ID" "$DOMAIN" "$PORT" "nuevo" "$IMAGE" "${ALIASES:--}"
  fi

  generate_nginx_config
  reload_nginx
  log_info "Esperando a que el backend sea accesible antes del desafío ACME..."
  sleep 2
  if ! issue_certificate "$DOMAIN" "$ALIASES" "$LE_EMAIL"; then
    log_err "Certbot no pudo emitir el certificado. El backend y la publicación se conservan."
    generate_nginx_config
    reload_nginx || true
    return 1
  fi

  generate_nginx_config
  reload_nginx
  log_ok "Dominio '${ALL_HOSTS}' publicado mediante HTTPS sin puerto."
  log_ok "NGINX recibe 80/443 y reenvía internamente a '${EXISTING_CONTAINER:-$APP_ID}:${PORT}'."
  echo "URL pública: https://${DOMAIN}/"
  echo "El certificado SSL es administrado por Certbot y Let's Encrypt."
}

# ============================================================================
# COMANDO: remove
# ============================================================================
cmd_remove() {
  local APP_NAME=""
  local OPTIND opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) APP_NAME="$OPTARG" ;;
      h) echo "Uso: sudo $0 remove -n <app>"; exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done
  [[ -z "$APP_NAME" ]] && die "Falta -n (nombre de app). Usa: $0 remove -h"
  require_root

  local APP_ID; APP_ID="$(echo "${APP_NAME}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
  local RECORD; RECORD="$(state_get "$APP_ID")"
  [[ -z "$RECORD" ]] && die "No hay ninguna app registrada con id '${APP_ID}'. Usa: $0 list"

  local APP_DIR="${BASE_DIR}/apps/${APP_ID}"
  local TIPO; TIPO="$(echo "$RECORD" | cut -f4)"
  local DOMAIN; DOMAIN="$(echo "$RECORD" | cut -f2)"
  local ALIASES; ALIASES="$(echo "$RECORD" | cut -f6)"
  local HOSTS="$DOMAIN"
  [[ -n "$ALIASES" && "$ALIASES" != "-" ]] && HOSTS="${HOSTS},${ALIASES}"

  if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
    if [[ "$TIPO" == "nuevo" ]]; then
      log_info "Deteniendo y eliminando el contenedor '${APP_ID}'..."
      (cd "$APP_DIR" && docker compose down -v) || log_warn "No se pudo bajar limpiamente; continúo con la limpieza."
    elif [[ "$TIPO" == "redirect" ]]; then
      log_info "La redirección se gestiona directamente desde NGINX; no se elimina ningún backend existente."
      (cd "$APP_DIR" && docker compose down -v) || true
    else
      local CONTENEDOR; CONTENEDOR="$(echo "$RECORD" | cut -f5)"
      log_warn "El contenedor original '${CONTENEDOR}' NO será eliminado ni recreado."
      log_info "Desconectando '${CONTENEDOR}' de la red '${NETWORK_NAME}'..."
      docker network disconnect "${NETWORK_NAME}" "$CONTENEDOR" 2>/dev/null || true
    fi
  elif [[ "$TIPO" == "existente" ]]; then
    local CONTENEDOR; CONTENEDOR="$(echo "$RECORD" | cut -f5)"
    docker network disconnect "${NETWORK_NAME}" "$CONTENEDOR" 2>/dev/null || true
  fi

  state_remove_silent "$APP_ID"
  cleanup_domain_artifacts "$HOSTS"
  rm -rf "$APP_DIR"

  log_ok "Publicación '${APP_ID}' eliminada completamente del proxy."
  log_ok "Dominio(s) liberado(s): ${HOSTS}"
  [[ "$TIPO" == "existente" ]] && log_ok "El contenedor original se conserva intacto, junto con sus datos."
  log_ok "El dominio puede volver a utilizarse."
}

# ============================================================================
# COMANDOS: list / status / logs
# ============================================================================
cmd_list() {
  ensure_state_file
  if [[ ! -s "$STATE_FILE" ]]; then
    log_info "No hay apps publicadas todavía. Usa: $0 add -h"
    return 0
  fi
  printf "%-15s %-30s %-8s %-10s %-20s %s\n" "APP" "DOMINIO" "PUERTO" "TIPO" "REFERENCIA" "ALIASES"
  printf "%-15s %-30s %-8s %-10s %-20s %s\n" "---" "-------" "------" "----" "----------" "-------"
  while IFS=$'\t' read -r id domain port tipo ref aliases; do
    printf "%-15s %-30s %-8s %-10s %-20s %s\n" "$id" "$domain" "$port" "$tipo" "$ref" "${aliases:--}"
  done < "$STATE_FILE"
}

cmd_status() {
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no está instalado."
  log_info "Estado del contenedor NGINX:"
  docker ps --filter "name=^/nginx-proxy$" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  log_info "Estado de las apps publicadas:"
  ensure_state_file
  if [[ ! -s "$STATE_FILE" ]]; then echo "  (ninguna)"; return 0; fi
  while IFS=$'\t' read -r id domain port tipo ref aliases; do
    local cname="$id"
    [[ "$tipo" == "existente" ]] && cname="$ref"
    if [[ "$tipo" == "redirect" ]]; then
      printf "  %-15s %-35s -> %s\n" "$id" "$domain" "redirect NGINX"
    elif docker inspect "$cname" &>/dev/null; then
      local st; st="$(docker inspect -f '{{.State.Status}}' "$cname")"
      printf "  %-15s %-35s -> %s\n" "$id" "$domain" "$st"
    else
      printf "  %-15s %-35s -> %s\n" "$id" "$domain" "contenedor no encontrado"
    fi
  done < "$STATE_FILE"
}

cmd_logs() {
  local TARGET="proxy"
  local OPTIND opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) TARGET="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 logs [-n proxy|certbot|<app>]
  -n   'proxy' (default), 'certbot' o id de app
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done
  case "$TARGET" in
    proxy) docker logs -f --tail 100 nginx-proxy ;;
    certbot)
      local logfile="${BASE_DIR}/nginx/logs/letsencrypt.log"
      [[ -f "$logfile" ]] || die "Todavía no existe el log de Certbot en ${logfile}."
      tail -f "$logfile" ;;
    *)
      local RECORD; RECORD="$(state_get "$TARGET")"
      [[ -z "$RECORD" ]] && die "No hay app '${TARGET}' registrada. Usa: $0 list"
      local tipo cname; tipo="$(echo "$RECORD" | cut -f4)"; cname="$TARGET"
      [[ "$tipo" == "existente" ]] && cname="$(echo "$RECORD" | cut -f5)"
      docker logs -f --tail 100 "$cname"
      ;;
  esac
}

# ============================================================================
# COMANDOS: certs / renew
# ============================================================================
cmd_certs() {
  local TARGET="all"
  local OPTIND opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) TARGET="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 certs [-n <app>|all]
  -n   id de una app publicada, o 'all' (default)
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done
  [[ -d "${BASE_DIR}/nginx/certbot" ]] || die "El proxy no está instalado."
  ensure_state_file

  _print_cert_row() {
    local domain="$1"
    local crt="${BASE_DIR}/nginx/certbot/live/${domain}/fullchain.pem"
    [[ -f "$crt" ]] || { printf "  %-35s %s\n" "$domain" "certificado no encontrado (¿aún emitiéndose o falló?)"; return; }
    local end_date; end_date="$(openssl x509 -enddate -noout -in "$crt" 2>/dev/null | cut -d= -f2)"
    [[ -n "$end_date" ]] || { printf "  %-35s %s\n" "$domain" "no se pudo leer el certificado"; return; }
    local end_epoch now_epoch days_left
    end_epoch="$(date -d "$end_date" +%s 2>/dev/null || echo 0)"; now_epoch="$(date +%s)"
    days_left=$(( (end_epoch - now_epoch) / 86400 ))
    if (( days_left < 0 )); then printf "  %-35s VENCIDO (%s)\n" "$domain" "$end_date"
    elif (( days_left < 15 )); then printf "  %-35s ${C_WARN}vence en %s días${C_RESET} (%s)\n" "$domain" "$days_left" "$end_date"
    else printf "  %-35s ${C_OK}vence en %s días${C_RESET} (%s)\n" "$domain" "$days_left" "$end_date"; fi
  }

  if [[ "$TARGET" == "all" ]]; then
    [[ -s "$STATE_FILE" ]] || { log_info "No hay apps publicadas todavía."; return 0; }
    log_info "Estado de certificados:"
    while IFS=$'\t' read -r id domain port tipo ref aliases; do _print_cert_row "$domain"; done < "$STATE_FILE"
  else
    local APP_ID; APP_ID="$(echo "${TARGET}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
    local RECORD; RECORD="$(state_get "$APP_ID")"; [[ -n "$RECORD" ]] || die "No hay app '${APP_ID}' registrada. Usa: $0 list"
    local domain; domain="$(echo "$RECORD" | cut -f2)"
    log_info "Estado de certificado para '${APP_ID}' (${domain}):"; _print_cert_row "$domain"
  fi
}

cmd_renew() {
  local TARGET=""
  local OPTIND opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) TARGET="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 renew -n <app>|all
  -n   id de una app publicada, o 'all' para renovar certificados administrados por Certbot
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done
  [[ -n "$TARGET" ]] || die "Falta -n <app>|all. Usa: $0 renew -h"
  require_root
  [[ -d "${BASE_DIR}/nginx/certbot" ]] || die "El proxy no está instalado."

  if [[ "$TARGET" == "all" ]]; then
    log_info "Forzando renovación de certificados administrados por Certbot..."
    certbot_run renew --non-interactive --force-renewal
  else
    local APP_ID; APP_ID="$(echo "${TARGET}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
    local RECORD; RECORD="$(state_get "$APP_ID")"; [[ -n "$RECORD" ]] || die "No hay app '${APP_ID}' registrada. Usa: $0 list"
    local domain; domain="$(echo "$RECORD" | cut -f2)"
    log_info "Forzando renovación de '${domain}'..."
    certbot_run renew --cert-name "$(certbot_cert_name "$domain")" --force-renewal --non-interactive
  fi

  generate_nginx_config
  reload_nginx
  log_ok "Renovación/proceso de certificados completado y NGINX recargado."
}

# Renovación automática equivalente a la función del acme-companion.
setup_renewal_timer() {
  local runner="/usr/local/sbin/reverse-proxy-certbot-renew"
  local timer="/etc/systemd/system/reverse-proxy-certbot-renew.service"
  local unit="/etc/systemd/system/reverse-proxy-certbot-renew.timer"

  cat > "$runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail
docker run --rm \
  -v "${BASE_DIR}/nginx/certbot:/etc/letsencrypt" \
  -v "${BASE_DIR}/nginx/html:/var/www/certbot" \
  -v "${BASE_DIR}/nginx/logs:/var/log/letsencrypt" \
  "${CERTBOT_IMAGE}" renew --non-interactive
if docker inspect nginx-proxy >/dev/null 2>&1; then
  docker exec nginx-proxy nginx -t
  docker exec nginx-proxy nginx -s reload
fi
EOF
  chmod 755 "$runner"

  cat > "$timer" <<EOF
[Unit]
Description=Renovacion de certificados Certbot para reverse-proxy
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=${runner}
EOF
  cat > "$unit" <<EOF
[Unit]
Description=Timer de renovacion Certbot para reverse-proxy

[Timer]
OnCalendar=*-*-* 00,12:00:00
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now reverse-proxy-certbot-renew.timer
  log_ok "Renovación automática configurada con systemd timer."
}

# ============================================================================
# COMANDO: redirect
# ============================================================================
cmd_redirect() {
  local APP_NAME="" DOMAIN="" TARGET_URL="" LE_EMAIL=""
  local OPTIND opt
  while getopts ":n:H:t:m:h" opt; do
    case "$opt" in
      n) APP_NAME="$OPTARG" ;;
      H) DOMAIN="$OPTARG" ;;
      t) TARGET_URL="$OPTARG" ;;
      m) LE_EMAIL="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 redirect -n <app> -H <dominio-origen> -t <url-destino> [-m <email>]
  -n   Nombre corto/identificador
  -H   Dominio o subdominio que va a redirigir
  -t   URL completa de destino
  -m   Email para Let's Encrypt (opcional; usa el de install si se omite)
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done
  [[ -z "$APP_NAME" ]] && die "Falta -n (nombre de app). Usa: $0 redirect -h"
  [[ -z "$DOMAIN" ]] && die "Falta -H (dominio origen). Usa: $0 redirect -h"
  [[ -z "$TARGET_URL" ]] && die "Falta -t (URL destino). Usa: $0 redirect -h"
  [[ "$TARGET_URL" =~ ^https?:// ]] || die "La URL destino debe comenzar por http:// o https://"
  [[ "$TARGET_URL" != *$'\n'* && "$TARGET_URL" != *$'\r'* && "$TARGET_URL" != *';'* && "$TARGET_URL" != *'{'* && "$TARGET_URL" != *'}'* ]] || die "La URL destino contiene caracteres no permitidos."
  require_root
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no está instalado."

  if [[ -z "$LE_EMAIL" ]]; then
    [[ -f "${BASE_DIR}/.state/default_email" ]] || die "No se indicó -m y no hay email por defecto."
    LE_EMAIL="$(cat "${BASE_DIR}/.state/default_email")"
  fi
  local _domain_regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$'
  [[ "$DOMAIN" =~ $_domain_regex ]] || die "El dominio '${DOMAIN}' no tiene un formato válido."
  local APP_ID; APP_ID="$(echo "${APP_NAME}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
  [[ -n "$APP_ID" ]] || die "El nombre de app resultó vacío tras sanitizar."
  [[ -z "$(state_get "$APP_ID")" ]] || die "Ya existe una app/registro con el id '${APP_ID}'. Usa 'remove' primero."

  state_add "$APP_ID" "$DOMAIN" "80" "redirect" "$TARGET_URL" "-"
  generate_nginx_config
  reload_nginx
  if ! issue_certificate "$DOMAIN" "-" "$LE_EMAIL"; then
    state_remove_silent "$APP_ID"
    generate_nginx_config
    reload_nginx || true
    die "No se pudo emitir el certificado para '${DOMAIN}'."
  fi
  generate_nginx_config
  reload_nginx
  log_ok "Listo. Todo el tráfico a '${DOMAIN}' será redirigido (301) a '${TARGET_URL}'."
  echo "El certificado SSL para '${DOMAIN}' es gestionado por Certbot."
}

# ============================================================================
# COMANDO: uninstall
# ============================================================================
cmd_uninstall() {
  require_root
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no parece estar instalado en ${BASE_DIR}."
  log_warn "Esto detendrá y eliminará NGINX."
  log_warn "Las apps publicadas (en ${BASE_DIR}/apps) NO se eliminan."
  read -r -p "¿Continuar? [y/N]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { log_info "Cancelado."; exit 0; }
  systemctl disable --now reverse-proxy-certbot-renew.timer 2>/dev/null || true
  rm -f /etc/systemd/system/reverse-proxy-certbot-renew.timer /etc/systemd/system/reverse-proxy-certbot-renew.service
  systemctl daemon-reload
  (cd "${BASE_DIR}" && docker compose down)
  log_ok "NGINX detenido y contenedor eliminado. Los certificados/configuración siguen en ${BASE_DIR}."
}

# ============================================================================
# MODO INTERACTIVO
# ============================================================================
_pause() { read -rp "Presiona Enter para continuar..." _ ; }

_run_safe() {
  ( "$@" )
  local rc=$?
  if [[ $rc -ne 0 ]]; then log_warn "La operación terminó con errores (código $rc)."; fi
  return 0
}

interactive_menu() {
  while true; do
    echo
    echo "================================================================"
    echo "   Administrador de Reverse Proxy NGINX + Docker + Certbot"
    echo "================================================================"
    echo "  1) Instalar el proxy (primera vez)"
    echo "  2) Agregar dominio/subdominio (nuevo contenedor o existente)"
    echo "  3) Crear una redirección (dominio -> URL)"
    echo "  4) Listar apps/dominios publicados"
    echo "  5) Ver estado de los contenedores"
    echo "  6) Ver logs (proxy, certbot o una app)"
    echo "  7) Ver estado de certificados SSL"
    echo "  8) Forzar renovación de certificado(s)"
    echo "  9) Eliminar una app/redirección"
    echo " 10) Desinstalar el proxy"
    echo "  0) Salir"
    echo "----------------------------------------------------------------"
    read -rp "Elige una opción: " OPT
    echo

    case "$OPT" in
      1)
        read -rp "Email para Let's Encrypt (obligatorio): " EMAIL
        [[ -z "$EMAIL" ]] && { log_warn "El email es obligatorio."; _pause; continue; }
        read -rp "Directorio base [Enter = ${BASE_DIR}]: " BDIR
        read -rp "Token API Cloudflare (Enter para usar el token integrado): " TOKEN_CF
        [[ -z "$TOKEN_CF" ]] && TOKEN_CF="$DEFAULT_CF_TOKEN"
        ARGS=(-e "$EMAIL"); [[ -n "$BDIR" ]] && ARGS+=(-b "$BDIR")
        [[ -n "$TOKEN_CF" ]] && ARGS+=(-t "$TOKEN_CF")
        _run_safe cmd_install "${ARGS[@]}"
        ;;
      2)
        read -rp "Nombre corto de la app (ej: blog, api): " APP_N
        read -rp "Dominio/subdominio principal (ej: blog.midominio.com): " DOM
        read -rp "Puerto interno del contenedor (ej: 80, 3000): " PRT
        read -rp "Email Let's Encrypt [Enter = usar el de install]: " MAIL
        read -rp "Alias adicionales separados por coma [Enter = ninguno]: " ALIAS
        echo "¿El backend es...?"
        echo "  a) Un contenedor NUEVO (a partir de una imagen)"
        echo "  b) Un contenedor YA EXISTENTE"
        read -rp "Elige a/b: " TIPO_SEL
        ARGS=(-n "$APP_N" -H "$DOM" -p "$PRT")
        [[ -n "$MAIL" ]] && ARGS+=(-m "$MAIL")
        [[ -n "$ALIAS" ]] && ARGS+=(-a "$ALIAS")
        if [[ "$TIPO_SEL" == "a" ]]; then
          read -rp "Imagen Docker (ej: wordpress:latest): " IMG; ARGS+=(-i "$IMG")
        elif [[ "$TIPO_SEL" == "b" ]]; then
          read -rp "Nombre del contenedor existente: " CONT; ARGS+=(-c "$CONT")
        else
          log_warn "Opción inválida."; _pause; continue
        fi
        _run_safe cmd_add "${ARGS[@]}"
        ;;
      3)
        read -rp "Nombre corto de la redirección (ej: old-blog): " APP_N
        read -rp "Dominio de origen (ej: viejo.midominio.com): " DOM
        read -rp "URL destino completa (ej: https://nuevo.midominio.com): " DEST
        read -rp "Email Let's Encrypt [Enter = usar el de install]: " MAIL
        ARGS=(-n "$APP_N" -H "$DOM" -t "$DEST"); [[ -n "$MAIL" ]] && ARGS+=(-m "$MAIL")
        _run_safe cmd_redirect "${ARGS[@]}"
        ;;
      4) _run_safe cmd_list ;;
      5) _run_safe cmd_status ;;
      6)
        read -rp "¿Logs de qué? [proxy/certbot/<id-de-app>] (Enter = proxy): " TARGET
        ARGS=(); [[ -n "$TARGET" ]] && ARGS+=(-n "$TARGET")
        echo "(Ctrl+C para dejar de ver los logs y volver al menú)"; _run_safe cmd_logs "${ARGS[@]}"
        ;;
      7)
        read -rp "¿Certificado de qué app? [Enter = todos]: " TARGET
        ARGS=(); [[ -n "$TARGET" ]] && ARGS+=(-n "$TARGET"); _run_safe cmd_certs "${ARGS[@]}"
        ;;
      8)
        read -rp "¿Renovar cuál app? (o escribe 'all' para todas): " TARGET
        [[ -z "$TARGET" ]] && { log_warn "Debes indicar una app o 'all'."; _pause; continue; }
        _run_safe cmd_renew -n "$TARGET"
        ;;
      9)
        read -rp "Id de la app/redirección a eliminar: " APP_N
        [[ -z "$APP_N" ]] && { log_warn "Debes indicar un id."; _pause; continue; }
        read -rp "¿Confirmas eliminar '${APP_N}'? [y/N]: " CONF
        [[ "$CONF" =~ ^[Yy]$ ]] || { log_info "Cancelado."; _pause; continue; }
        _run_safe cmd_remove -n "$APP_N"
        ;;
      10) _run_safe cmd_uninstall ;;
      0) log_info "Hasta luego."; exit 0 ;;
      *) log_warn "Opción no reconocida." ;;
    esac
    _pause
  done
}

# ============================================================================
# DISPATCH PRINCIPAL
# ============================================================================
if [[ $# -lt 1 ]]; then
  interactive_menu
  exit 0
fi

COMMAND="$1"; shift
case "$COMMAND" in
  install)   cmd_install "$@" ;;
  add)       cmd_add "$@" ;;
  remove)    cmd_remove "$@" ;;
  list)      cmd_list "$@" ;;
  status)    cmd_status "$@" ;;
  logs)      cmd_logs "$@" ;;
  certs)     cmd_certs "$@" ;;
  renew)     cmd_renew "$@" ;;
  redirect)  cmd_redirect "$@" ;;
  uninstall) cmd_uninstall "$@" ;;
  help|-h|--help) print_main_usage ;;
  *) log_err "Comando desconocido: '$COMMAND'"; echo; print_main_usage; exit 1 ;;
esac
