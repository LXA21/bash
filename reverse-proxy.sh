#!/usr/bin/env bash
###############################################################################
# reverse-proxy.sh
#
# Herramienta única de administración de un Reverse Proxy basado en NGINX
# (nginx-proxy + acme-companion) sobre Docker, para publicar múltiples
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
DOMAIN_STATE_FILE="${BASE_DIR}/.state/domains.tsv"   # zonas: raiz<TAB>proveedor<TAB>api_dns<TAB>id_config
ACME_USER_DATA="${BASE_DIR}/.state/letsencrypt_user_data"

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
# AYUDA GENERAL
# ============================================================================
print_main_usage() {
  cat <<EOF
reverse-proxy.sh — Administrador de Proxy Inverso NGINX sobre Docker

USO:
  sudo $0                    Modo interactivo: te pregunta todo paso a paso (recomendado)
  sudo $0 <comando> [opciones]   Modo directo, para scripts/automatización

COMANDOS:
  install     Instala Docker (si falta), la red compartida y el proxy (nginx-proxy + acme-companion)
  add         Publica un dominio/subdominio hacia un contenedor nuevo o existente (admite alias con -a)
  redirect    Crea una redirección 301 pura de un dominio hacia otra URL (sin backend real)
  remove      Elimina una app/redirección publicada previamente
  list        Lista las apps/dominios actualmente publicados
  status      Muestra el estado de los contenedores del proxy y de las apps
  logs        Muestra logs del proxy, del emisor de certificados, o de una app
  certs       Muestra el estado y fecha de vencimiento de los certificados wildcard por zona
  renew       Fuerza la renovación de un certificado wildcard por zona (o de todos)
  uninstall   Detiene y elimina completamente el proxy (no borra las apps)
  help        Muestra esta ayuda

Ejecuta 'sudo $0 <comando> -h' para ver las opciones de cada comando.

EJEMPLOS:
  sudo $0 install -e admin@midominio.com
  sudo $0 add -n blog -H blog.midominio.com -p 80 -m admin@midominio.com -i wordpress:latest
  sudo $0 add -n web  -H midominio.com -a www.midominio.com -p 80 -i mi-app:latest
  sudo $0 add -n api  -H api.midominio.com  -p 3000 -m admin@midominio.com -c mi-api-existente
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
# HELPERS DE ESTADO (registro de apps publicadas)
# ============================================================================
ensure_state_file() {
  mkdir -p "$(dirname "$STATE_FILE")"
  [[ -f "$STATE_FILE" ]] || touch "$STATE_FILE"
}

state_add() {
  # id, dominio, puerto, tipo(nuevo|existente|redirect), referencia(imagen|contenedor|destino), aliases(o "-")
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


# ============================================================================
# GESTIÓN AUTOMÁTICA DE DOMINIOS / DNS / WILDCARD
# ============================================================================
ensure_domain_state_file() {
  mkdir -p "$(dirname "$DOMAIN_STATE_FILE")"
  [[ -f "$DOMAIN_STATE_FILE" ]] || touch "$DOMAIN_STATE_FILE"
}

shell_quote() {
  printf "%q" "$1"
}

# Devuelve la zona DNS autoritativa más específica con SOA. Esto evita asumir
# que el dominio raíz siempre son las últimas dos etiquetas (co.uk, com.au, etc.).
detect_dns_zone() {
  local host="$1"
  host="${host%.}"
  local labels=() candidate i out old_ifs="$IFS"
  IFS='.' read -ra labels <<< "$host"
  for ((i=0; i<${#labels[@]}; i++)); do
    candidate="$(IFS='.'; printf '%s' "${labels[*]:i}")"
    if command -v dig >/dev/null 2>&1; then
      out="$(dig +short SOA "$candidate" 2>/dev/null || true)"
      if [[ -n "$out" ]]; then
        IFS="$old_ifs"
        printf '%s' "$candidate"
        return 0
      fi
    fi
  done
  IFS="$old_ifs"
  return 1
}

ensure_dns_tools() {
  if command -v dig >/dev/null 2>&1; then
    return 0
  fi
  log_info "No se encontró 'dig'. Instalando la herramienta DNS necesaria para detectar automáticamente la zona/proveedor..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 && apt-get install -y dnsutils >/dev/null 2>&1 && return 0
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y bind-utils >/dev/null 2>&1 && return 0
  elif command -v yum >/dev/null 2>&1; then
    yum install -y bind-utils >/dev/null 2>&1 && return 0
  fi
  return 1
}

detect_dns_provider() {
  local zone="$1" ns
  ns="$(dig +short NS "$zone" 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr '\n' ' ' || true)"
  [[ -n "$ns" ]] || { printf '%s' "unknown"; return 0; }
  case "$ns" in
    *cloudflare.com*) printf '%s' "cloudflare" ;;
    *dns-parking.com*|*hostinger.com*) printf '%s' "hostinger" ;;
    *domaincontrol.com*) printf '%s' "godaddy" ;;
    *registrar-servers.com*) printf '%s' "namecheap" ;;
    *awsdns-*) printf '%s' "route53" ;;
    *digitalocean.com*) printf '%s' "digitalocean" ;;
    *linode.com*|*linodeobjects.com*) printf '%s' "linode" ;;
    *hetzner.com*|*hetzner.de*) printf '%s' "hetznercloud" ;;
    *dnsimple.com*) printf '%s' "dnsimple" ;;
    *) printf '%s' "unknown" ;;
  esac
}

domain_state_get() {
  ensure_domain_state_file
  awk -F '\t' -v zone="$1" '$1 == zone {print; exit}' "$DOMAIN_STATE_FILE" 2>/dev/null || true
}

domain_state_add() {
  ensure_domain_state_file
  local zone="$1" provider="$2" dns_api="$3" cfg_id="$4"
  awk -F '\t' -v zone="$zone" '$1 != zone' "$DOMAIN_STATE_FILE" > "${DOMAIN_STATE_FILE}.tmp" 2>/dev/null || true
  printf "%s\t%s\t%s\t%s\n" "$zone" "$provider" "$dns_api" "$cfg_id" >> "${DOMAIN_STATE_FILE}.tmp"
  mv -f "${DOMAIN_STATE_FILE}.tmp" "$DOMAIN_STATE_FILE"
}

