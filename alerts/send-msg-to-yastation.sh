#!/bin/bash

# Send message script to Yandex Station
# Andrey Kuznetsov, 2026.05.26
# Telegram: https://t.me/akmsg


# Home Assistant URL
HA_URL="http://has.home.local:8123"
# Long-Lived Access Token
HA_TOKEN="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# Yandex Station ID
STATION_NAME="media_player.yandex_station_r10ta8w005n8mk"

# User message here
MESSAGE="Это тестовое сообщение, отправленное скриптом!"

# Send POST request from Home Assistant API
curl -X POST -s -k \
  -H "Authorization: Bearer $HA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"entity_id\": \"$STATION_NAME\", \"message\": \"$MESSAGE\"}" \
  "$HA_URL/api/services/tts/cloud_say" > /dev/null 2>&1
