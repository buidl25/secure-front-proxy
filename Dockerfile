FROM nginx:alpine AS runtime

ARG PROXY_PASS=http://delta-neutral-lp-bot-dev.railway.internal
ARG PORT=4000
ARG USERNAME=user
ARG PASSWORD=password

# Устанавливаем необходимые инструменты для отладки и проверки сети
RUN apk add --no-cache openssl iputils curl bind-tools

# Настраиваем переменные окружения
ENV PROXY_PASS=$PROXY_PASS
ENV PORT=$PORT
ENV USERNAME=$USERNAME
ENV PASSWORD=$PASSWORD

# Копируем файлы конфигурации
COPY ./nginx.conf.template /etc/nginx/nginx.conf.template
COPY ./gen_passwd.sh /etc/nginx/gen_passwd.sh
COPY ./docker-entrypoint.sh /docker-entrypoint.sh

# Устанавливаем права на выполнение скриптов
RUN chmod +x /etc/nginx/gen_passwd.sh
RUN chmod +x /docker-entrypoint.sh

# Добавляем настройки для DNS-резолвера
RUN echo "resolver 1.1.1.1 ipv6=off;" > /etc/nginx/conf.d/resolver.conf
EXPOSE ${PORT}

# Устанавливаем точку входа
ENTRYPOINT ["/docker-entrypoint.sh"]