acme_cfg_escape() {
  # %q produce una representación segura para Bash, incluyendo comillas,
  # espacios, backslashes y caracteres especiales.
  printf "%q" "$1"
}

write_acme_user_data() {
  local zone="$1" provider="$2" dns_api="$3" email="$4" cfg_id="$5"
  shift 5
  local cfg_file="$ACME_USER_DATA"
  local tmp="${cfg_file}.tmp"
  ensure_domain_state_file
  mkdir -p "$(dirname "$cfg_file")"
  touch "$cfg_file"
  chmod 600 "$cfg_file"

  # Regenera el archivo completo desde domains.tsv + los bloques existentes.
  # Para no guardar secretos en domains.tsv, los bloques de configuración ACME
  # son conservados y el nuevo bloque se añade/actualiza por identificador.
  if [[ -f "$cfg_file" ]] && grep -q "^ACME_${cfg_id}_HOST=" "$cfg_file"; then
    return 0
  fi

  {
    if [[ ! -s "$cfg_file" ]]; then
      echo "# Generado automáticamente por reverse-proxy.sh. NO editar manualmente."
      echo "ACME_STANDALONE_CERTS=()"
    else
      cat "$cfg_file"
    fi
    echo ""
    echo "ACME_STANDALONE_CERTS+=("${cfg_id}")"
    printf "ACME_%s_HOST=('%s' '*.%s')\n" "$cfg_id" "$zone" "$zone"
    printf "ACME_%s_EMAIL=%s\n" "$cfg_id" "$(acme_cfg_escape "$email")"
    echo "ACME_${cfg_id}_CHALLENGE='DNS-01'"
    echo "declare -A ACMESH_${cfg_id}_DNS_API_CONFIG=("
    printf "  ['DNS_API']='%s'\n" "$dns_api"
    while (($#)); do
      local key="$1" value="$2"
      shift 2
      printf "  ['%s']=%s\n" "$key" "$(acme_cfg_escape "$value")"
    done
    echo ")"
  } > "$tmp"
  mv -f "$tmp" "$cfg_file"
  chmod 600 "$cfg_file"
}

setup_dns_credentials() {
  # Salida: variables globales DNS_API_NAME y DNS_CFG_KV (pares key/value).
  local zone="$1" detected="$2" provider="$2"
  local v1 v2 v3
  DNS_API_NAME=""
  DNS_CFG_KV=()

  if [[ "$provider" == "unknown" ]]; then
    echo
    log_warn "No pude identificar automáticamente el proveedor DNS de '${zone}'."
    echo "Proveedores detectables actualmente: Hostinger, Cloudflare, GoDaddy, Namecheap, AWS Route53, DigitalOcean, Linode, Hetzner Cloud y DNSimple."
    read -rp "Proveedor DNS [Enter = manual]: " provider
    provider="$(echo "$provider" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
    [[ -z "$provider" ]] && provider="manual"
  fi

  case "$provider" in
    hostinger)
      DNS_API_NAME="dns_hostinger"
      if [[ -n "${HOSTINGER_Token:-}" ]]; then v1="$HOSTINGER_Token"; else read -rsp "Token API de Hostinger (solo la primera vez): " v1; echo; fi
      [[ -n "$v1" ]] || die "El token de Hostinger es obligatorio para DNS-01 automático."
      DNS_CFG_KV=(HOSTINGER_Token "$v1")
      ;;
    cloudflare)
      DNS_API_NAME="dns_cf"
      if [[ -n "${CF_Token:-}" ]]; then v1="$CF_Token"; else read -rsp "Token API de Cloudflare (solo la primera vez): " v1; echo; fi
      [[ -n "$v1" ]] || die "El token de Cloudflare es obligatorio para DNS-01 automático."
      DNS_CFG_KV=(CF_Token "$v1")
      ;;
    godaddy)
      DNS_API_NAME="dns_gd"
      read -rp "API Key de GoDaddy (solo la primera vez): " v1
      read -rsp "API Secret de GoDaddy (solo la primera vez): " v2; echo
      [[ -n "$v1" && -n "$v2" ]] || die "La API Key y el Secret de GoDaddy son obligatorios."
      DNS_CFG_KV=(GD_Key "$v1" GD_Secret "$v2")
      ;;
    namecheap)
      DNS_API_NAME="dns_namecheap"
      read -rp "Username de Namecheap (solo la primera vez): " v1
      read -rsp "API Key de Namecheap (solo la primera vez): " v2; echo
      read -rp "IP pública autorizada en Namecheap (Enter = detectar): " v3
      if [[ -z "$v3" ]]; then v3="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"; fi
      [[ -n "$v1" && -n "$v2" && -n "$v3" ]] || die "Namecheap requiere username, API key e IP origen."
      DNS_CFG_KV=(NAMECHEAP_USERNAME "$v1" NAMECHEAP_API_KEY "$v2" NAMECHEAP_SOURCEIP "$v3")
      ;;
    route53)
      DNS_API_NAME="dns_aws"
      read -rp "AWS Access Key ID (Enter = usar IAM Role): " v1
      if [[ -n "$v1" ]]; then
        read -rsp "AWS Secret Access Key: " v2; echo
        [[ -n "$v2" ]] || die "El AWS Secret Access Key es obligatorio."
        DNS_CFG_KV=(AWS_ACCESS_KEY_ID "$v1" AWS_SECRET_ACCESS_KEY "$v2")
      else
        DNS_CFG_KV=()
      fi
      ;;
    digitalocean)
      DNS_API_NAME="dns_dgon"
      read -rsp "Token API de DigitalOcean (solo la primera vez): " v1; echo
      [[ -n "$v1" ]] || die "El token de DigitalOcean es obligatorio."
      DNS_CFG_KV=(DO_API_KEY "$v1")
      ;;
    linode)
      DNS_API_NAME="dns_linode"
      read -rsp "API Key de Linode (solo la primera vez): " v1; echo
      [[ -n "$v1" ]] || die "La API Key de Linode es obligatoria."
      DNS_CFG_KV=(LINODE_API_KEY "$v1" DNS_SLEEP "900")
      ;;
    hetznercloud)
      DNS_API_NAME="dns_hetznercloud"
      read -rsp "Token DNS de Hetzner Cloud (solo la primera vez): " v1; echo
      [[ -n "$v1" ]] || die "El token de Hetzner Cloud es obligatorio."
      DNS_CFG_KV=(HETZNER_TOKEN "$v1")
      ;;
    dnsimple)
      DNS_API_NAME="dns_dnsimple"
      read -rsp "OAuth Token de DNSimple (solo la primera vez): " v1; echo
      [[ -n "$v1" ]] || die "El token de DNSimple es obligatorio."
      DNS_CFG_KV=(DNSimple_OAUTH_TOKEN "$v1")
      ;;
    manual)
      die "El modo DNS manual no está habilitado en esta versión porque no permite renovación totalmente desatendida. Configura un proveedor con API compatible."
      ;;
    *)
      die "Proveedor DNS '${provider}' no soportado automáticamente todavía. Configura un proveedor con API compatible o añade su adaptador DNS."
      ;;
  esac
  DNS_PROVIDER="$provider"
}

