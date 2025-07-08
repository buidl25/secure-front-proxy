#!/bin/sh
set -e

# Выводим информацию о системе для диагностики
echo "=== System Information ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "Railway environment: $RAILWAY_ENVIRONMENT"

# Получаем переменные окружения и выводим их (без пароля)
echo "=== Configuration ==="
echo "PROXY_PASS: $PROXY_PASS"
echo "PORT: $PORT"
echo "USERNAME: $USERNAME"

# Извлекаем хост из PROXY_PASS
HOST=$(echo $PROXY_PASS | sed -E 's/https?:\/\///' | sed -E 's/:.*//')
echo "Target host: $HOST"

# Выводим информацию о сети
echo "=== Network Information ==="
echo "DNS Servers:"
cat /etc/resolv.conf
echo "\nHosts file:"
cat /etc/hosts
echo "\nNetwork interfaces:"
ip addr

# Проверяем DNS-резолвинг
echo "\n=== DNS Resolution Test ==="
echo "Resolving $HOST:"
nslookup $HOST || echo "nslookup failed for $HOST"

dig $HOST || echo "dig failed for $HOST"

# Пропускаем проверку доступности хоста, чтобы не блокировать запуск
echo "\n=== Skipping host connectivity check ==="
echo "Proceeding with Nginx configuration..."

# Генерируем файл с паролем, если он еще не существует
if [ ! -f /etc/nginx/.htpasswd ]; then
    echo "\n=== Generating password file ==="
    /etc/nginx/gen_passwd.sh
fi

# Применяем переменные окружения к шаблону конфигурации
echo "\n=== Applying Nginx configuration ==="
envsubst '$PROXY_PASS $PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
echo "Nginx configuration applied successfully"

# Проверяем конфигурацию Nginx
echo "\n=== Checking Nginx configuration ==="
nginx -t || echo "Nginx configuration test failed"

# Запускаем Nginx
echo "\n=== Starting Nginx ==="
echo "Nginx starting in foreground mode..."
exec nginx -g "daemon off;"
