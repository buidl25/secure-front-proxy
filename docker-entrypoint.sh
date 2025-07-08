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

# Проверяем с помощью nslookup
echo "Testing with nslookup:"
nslookup $HOST || echo "nslookup failed for $HOST"

# Проверяем с помощью dig
echo "\nTesting with dig:"
dig $HOST || echo "dig failed for $HOST"

# Проверяем с помощью dig с указанием внутреннего DNS Railway
echo "\nTesting with dig using Railway internal DNS:"
dig @fd12::10 $HOST || echo "dig with Railway DNS failed for $HOST"

# Проверяем с помощью getent
echo "\nTesting with getent hosts:"
getent hosts $HOST || echo "getent hosts failed for $HOST"

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

# Автоматически исправляем проблемы с IPv6-адресами в конфигурации
echo "\n=== Fixing IPv6 addresses in Nginx configuration ==="

# Исправляем формат IPv6-адресов в конфигурации Nginx
if grep -q "fd12::10" /etc/nginx/nginx.conf; then
    echo "Found IPv6 address fd12::10 without brackets, fixing..."
    sed -i 's/fd12::10/\[fd12::10\]/g' /etc/nginx/nginx.conf
    echo "Fixed IPv6 addresses in configuration"
fi

# Проверяем конфигурацию Nginx
echo "\n=== Checking Nginx configuration ==="
if nginx -t; then
    echo "Nginx configuration test passed"
else
    echo "Nginx configuration test failed, showing configuration:"
    cat /etc/nginx/nginx.conf
    echo "\nTrying to fix common issues..."
    
    # Дополнительные исправления
    # Удаляем IPv6-адреса, если они вызывают проблемы
    echo "Removing problematic IPv6 addresses from configuration..."
    sed -i 's/\[fd12::10\]//g' /etc/nginx/nginx.conf
    
    # Проверяем еще раз
    if nginx -t; then
        echo "Nginx configuration fixed and test passed"
    else
        echo "WARNING: Could not fix Nginx configuration automatically"
    fi
fi

# Запускаем Nginx
echo "\n=== Starting Nginx ==="
echo "Nginx starting in foreground mode..."
exec nginx -g "daemon off;"