ensure_wildcard_domain() {
  local host="$1" email="$2"
  ensure_domain_state_file
  mkdir -p "${BASE_DIR}/.state"
  ensure_dns_tools || die "No se pudo instalar 'dig'; no puedo detectar automáticamente la zona DNS."

  local zone record provider dns_api cfg_id
  DETECTED_DNS_ZONE=""
  zone="$(detect_dns_zone "$host" || true)"
  if [[ -z "$zone" ]]; then
    # Si el host ya es un dominio raíz, lo aceptamos como fallback.
    if [[ "$host" != *.*.* ]]; then
      zone="$host"
    else
      die "No pude detectar la zona DNS de '${host}'. Verifica que el DNS esté publicado o configura la zona manualmente."
    fi
  fi

  record="$(domain_state_get "$zone")"
  if [[ -n "$record" ]]; then
    log_ok "Zona DNS detectada automáticamente: ${zone}. Ya existe configuración; no se volverán a pedir credenciales."
    DETECTED_DNS_ZONE="$zone"
    return 0
  fi

  provider="$(detect_dns_provider "$zone")"
  log_info "Nueva zona detectada: ${zone}"
  log_info "Proveedor DNS detectado: ${provider}"

  setup_dns_credentials "$zone" "$provider"
  cfg_id="zone_$(echo "$zone" | tr -cd 'a-zA-Z0-9' | tr '[:upper:]' '[:lower:]')"
  write_acme_user_data "$zone" "$DNS_PROVIDER" "$DNS_API_NAME" "$email" "$cfg_id" "${DNS_CFG_KV[@]}"
  domain_state_add "$zone" "$DNS_PROVIDER" "$DNS_API_NAME" "$cfg_id"

  # El archivo de configuración es leído por acme-companion al iniciar y al
  # recibir signal_le_service.
  if docker inspect nginx-proxy-acme >/dev/null 2>&1; then
    docker exec nginx-proxy-acme signal_le_service >/dev/null 2>&1 || true
  fi

  DETECTED_DNS_ZONE="$zone"
}

# ============================================================================
# LIMPIEZA COMPLETA DE UN DOMINIO / ALIASES
# ============================================================================
cleanup_domain_artifacts() {
  local HOSTS="$1"
  local d
  local _domains

  IFS=',' read -ra _domains <<< "$HOSTS"

  for d in "${_domains[@]}"; do
    d="$(echo "$d" | xargs)"
    [[ -z "$d" ]] && continue

    # Nunca borrar certificados/configuración que todavía pertenezcan a otra
    # publicación registrada en el estado. Se compara el dominio principal y
    # también cada alias como campo independiente.
    local HOST_IN_USE=""
    HOST_IN_USE="$(awk -F '\t' -v host="$d" -v current="$APP_ID" '
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

    log_info "Limpiando certificados y configuración de '${d}'..."

    # Los certificados ahora pertenecen a la ZONA wildcard, no a la app.
    # Nunca eliminamos aquí *.zona ni el estado global de acme.sh al quitar
    # una publicación, porque otras apps/subdominios pueden estar usando
    # exactamente el mismo wildcard.

    # Configuración personalizada por host de nginx-proxy, si existe.
    rm -f \
      "${BASE_DIR}/nginx/vhost.d/${d}" \
      "${BASE_DIR}/nginx/vhost.d/${d}.conf" 2>/dev/null || true

    # El estado ACME/wildcard se conserva aunque se elimine esta app.
  done

  # Fuerza a nginx-proxy a recargar la configuración después de eliminar
  # el bridge y los archivos asociados al dominio.
  if docker inspect nginx-proxy &>/dev/null; then
    docker exec nginx-proxy nginx -s reload &>/dev/null || true
  fi
}

