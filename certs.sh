mkdir -p /opt/reverse-proxy/nginx/certs

openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -subj "/CN=nginx-default.invalid" \
  -keyout /opt/reverse-proxy/nginx/certs/default.key \
  -out /opt/reverse-proxy/nginx/certs/default.crt

chmod 600 /opt/reverse-proxy/nginx/certs/default.key

docker restart nginx-proxy