FROM nginx:alpine AS runtime

# Устанавливаем аргументы сборки с публичным URL по умолчанию
ARG PROXY_PASS=https://delta-neutral-lp-bot-dev.up.railway.app
ARG PORT=80
ARG USERNAME=user
ARG PASSWORD=password
ARG USE_HTTP_BACKEND=false

# Устанавливаем необходимые инструменты для отладки и проверки сети
RUN apk update && \
    apk add --no-cache \
    openssl \
    iputils \
    curl \
    bind-tools \
    bash \
    ca-certificates \
    tzdata

# Настраиваем переменные окружения
ENV PROXY_PASS=$PROXY_PASS
ENV PORT=$PORT
ENV USERNAME=$USERNAME
ENV PASSWORD=$PASSWORD
ENV USE_HTTP_BACKEND=$USE_HTTP_BACKEND

# Создаем директории для логов
RUN mkdir -p /var/log/nginx

# Копируем файлы конфигурации
COPY ./nginx.conf.template /etc/nginx/nginx.conf.template
COPY ./gen_passwd.sh /etc/nginx/gen_passwd.sh
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

# Устанавливаем права на выполнение скриптов
RUN chmod +x /etc/nginx/gen_passwd.sh
RUN chmod +x /docker-entrypoint.sh

# Создаем страницу с ошибкой для отображения при проблемах
RUN echo '<html><head><title>Service Temporarily Unavailable</title></head><body><h1>Service Temporarily Unavailable</h1><p>The server is temporarily unable to service your request due to maintenance downtime or capacity problems. Please try again later.</p></body></html>' > /usr/share/nginx/html/50x.html

# Открываем порт
EXPOSE ${PORT}

# Устанавливаем точку входа
ENTRYPOINT ["/docker-entrypoint.sh"]