# ============================================================================
# COMANDO: install
# ============================================================================
cmd_install() {
  local LE_EMAIL=""
  local OPTIND opt
  while getopts ":e:b:h" opt; do
    case "$opt" in
      e) LE_EMAIL="$OPTARG" ;;
      b) BASE_DIR="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 install -e <email-letsencrypt> [-b <directorio-base>]
  -e   Email por defecto para el registro ACME de Let's Encrypt (obligatorio)
  -b   Directorio base de instalación (default: /opt/reverse-proxy)
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :)  die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done

  [[ -z "$LE_EMAIL" ]] && die "Debes indicar -e <email>. Usa: $0 install -h"
  require_root

  # ---- Detección de distro ----
  [[ -f /etc/os-release ]] || die "No se pudo detectar la distribución (/etc/os-release no existe)."
  . /etc/os-release
  local DISTRO_ID="${ID:-unknown}"
  log_info "Distribución detectada: $DISTRO_ID"

  # ---- Instalación de Docker (idempotente) ----
  if command -v docker &>/dev/null; then
    log_ok "Docker ya está instalado ($(docker --version))."
  else
    log_info "Instalando Docker Engine..."
    case "$DISTRO_ID" in
      ubuntu|debian)
        apt-get update -y
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/${DISTRO_ID}/gpg" -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        local ARCH CODENAME
        ARCH="$(dpkg --print-architecture)"
        CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
        echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DISTRO_ID} ${CODENAME} stable" \
          > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        ;;
      rhel|centos|rocky|almalinux|fedora)
        local PKG_MGR="dnf"; command -v dnf &>/dev/null || PKG_MGR="yum"
        $PKG_MGR install -y yum-utils
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

  # ---- Estructura de directorios ----
  log_info "Creando estructura de directorios en ${BASE_DIR}..."
  mkdir -p "${BASE_DIR}/nginx/certs" "${BASE_DIR}/nginx/vhost.d" "${BASE_DIR}/nginx/conf.d" \
           "${BASE_DIR}/nginx/html" "${BASE_DIR}/nginx/acme" \
           "${BASE_DIR}/apps" "${BASE_DIR}/.state"
  ensure_domain_state_file
  touch "${ACME_USER_DATA}"
  chmod 600 "${ACME_USER_DATA}"
  ensure_state_file
  echo "$LE_EMAIL" > "${BASE_DIR}/.state/default_email"

  # ---- Red Docker compartida (idempotente) ----
  if docker network inspect "${NETWORK_NAME}" &>/dev/null; then
    log_ok "La red '${NETWORK_NAME}' ya existe."
  else
    log_info "Creando red Docker externa '${NETWORK_NAME}'..."
    docker network create "${NETWORK_NAME}"
  fi

  # ---- docker-compose.yml del proxy ----
  log_info "Generando docker-compose.yml de nginx-proxy + acme-companion (wildcard DNS-01)..."
  cat > "${BASE_DIR}/docker-compose.yml" <<EOF
services:
  nginx-proxy:
    image: nginxproxy/nginx-proxy:latest
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    networks:
      - ${NETWORK_NAME}
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
      - ./nginx/certs:/etc/nginx/certs:ro
      - ./nginx/vhost.d:/etc/nginx/vhost.d
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/html:/usr/share/nginx/html
    labels:
      - "com.github.nginx-proxy.nginx-proxy=true"

  acme-companion:
    image: nginxproxy/acme-companion:latest
    container_name: nginx-proxy-acme
    restart: unless-stopped
    networks:
      - ${NETWORK_NAME}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./nginx/certs:/etc/nginx/certs
      - ./nginx/vhost.d:/etc/nginx/vhost.d
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/html:/usr/share/nginx/html
      - ./nginx/acme:/etc/acme.sh
      - ./.state/letsencrypt_user_data:/app/letsencrypt_user_data:ro
    environment:
      - DEFAULT_EMAIL=${LE_EMAIL}
      - NGINX_PROXY_CONTAINER=nginx-proxy

networks:
  ${NETWORK_NAME}:
    external: true
EOF

  log_info "Levantando nginx-proxy y acme-companion..."
  (cd "${BASE_DIR}" && docker compose up -d)

  log_ok "¡Proxy inverso (nginx) instalado y corriendo!"
  echo
  echo "--------------------------------------------------------------"
  echo " Directorio de instalación : ${BASE_DIR}"
  echo " Red Docker compartida     : ${NETWORK_NAME}"
  echo " Email Let's Encrypt       : ${LE_EMAIL}"
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
  -n   Nombre corto/identificador de la app (ej: blog, api, tienda)
  -H   Dominio o subdominio PRINCIPAL (ej: blog.midominio.com)
  -p   Puerto interno que expone el contenedor (ej: 80, 3000, 8080)
  -m   Email para el certificado Let's Encrypt (opcional; usa el de 'install' si se omite)
  -a   Dominios/subdominios ADICIONALES que apuntan al MISMO contenedor,
       separados por coma (ej: www.blog.midominio.com,blog-alt.com)
       El certificado SSL cubrirá el dominio principal y todos los alias (SAN).
  -i   Imagen Docker a desplegar (crea un contenedor nuevo)
  -c   Nombre de un contenedor Docker YA EXISTENTE a conectar a la red proxy
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :)  die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done

  [[ -z "$APP_NAME" ]] && die "Falta -n (nombre de app). Usa: $0 add -h"
  [[ -z "$DOMAIN"   ]] && die "Falta -H (dominio). Usa: $0 add -h"
  [[ -z "$PORT"     ]] && die "Falta -p (puerto interno). Usa: $0 add -h"
  [[ -n "$IMAGE" && -n "$EXISTING_CONTAINER" ]] && die "Indica solo -i o -c, no ambos."
  [[ -z "$IMAGE" && -z "$EXISTING_CONTAINER" ]] && die "Debes indicar -i (imagen) o -c (contenedor existente)."

  require_root
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no está instalado. Ejecuta primero: sudo $0 install -e <email>"
  docker network inspect "${NETWORK_NAME}" &>/dev/null || die "La red '${NETWORK_NAME}' no existe. Ejecuta 'install' primero."

  if [[ -z "$LE_EMAIL" ]]; then
    if [[ -f "${BASE_DIR}/.state/default_email" ]]; then
      LE_EMAIL="$(cat "${BASE_DIR}/.state/default_email")"
      log_info "Usando email por defecto de la instalación: ${LE_EMAIL}"
    else
      die "No se indicó -m <email> y no hay email por defecto guardado. Indícalo con -m."
    fi
  fi

  # Validación de formato para el dominio principal y cada alias
  local _domain_regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$'
  [[ "$DOMAIN" =~ $_domain_regex ]] || die "El dominio '${DOMAIN}' no tiene un formato válido."
  [[ "$PORT" =~ ^[0-9]+$ ]] || die "El puerto '${PORT}' debe ser numérico."

  # La primera vez que aparece una zona, el script detectará automáticamente
  # la zona y el proveedor DNS y preparará su wildcard. La detección se hace
  # después de validar el id de la app para no pedir credenciales si la app ya existe.
  local DNS_ZONE=""
  local ALL_HOSTS="$DOMAIN"
  if [[ -n "$ALIASES" ]]; then
    IFS=',' read -ra _alias_arr <<< "$ALIASES"
    for a in "${_alias_arr[@]}"; do
      a="$(echo "$a" | xargs)"  # trim espacios
      [[ -z "$a" ]] && continue
      [[ "$a" =~ $_domain_regex ]] || die "El alias '${a}' no tiene un formato de dominio válido."
      ALL_HOSTS="${ALL_HOSTS},${a}"
    done
  fi

  local APP_ID
  APP_ID="$(echo "${APP_NAME}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
  [[ -z "$APP_ID" ]] && die "El nombre de app resultó vacío tras sanitizar."

  if [[ -n "$(state_get "$APP_ID")" ]]; then
    die "Ya existe una app registrada con el id '${APP_ID}'. Usa 'remove' primero o elige otro nombre (-n)."
  fi

  # Primera vez por zona: detección DNS + credenciales una sola vez.
  ensure_wildcard_domain "$DOMAIN" "$LE_EMAIL"
  DNS_ZONE="$DETECTED_DNS_ZONE"
  if [[ -n "$ALIASES" ]]; then
    IFS=',' read -ra _alias_arr <<< "$ALIASES"
    for a in "${_alias_arr[@]}"; do
      a="$(echo "$a" | xargs)"
      [[ -z "$a" ]] && continue
      ensure_wildcard_domain "$a" "$LE_EMAIL"
    done
  fi

  local APP_DIR="${BASE_DIR}/apps/${APP_ID}"
  mkdir -p "$APP_DIR"

  if [[ -n "$EXISTING_CONTAINER" ]]; then
    docker inspect "$EXISTING_CONTAINER" &>/dev/null || die "El contenedor '${EXISTING_CONTAINER}' no existe."

    # Un contenedor existente no puede recibir VIRTUAL_* / LETSENCRYPT_*
    # simplemente con "docker network connect". Creamos un bridge NGINX
    # dedicado que recibe tráfico del reverse proxy y lo reenvía al
    # contenedor existente por la red Docker compartida.
    local BRIDGE_NAME="${APP_ID}-proxy"
    local BRIDGE_DIR="${APP_DIR}"

    log_info "Conectando '${EXISTING_CONTAINER}' a la red '${NETWORK_NAME}'..."
    docker network connect "${NETWORK_NAME}" "${EXISTING_CONTAINER}" 2>/dev/null \
      || log_ok "El contenedor ya estaba conectado a la red."

    cat > "${BRIDGE_DIR}/nginx.conf" <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://${EXISTING_CONTAINER}:${PORT};
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

    cat > "${BRIDGE_DIR}/docker-compose.yml" <<EOF
