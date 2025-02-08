#!/bin/bash

# Запрос ввода от пользователя
read -p "Введите тип сервера (main/node): " SERVER_TYPE
read -p "Введите URL для параметра (из Uptime-Kuma) --url: " URL
read -p "Введите хост (ip/домен до которого будет идти TCP запрос) для параметра --ping-host: " PING_HOST
read -p "Введите Telegram Bot Token: " TELEGRAM_BOT_TOKEN
read -p "Введите Telegram Chat ID: " TELEGRAM_CHAT_ID

# URLs для скачивания файлов с GitHub
SCRIPT_URL="https://raw.githubusercontent.com/RAMMsila/kuma-push/refs/heads/main/kuma-push.sh"
SERVICE_URL="https://raw.githubusercontent.com/RAMMsila/kuma-push/refs/heads/main/kuma-push.service"

# Пути для установки
if [ "$SERVER_TYPE" == "node" ]; then
    INSTALL_DIR="/opt/marzban-node"
else
    INSTALL_DIR="/opt/marzban"
fi
SCRIPT_PATH="$INSTALL_DIR/kuma-push.sh"
SERVICE_PATH="/etc/systemd/system/kuma-push.service"

# Создание директории для скрипта, если она не существует
mkdir -p $INSTALL_DIR

# Скачивание и установка скрипта kuma-push.sh
wget -O $SCRIPT_PATH $SCRIPT_URL
chmod +x $SCRIPT_PATH

# Замена плейсхолдеров в скрипте
sed -i "s|TELEGRAM_BOT_TOKEN=\"YOUR_TELEGRAM_BOT_TOKEN\"|TELEGRAM_BOT_TOKEN=\"$TELEGRAM_BOT_TOKEN\"|g" $SCRIPT_PATH
sed -i "s|TELEGRAM_CHAT_ID=\"YOUR_TELEGRAM_CHAT_ID\"|TELEGRAM_CHAT_ID=\"$TELEGRAM_CHAT_ID\"|g" $SCRIPT_PATH

# Скачивание и установка службы kuma-push.service
wget -O $SERVICE_PATH $SERVICE_URL

# Замена плейсхолдеров в файле службы
sed -i "s|PLACEHOLDER_URL|$URL|g" $SERVICE_PATH
sed -i "s|PLACEHOLDER_PING_HOST|$PING_HOST|g" $SERVICE_PATH

# Замена пути установки в файле службы
sed -i "s|/opt/marzban/kuma-push.sh|$SCRIPT_PATH|g" $SERVICE_PATH
sed -i "s|WorkingDirectory=/opt/marzban|WorkingDirectory=$INSTALL_DIR|g" $SERVICE_PATH

# Перезагрузка systemd и запуск службы
systemctl daemon-reload
systemctl enable kuma-push.service
systemctl start kuma-push.service

echo "Установка завершена. Служба kuma-push запущена."

# Удаление самого себя
rm -- "$0"
