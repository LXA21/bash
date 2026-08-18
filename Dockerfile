FROM php:8.2-apache

# Extensiones necesarias para MySQL
RUN docker-php-ext-install mysqli pdo pdo_mysql

# Habilitar mod_rewrite (util para la mayoria de sistemas PHP)
RUN a2enmod rewrite

# Apache escuchara en el puerto 1080 en vez del 80 por defecto
RUN sed -i 's/Listen 80/Listen 1080/' /etc/apache2/ports.conf \
    && sed -i 's/<VirtualHost \*:80>/<VirtualHost *:1080>/' /etc/apache2/sites-available/000-default.conf

# Copiar el proyecto dentro del contenedor
COPY ./nexora/ /var/www/html/

# Permisos
RUN chown -R www-data:www-data /var/www/html

EXPOSE 1080