services:
  ${BRIDGE_NAME}:
    image: nginx:alpine
    container_name: ${BRIDGE_NAME}
    restart: unless-stopped
    networks:
      - ${NETWORK_NAME}
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    environment:
      - VIRTUAL_HOST=${ALL_HOSTS}
      - VIRTUAL_PORT=80

networks:
  ${NETWORK_NAME}:
    external: true
EOF

    log_info "Levantando bridge '${BRIDGE_NAME}'..."
    (cd "$BRIDGE_DIR" && docker compose up -d)

    state_add "$APP_ID" "$DOMAIN" "$PORT" "existente" "$EXISTING_CONTAINER" "${ALIASES:--}"

    log_ok "Dominio '${ALL_HOSTS}' publicado mediante HTTPS sin puerto."
    log_ok "El tráfico externo 80/443 será reenviado internamente a '${EXISTING_CONTAINER}:${PORT}'."
    echo "URL pública: https://${DOMAIN}/"
    echo "El contenedor original NO fue recreado ni eliminado."
    echo "SSL: wildcard de la zona ${DNS_ZONE} (${DNS_ZONE} + *.${DNS_ZONE})."
    return 0
  fi

  # Caso: imagen nueva
  cat > "${APP_DIR}/docker-compose.yml" <<EOF
services:
  ${APP_ID}:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    networks:
      - ${NETWORK_NAME}
    environment:
      - VIRTUAL_HOST=${ALL_HOSTS}
      - VIRTUAL_PORT=${PORT}

networks:
  ${NETWORK_NAME}:
    external: true
