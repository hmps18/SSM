#!/bin/bash
set -e

# --- 1. Instalar Laravel ---
# Crea un directorio temporal y mueve el contenido a la raíz
composer create-project laravel/laravel temp_app
mv temp_app/* .
rmdir temp_app

# --- 2. Instalar y configurar React Starter Kit (Breeze) ---
composer require laravel/breeze --dev
php artisan breeze:install react

# --- 3. Instalar dependencias Node y PHP restantes ---
npm install
composer install

# --- 4. Configurar Docker Compose para MSSQL y Nginx ---
# Crea los directorios necesarios para los archivos compose y config
mkdir -p docker/nginx

# Descarga el docker-compose.yml que define Nginx y MSSQL
cat <<EOF > docker-compose.yml
version: '3.8'

services:
  nginx:
    image: nginx:stable-alpine
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - .:/var/www/html
      - ./docker/nginx/default.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - mssql_server
    networks:
      - app-network

  mssql_server:
    image: mcr.microsoft.com/mssql/server:2025-latest
    restart: unless-stopped
    environment:
      ACCEPT_EULA: 'Y'
      MSSQL_PID: 'Developer'
      SA_PASSWORD: 'YourStrongPassword!123'
    volumes:
      - mssqldata:/var/opt/mssql
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  mssqldata:
    driver: local
EOF

# Descarga el archivo default.conf de Nginx
cat <<EOF > docker/nginx/default.conf
server {
    listen 80;
    index index.php index.html;
    error_log /var/log/nginx/error.log;
    access_log /var/log/nginx/access.log;
    root /var/www/html/public;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
        # 'localhost:9000' porque php-fpm se ejecuta en el host del contenedor dev
        fastcgi_pass localhost:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
    }
}
EOF

# --- 5. Levantar servicios Docker Compose y Migrar DB ---
docker-compose up -d

# Esperar un momento a que la DB inicie
sleep 20 

# Configurar el .env para MSSQL
sed -i 's/DB_CONNECTION=mysql/DB_CONNECTION=sqlsrv/' .env
sed -i 's/DB_HOST=127.0.0.1/DB_HOST=mssql_server/' .env
sed -i 's/DB_PORT=3306/DB_PORT=1433/' .env
sed -i 's/DB_DATABASE=laravel/DB_DATABASE=laravel_db/' .env
sed -i 's/DB_USERNAME=root/DB_USERNAME=SA/' .env
# Usar la contraseña definida en docker-compose.yml
sed -i 's/DB_PASSWORD=/DB_PASSWORD=YourStrongPassword!123/' .env

# Ejecutar migraciones
php artisan migrate

# Limpiar script de setup
# rm setup.sh

echo "------------------------------------------------------"
echo "¡Proyecto Laravel 12 con React y MSSQL configurado!"
echo "Para iniciar el servidor de desarrollo Vite/React, ejecuta:"
echo "npm run dev"
echo "------------------------------------------------------"
