FROM php:8.2-apache

# Habilitar mod_rewrite y compilar extensiones necesarias para MySQL en una sola capa para optimizar la imagen
RUN a2enmod rewrite \
    && docker-php-ext-install mysqli pdo pdo_mysql

# Hacer que Apache escuche en el puerto 1080 en vez del 80 por defecto
RUN sed -i 's/Listen 80/Listen 1080/' /etc/apache2/ports.conf \
    && sed -i 's/<VirtualHost \*:80>/<VirtualHost *:1080>/' /etc/apache2/sites-available/000-default.conf

# Copiar el proyecto desde la raíz del repositorio local hacia el contenedor (esto soluciona el error)
COPY . /var/www/html/

# Asignar los permisos correctos al usuario de Apache
RUN chown -R www-data:www-data /var/www/html

EXPOSE 1080