EOF

  log_info "Levantando el contenedor '${APP_ID}'..."
  (cd "$APP_DIR" && docker compose up -d)
  state_add "$APP_ID" "$DOMAIN" "$PORT" "nuevo" "$IMAGE" "${ALIASES:--}"

  log_ok "Listo. '${ALL_HOSTS}' quedará enrutado hacia '${APP_ID}:${PORT}'."
  echo "SSL: wildcard de la zona ${DNS_ZONE} (${DNS_ZONE} + *.${DNS_ZONE})."
  echo "acme-companion gestionará automáticamente la emisión/renovación mediante DNS-01."
  echo "Verifica con: sudo $0 certs -n ${APP_ID}   |   sudo $0 logs -n acme"
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
      :)  die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done
  [[ -z "$APP_NAME" ]] && die "Falta -n (nombre de app). Usa: $0 remove -h"
  require_root

  local APP_ID
  APP_ID="$(echo "${APP_NAME}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
  local RECORD
  RECORD="$(state_get "$APP_ID")"
  [[ -z "$RECORD" ]] && die "No hay ninguna app registrada con id '${APP_ID}'. Usa: $0 list"

  local APP_DIR="${BASE_DIR}/apps/${APP_ID}"
  local TIPO; TIPO="$(echo "$RECORD" | cut -f4)"
  local DOMAIN; DOMAIN="$(echo "$RECORD" | cut -f2)"
  local ALIASES; ALIASES="$(echo "$RECORD" | cut -f6)"

  # Reconstruimos la lista exacta de hosts que pertenecían a esta publicación.
  local HOSTS="$DOMAIN"
  if [[ -n "$ALIASES" && "$ALIASES" != "-" ]]; then
    HOSTS="${HOSTS},${ALIASES}"
  fi

  if [[ -f "${APP_DIR}/docker-compose.yml" ]]; then
    if [[ "$TIPO" == "nuevo" || "$TIPO" == "redirect" ]]; then
      log_info "Deteniendo y eliminando el contenedor '${APP_ID}'..."
      (cd "$APP_DIR" && docker compose down -v) || log_warn "No se pudo bajar limpiamente; continúo con la limpieza."
    else
      local CONTENEDOR; CONTENEDOR="$(echo "$RECORD" | cut -f5)"
      log_info "Eliminando el bridge de proxy '${APP_ID}-proxy'..."
      (cd "$APP_DIR" && docker compose down -v) || log_warn "No se pudo eliminar limpiamente el bridge; continúo con la limpieza."
      log_warn "El contenedor original '${CONTENEDOR}' NO será eliminado ni recreado."
      log_info "Desconectando '${CONTENEDOR}' de la red '${NETWORK_NAME}'..."
      docker network disconnect "${NETWORK_NAME}" "$CONTENEDOR" 2>/dev/null || true
    fi
  elif [[ "$TIPO" == "existente" ]]; then
    local CONTENEDOR; CONTENEDOR="$(echo "$RECORD" | cut -f5)"
    log_info "Desconectando '${CONTENEDOR}' de la red '${NETWORK_NAME}'..."
    docker network disconnect "${NETWORK_NAME}" "$CONTENEDOR" 2>/dev/null || true
  fi

  # Primero retiramos el registro actual. Así la limpieza puede comprobar
  # si alguno de los hosts sigue siendo utilizado por OTRA publicación.
  state_remove_silent "$APP_ID"

  # IMPORTANTE: se limpia también el certificado/ACME del dominio y de sus
  # aliases. Esto permite volver a registrar exactamente el mismo dominio.
  cleanup_domain_artifacts "$HOSTS"

  # El directorio de la publicación contiene únicamente la configuración
  # creada por este script para esa app/bridge.
  rm -rf "$APP_DIR"

  log_ok "Publicación '${APP_ID}' eliminada completamente del proxy."
  log_ok "Dominio(s) liberado(s): ${HOSTS}"
  if [[ "$TIPO" == "existente" ]]; then
    log_ok "El contenedor original se conserva intacto, junto con sus datos."
  fi
  log_ok "El dominio puede volver a utilizarse con la opción 2."
}

# ============================================================================
# COMANDO: list
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

# ============================================================================
# COMANDO: status
# ============================================================================
cmd_status() {
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no está instalado."
  log_info "Estado de los contenedores del proxy:"
  docker ps --filter "name=nginx-proxy" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  echo
  log_info "Estado de las apps publicadas:"
  ensure_state_file
  if [[ ! -s "$STATE_FILE" ]]; then
    echo "  (ninguna)"
    return 0
  fi
  while IFS=$'\t' read -r id domain port tipo ref aliases; do
    local cname="$id"
    [[ "$tipo" == "existente" ]] && cname="$ref"
    if docker inspect "$cname" &>/dev/null; then
      local st; st="$(docker inspect -f '{{.State.Status}}' "$cname")"
      printf "  %-15s %-35s -> %s\n" "$id" "$domain" "$st"
    else
      printf "  %-15s %-35s -> %s\n" "$id" "$domain" "contenedor no encontrado"
    fi
  done < "$STATE_FILE"
}

# ============================================================================
# COMANDO: logs
# ============================================================================
cmd_logs() {
  local TARGET="proxy"
  local OPTIND opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) TARGET="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 logs [-n proxy|acme|<app>]
  -n   'proxy' (default), 'acme', o el id de una app publicada
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :)  die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done

  case "$TARGET" in
    proxy) docker logs -f --tail 100 nginx-proxy ;;
    acme)  docker logs -f --tail 100 nginx-proxy-acme ;;
    *)
      local RECORD; RECORD="$(state_get "$TARGET")"
      [[ -z "$RECORD" ]] && die "No hay app '${TARGET}' registrada. Usa: $0 list"
      local tipo cname
      tipo="$(echo "$RECORD" | cut -f4)"
      cname="$TARGET"
      [[ "$tipo" == "existente" ]] && cname="$(echo "$RECORD" | cut -f5)"
      docker logs -f --tail 100 "$cname"
      ;;
  esac
}

