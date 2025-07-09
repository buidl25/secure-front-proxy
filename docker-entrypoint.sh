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
HOST=$(echo $PROXY_PASS | sed -E 's/https?:\/\///' | sed -E 's/:\/.*$//' | sed -E 's/\/.*//')
echo "Target host: $HOST"

# Извлекаем протокол из PROXY_PASS
PROTOCOL=$(echo $PROXY_PASS | grep -o "^https\?://" | sed 's/:\/\///')
echo "Protocol: $PROTOCOL"

# Сохраняем исходный URL для использования в конфигурации
ORIGINAL_PROXY_PASS=$PROXY_PASS

# Формируем чистый URL без протокола для использования в заголовке Host
CLEAN_HOST=$HOST
export CLEAN_HOST

# Проверяем, нужно ли использовать HTTP вместо HTTPS
if [ "$USE_HTTP_BACKEND" = "true" ]; then
    echo "\n=== Using HTTP instead of HTTPS for backend ==="
    # Если URL содержит https://, заменяем на http://
    if echo "$PROXY_PASS" | grep -q "^https://"; then
        HTTP_URL=$(echo "$PROXY_PASS" | sed 's/^https:/http:/')
        echo "Converting $PROXY_PASS to $HTTP_URL"
        PROXY_PASS="$HTTP_URL"
    fi
fi

# Проверяем, является ли хост внутренним доменом Railway
if echo "$HOST" | grep -q "\.railway\.internal$"; then
    echo "\n=== WARNING: Internal Railway domain detected ==="
    echo "Internal Railway domains may not be resolvable. Consider using a public URL instead."
    
    # Преобразуем внутренний домен в публичный URL
    SERVICE_NAME=$(echo "$HOST" | sed -E 's/\.railway\.internal$//')
    PUBLIC_URL="https://${SERVICE_NAME}.up.railway.app"
    
    echo "Attempting to use public URL instead: $PUBLIC_URL"
    PROXY_PASS="$PUBLIC_URL"
    HOST=$(echo $PROXY_PASS | sed -E 's/https?:\/\///' | sed -E 's/:.*//')
    echo "New target host: $HOST"
fi

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

# Проверяем с помощью dig с указанием публичных DNS
echo "\nTesting with dig using public DNS:"
dig @1.1.1.1 $HOST || echo "dig with Cloudflare DNS failed for $HOST"
dig @8.8.8.8 $HOST || echo "dig with Google DNS failed for $HOST"

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

# Создаем переменную use_http_backend для использования в nginx.conf
if [ "$USE_HTTP_BACKEND" = "true" ] || [ "$PROTOCOL" = "http" ]; then
    export use_http_backend="true"
    echo "Using HTTP for backend connections"
else
    export use_http_backend="false"
    echo "Using HTTPS for backend connections"
fi

# Устанавливаем переменные для использования в конфигурации
export BACKEND_HOST=$CLEAN_HOST

# Применяем все переменные окружения к шаблону
envsubst '$PROXY_PASS $PORT $use_http_backend $BACKEND_HOST $CLEAN_HOST' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
echo "Nginx configuration applied successfully"

# Выводим информацию о конфигурации
echo "\n=== Configuration Summary ==="
echo "PROXY_PASS: $PROXY_PASS"
echo "PORT: $PORT"
echo "HOST: $HOST"
echo "CLEAN_HOST: $CLEAN_HOST"
echo "PROTOCOL: $PROTOCOL"
echo "USE_HTTP_BACKEND: $USE_HTTP_BACKEND"
echo "use_http_backend (for nginx): $use_http_backend"
echo "BACKEND_HOST: $BACKEND_HOST"

# Проверяем конфигурацию Nginx на наличие проблем
echo "\n=== Checking Nginx configuration for issues ==="

# Удаляем любые упоминания IPv6-адресов, если они есть
if grep -q "fd12::10" /etc/nginx/nginx.conf; then
    echo "Found IPv6 address fd12::10 in configuration, removing..."
    sed -i 's/fd12::10//g' /etc/nginx/nginx.conf
    echo "Removed IPv6 addresses from configuration"
fi

# Отключаем поддержку IPv6 в конфигурации
if grep -q "ipv6=on" /etc/nginx/nginx.conf; then
    echo "Found ipv6=on in configuration, removing..."
    sed -i 's/ipv6=on//g' /etc/nginx/nginx.conf
    echo "Disabled IPv6 support in configuration"
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
    # Упрощаем конфигурацию резолвера
    echo "Simplifying resolver configuration..."
    sed -i 's/resolver .*/resolver 1.1.1.1 8.8.8.8 valid=10s;/g' /etc/nginx/nginx.conf
    
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
