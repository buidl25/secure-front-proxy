#!/bin/sh
set -e

# Получаем переменные окружения
HOST=$(echo $PROXY_PASS | sed -E 's/https?:\/\///' | sed -E 's/:.*//')

echo "Checking connectivity to host: $HOST"
# Проверяем доступность хоста
for i in $(seq 1 30); do
    if ping -c 1 $HOST > /dev/null 2>&1; then
        echo "Host $HOST is reachable!"
        break
    fi
    
    if [ $i -eq 30 ]; then
        echo "Error: Host $HOST is not reachable after 30 attempts."
        echo "Available hosts in /etc/hosts:"
        cat /etc/hosts
        echo "Network configuration:"
        ip addr
        echo "DNS configuration:"
        cat /etc/resolv.conf
        exit 1
    fi
    
    echo "Waiting for host $HOST to become available... (attempt $i/30)"
    sleep 2
done

# Генерируем файл с паролем, если он еще не существует
if [ ! -f /etc/nginx/.htpasswd ]; then
    echo "Generating password file..."
    /etc/nginx/gen_passwd.sh
fi

# Применяем переменные окружения к шаблону конфигурации
echo "Applying environment variables to nginx configuration..."
envsubst '$PROXY_PASS $PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Запускаем Nginx
echo "Starting Nginx..."
exec nginx -g "daemon off;"