# ============================================================================
# COMANDO: certs — estado y vencimiento de certificados SSL
# ============================================================================
cmd_certs() {
  local TARGET="all"
  local OPTIND opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) TARGET="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 certs [-n <app>|all]
  -n   id de una app publicada, o 'all' (default) para ver los certificados wildcard
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done

  [[ -d "${BASE_DIR}/nginx/certs" ]] || die "El proxy no está instalado (no existe ${BASE_DIR}/nginx/certs)."
  ensure_state_file
  ensure_domain_state_file

  _print_cert_row() {
    local domain="$1"
    local crt="${BASE_DIR}/nginx/certs/${domain}.crt"
    if [[ ! -f "$crt" ]]; then
      local candidate sans_candidate
      for candidate in "${BASE_DIR}/nginx/certs/"*.crt; do
        [[ -f "$candidate" ]] || continue
        sans_candidate="$(openssl x509 -in "$candidate" -noout -ext subjectAltName 2>/dev/null | tr '\n' ' ' || true)"
        if [[ "$sans_candidate" == *"DNS:${domain}"* && "$sans_candidate" == *"DNS:*.${domain}"* ]]; then
          crt="$candidate"
          break
        fi
      done
    fi
    if [[ ! -f "$crt" ]]; then
      printf "  %-35s %s\n" "$domain" "certificado wildcard no encontrado (¿aún emitiéndose o falló?)"
      return
    fi
    local end_date days_left
    end_date="$(openssl x509 -enddate -noout -in "$crt" 2>/dev/null | cut -d= -f2)"
    [[ -n "$end_date" ]] || { printf "  %-35s %s\n" "$domain" "no se pudo leer el certificado"; return; }
    local end_epoch now_epoch
    end_epoch="$(date -d "$end_date" +%s 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    days_left=$(( (end_epoch - now_epoch) / 86400 ))
    if (( days_left < 0 )); then
      printf "  %-35s VENCIDO (%s)\n" "$domain" "$end_date"
    elif (( days_left < 15 )); then
      printf "  %-35s ${C_WARN}vence en %s días${C_RESET} (%s)\n" "$domain" "$days_left" "$end_date"
    else
      printf "  %-35s ${C_OK}vence en %s días${C_RESET} (%s)\n" "$domain" "$days_left" "$end_date"
    fi
    local sans
    sans="$(openssl x509 -in "$crt" -noout -ext subjectAltName 2>/dev/null | tr '\n' ' ' || true)"
    [[ "$sans" == *"*.$domain"* ]] && echo "    SAN: ${domain}, *.${domain}" || true
  }

  if [[ "$TARGET" == "all" ]]; then
    log_info "Estado de certificados wildcard:"
    if [[ ! -s "$DOMAIN_STATE_FILE" ]]; then
      log_info "No hay zonas DNS configuradas todavía."
      return 0
    fi
    while IFS=$'\t' read -r zone provider dns_api cfg_id; do
      [[ -z "$zone" ]] && continue
      _print_cert_row "$zone"
      printf "    DNS: %s (%s)\n" "$provider" "$dns_api"
    done < "$DOMAIN_STATE_FILE"
  else
    local record zone provider dns_api cfg_id host appid
    record="$(domain_state_get "$TARGET")"
    if [[ -z "$record" ]]; then
      appid="$(echo "$TARGET" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
      record="$(state_get "$appid")"
      [[ -n "$record" ]] || die "No existe la zona '${TARGET}' ni la app '${appid}'."
      host="$(echo "$record" | cut -f2)"
      zone="$(detect_dns_zone "$host" || true)"
      [[ -n "$zone" ]] || die "No pude determinar la zona DNS de '${host}'."
      record="$(domain_state_get "$zone")"
    fi
    IFS=$'\t' read -r zone provider dns_api cfg_id <<< "$record"
    log_info "Estado del wildcard para '${zone}':"
    _print_cert_row "$zone"
    printf "    DNS: %s (%s)\n" "$provider" "$dns_api"
  fi
}

# ============================================================================
# COMANDO: renew — fuerza renovación del wildcard de una zona DNS
# ============================================================================
cmd_renew() {
  local TARGET=""
  local OPTIND opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) TARGET="$OPTARG" ;;
      h) cat <<EOF
Uso: sudo $0 renew -n <zona>|all
  -n   dominio raíz (ej: orkapp.online), id de app que pertenezca a esa zona, o 'all'
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :) die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done
  [[ -n "$TARGET" ]] || die "Falta -n <zona>|<app>|all. Usa: $0 renew -h"
  require_root
  docker inspect nginx-proxy-acme &>/dev/null || die "El contenedor 'nginx-proxy-acme' no está corriendo. ¿Instalaste el proxy?"
  ensure_domain_state_file

  renew_zone() {
    local zone="$1"
    [[ -n "$(domain_state_get "$zone")" ]] || { log_warn "No existe una configuración wildcard para '${zone}'."; return 1; }
    log_info "Forzando renovación del wildcard '${zone} + *.${zone}'..."
    local logfile="/tmp/renew_${zone//[^a-zA-Z0-9_.-]/_}.log"
    if docker exec nginx-proxy-acme acme.sh --renew -d "$zone" --force &>"$logfile"; then
      log_ok "Renovación completada para '${zone} + *.${zone}'."
    else
      log_warn "acme.sh reportó un problema renovando '${zone}'. Detalle:"
      tail -n 20 "$logfile" || true
      return 1
    fi
  }

  if [[ "$TARGET" == "all" ]]; then
    while IFS=$'\t' read -r zone provider dns_api cfg_id; do
      [[ -z "$zone" ]] && continue
      renew_zone "$zone" || true
    done < "$DOMAIN_STATE_FILE"
  else
    local zone="$TARGET" record appid
    record="$(domain_state_get "$zone")"
    if [[ -z "$record" ]]; then
      appid="$(echo "$TARGET" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
      record="$(state_get "$appid")"
      [[ -n "$record" ]] || die "No existe la zona '${TARGET}' ni la app '${appid}'."
      local host; host="$(echo "$record" | cut -f2)"
      zone="$(detect_dns_zone "$host" || true)"
      [[ -n "$zone" ]] || die "No pude determinar la zona DNS de '${host}'."
    fi
    renew_zone "$zone"
  fi

  docker exec nginx-proxy nginx -s reload >/dev/null 2>&1 || true
}

