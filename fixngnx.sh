cd /opt/reverse-proxy
docker compose down

cat > /opt/reverse-proxy/docker-compose.yml <<'EOF'
services:
  nginx-proxy:
    image: nginx:stable-alpine
    container_name: nginx-proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    networks:
      - proxy
    volumes:
      - /opt/reverse-proxy/nginx/conf.d:/etc/nginx/conf.d:ro
      - /opt/reverse-proxy/nginx/certs:/etc/nginx/certs:ro
      - /opt/reverse-proxy/nginx/certbot:/etc/letsencrypt:ro
      - /opt/reverse-proxy/nginx/html:/usr/share/nginx/html:ro
      - /opt/reverse-proxy/nginx/logs:/var/log/nginx

networks:
  proxy:
    external: true
EOF

docker compose up -d