# ============================================================================
# COMANDO: redirect — redirección pura dominio -> URL destino (sin backend)
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
  -n   Nombre corto/identificador (ej: old-blog)
  -H   Dominio o subdominio que va a redirigir (ej: viejo.midominio.com)
  -t   URL completa de destino (ej: https://nuevo.midominio.com)
  -m   Email para el certificado Let's Encrypt (opcional; usa el de 'install' si se omite)

Crea un contenedor nginx minimalista que solo responde con un 301 hacia
la URL destino, con SSL propio para el dominio de origen.
EOF
         exit 0 ;;
      \?) die "Opción inválida: -$OPTARG" ;;
      :)  die "La opción -$OPTARG requiere un argumento." ;;
    esac
  done

  [[ -z "$APP_NAME" ]] && die "Falta -n (nombre de app). Usa: $0 redirect -h"
  [[ -z "$DOMAIN"   ]] && die "Falta -H (dominio origen). Usa: $0 redirect -h"
  [[ -z "$TARGET_URL" ]] && die "Falta -t (URL destino). Usa: $0 redirect -h"
  [[ "$TARGET_URL" =~ ^https?:// ]] || die "La URL destino debe comenzar con http:// o https://"

  require_root
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no está instalado. Ejecuta primero: sudo $0 install -e <email>"
  docker network inspect "${NETWORK_NAME}" &>/dev/null || die "La red '${NETWORK_NAME}' no existe."

  if [[ -z "$LE_EMAIL" ]]; then
    if [[ -f "${BASE_DIR}/.state/default_email" ]]; then
      LE_EMAIL="$(cat "${BASE_DIR}/.state/default_email")"
    else
      die "No se indicó -m <email> y no hay email por defecto guardado."
    fi
  fi

  local _domain_regex='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$'
  [[ "$DOMAIN" =~ $_domain_regex ]] || die "El dominio '${DOMAIN}' no tiene un formato válido."

  local DNS_ZONE
  ensure_wildcard_domain "$DOMAIN" "$LE_EMAIL"
  DNS_ZONE="$DETECTED_DNS_ZONE"

  local APP_ID
  APP_ID="$(echo "${APP_NAME}" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')"
  [[ -z "$APP_ID" ]] && die "El nombre de app resultó vacío tras sanitizar."

  if [[ -n "$(state_get "$APP_ID")" ]]; then
    die "Ya existe una app/registro con el id '${APP_ID}'. Usa 'remove' primero o elige otro nombre."
  fi

  local APP_DIR="${BASE_DIR}/apps/${APP_ID}"
  mkdir -p "$APP_DIR"

  # Configuración nginx minimalista: responde 301 a cualquier ruta
  cat > "${APP_DIR}/redirect.conf" <<EOF
server {
    listen 80;
    server_name _;
    return 301 ${TARGET_URL}\$request_uri;
}
EOF

  cat > "${APP_DIR}/docker-compose.yml" <<EOF
services:
  ${APP_ID}:
    image: nginx:alpine
    container_name: ${APP_ID}
    restart: unless-stopped
    networks:
      - ${NETWORK_NAME}
    volumes:
      - ./redirect.conf:/etc/nginx/conf.d/default.conf:ro
    environment:
      - VIRTUAL_HOST=${DOMAIN}
      - VIRTUAL_PORT=80

networks:
  ${NETWORK_NAME}:
    external: true
EOF

  log_info "Levantando redirector '${APP_ID}' (${DOMAIN} -> ${TARGET_URL})..."
  (cd "$APP_DIR" && docker compose up -d)
  state_add "$APP_ID" "$DOMAIN" "80" "redirect" "$TARGET_URL" "-"

  log_ok "Listo. Todo el tráfico a '${DOMAIN}' será redirigido (301) a '${TARGET_URL}'."
  echo "SSL: wildcard de la zona correspondiente; la emisión/renovación se gestiona automáticamente."
}

# ============================================================================
# COMANDO: uninstall
# ============================================================================
cmd_uninstall() {
  require_root
  [[ -f "${BASE_DIR}/docker-compose.yml" ]] || die "El proxy no parece estar instalado en ${BASE_DIR}."
  log_warn "Esto detendrá y eliminará nginx-proxy y acme-companion."
  log_warn "Las apps publicadas (en ${BASE_DIR}/apps) NO se eliminan; hazlo con 'remove' si lo necesitas."
  read -r -p "¿Continuar? [y/N]: " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { log_info "Cancelado."; exit 0; }
  (cd "${BASE_DIR}" && docker compose down)
  log_ok "Proxy detenido y contenedores eliminados. Los certificados y configuración siguen en ${BASE_DIR}."
}

# ============================================================================
# MODO INTERACTIVO — menú que pregunta cada dato y ejecuta la acción
# ============================================================================
_pause() { read -rp "Presiona Enter para continuar..." _ ; }

_run_safe() {
  # Ejecuta la función indicada en un subshell: si algo falla (die/exit),
  # NO se cierra el script completo, solo se reporta el error y se vuelve al menú.
  ( "$@" )
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    log_warn "La operación terminó con errores (código $rc)."
  fi
  return 0
}

interactive_menu() {
  while true; do
    echo
    echo "================================================================"
    echo "   Administrador de Reverse Proxy NGINX + Docker"
    echo "================================================================"
    echo "  1) Instalar el proxy (primera vez)"
    echo "  2) Agregar dominio/subdominio (nuevo contenedor o existente)"
    echo "  3) Crear una redirección (dominio -> URL)"
    echo "  4) Listar apps/dominios publicados"
    echo "  5) Ver estado de los contenedores"
    echo "  6) Ver logs (proxy, acme o una app)"
    echo "  7) Ver estado de certificados SSL"
    echo "  8) Forzar renovación de certificado wildcard"
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
        ARGS=(-e "$EMAIL"); [[ -n "$BDIR" ]] && ARGS+=(-b "$BDIR")
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
        [[ -n "$MAIL"  ]] && ARGS+=(-m "$MAIL")
        [[ -n "$ALIAS" ]] && ARGS+=(-a "$ALIAS")

        if [[ "$TIPO_SEL" == "a" ]]; then
          read -rp "Imagen Docker (ej: wordpress:latest): " IMG
          ARGS+=(-i "$IMG")
        elif [[ "$TIPO_SEL" == "b" ]]; then
          read -rp "Nombre del contenedor existente: " CONT
          ARGS+=(-c "$CONT")
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
        ARGS=(-n "$APP_N" -H "$DOM" -t "$DEST")
        [[ -n "$MAIL" ]] && ARGS+=(-m "$MAIL")
        _run_safe cmd_redirect "${ARGS[@]}"
        ;;

      4) _run_safe cmd_list ;;

      5) _run_safe cmd_status ;;

      6)
        read -rp "¿Logs de qué? [proxy/acme/<id-de-app>] (Enter = proxy): " TARGET
        ARGS=(); [[ -n "$TARGET" ]] && ARGS+=(-n "$TARGET")
        echo "(Ctrl+C para dejar de ver los logs y volver al menú)"
        _run_safe cmd_logs "${ARGS[@]}"
        ;;

      7)
        read -rp "¿Certificado de qué zona/app? [Enter = todos]: " TARGET
        ARGS=(); [[ -n "$TARGET" ]] && ARGS+=(-n "$TARGET")
        _run_safe cmd_certs "${ARGS[@]}"
        ;;

      8)
        read -rp "¿Renovar qué zona/app? (Enter = todas): " TARGET
        if [[ -z "$TARGET" ]]; then
          _run_safe cmd_renew -n all
        else
          _run_safe cmd_renew -n "$TARGET"
        fi
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
