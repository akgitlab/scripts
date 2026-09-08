#!/usr/bin/env bash
set -euo pipefail

# --- КОНФИГУРАЦИЯ ---
ARCHIVE_PATH="${1:-/home/devops/integrations/bitrix24/bitrix24_mcp-1.0.1}"
# Если ARCHIVE_PATH не найден на диске, исходники скачиваются отсюда:
PYPI_URL="https://files.pythonhosted.org/packages/c9/ea/0e3c534e0badd2e3ea1723c0a27f572449225db979d44e4b2b2667d9b308/bitrix24_mcp-1.0.1.tar.gz"
SERVER_NAME="bitrix24"
INSTALL_DIR="/opt/mcp/servers/${SERVER_NAME}"
HTTP_PORT="${HTTP_PORT:-8003}"   # 8000-8002 заняты (hpovsd, zabbix), bitrix24 на 8003
MCP_PATH="${MCP_PATH:-/mcp}"
SECRETS_DIR="${INSTALL_DIR}/secrets"        # переживает rm -rf через бэкап/восстановление
UV_PYTHON_INSTALL_DIR="${INSTALL_DIR}/uv-python"   # managed-Python живёт в INSTALL_DIR (uv только у bitrix24)
LOG_DIR="/var/log/mcp"                      # как у hpovsd/zabbix
LOG_FILE="${LOG_DIR}/mcp-${SERVER_NAME}.log"

log_info()  { echo "[INFO] $1"; }
log_warn()  { echo "[WARN] $1"; }
log_error() { echo "[ERROR] $1"; }

# --- ПРОВЕРКИ / ИСТОЧНИК ---
log_info "Начало развёртывания: $SERVER_NAME"

TMP_SRC=""
cleanup() { [[ -n "$TMP_SRC" ]] && rm -rf "$TMP_SRC"; }
trap cleanup EXIT

if [[ ! -d "$ARCHIVE_PATH" && ! -f "$ARCHIVE_PATH" ]]; then
    log_info "Источник '$ARCHIVE_PATH' не найден, скачиваю с PyPI..."
    TMP_SRC="$(mktemp -d)"
    curl -fsSL "$PYPI_URL" -o "$TMP_SRC/pkg.tar.gz"
    tar -xzf "$TMP_SRC/pkg.tar.gz" -C "$TMP_SRC"
    ARCHIVE_PATH="$(dirname "$(find "$TMP_SRC" -maxdepth 3 -name pyproject.toml | head -1)")"
    [[ -d "$ARCHIVE_PATH" ]] || { log_error "pyproject.toml не найден в скачанном архиве"; exit 1; }
    log_info "Источник: $ARCHIVE_PATH (распакован из PyPI)"
else
    log_info "Источник: $ARCHIVE_PATH"
fi

mkdir -p /opt/mcp/servers

if ! id "mcp" &>/dev/null; then
    log_info "Создание пользователя mcp..."
    useradd -r -u 10001 -m -d /opt/mcp -s /usr/sbin/nologin mcp
else
    log_info "Пользователь mcp уже существует."
fi

# --- КАТАЛОГ ЛОГОВ (общий для всех MCP-серверов) ---
mkdir -p "$LOG_DIR"
chown mcp:mcp "$LOG_DIR"
chmod 750 "$LOG_DIR"

# --- СИСТЕМНЫЕ ПАКЕТЫ ---
log_info "Установка системных пакетов..."
apt update
apt install -y curl ca-certificates

# --- UV ---
if ! command -v uv &>/dev/null; then
    log_info "Установка uv..."
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh
else
    log_info "uv уже установлен: $(uv --version)"
fi

# --- РАСПАКОВКА ---
log_info "Подготовка каталога: $INSTALL_DIR"

# Переживают rm -rf при переустановке: секреты и managed-Python бэкапим
# во временный каталог и возвращаем после распаковки
TMP_KEEP="$(mktemp -d)"
for D in "$SECRETS_DIR" "$UV_PYTHON_INSTALL_DIR"; do
    if [[ -d "$D" ]]; then
        NAME="$(basename "$D")"
        mkdir -p "$TMP_KEEP/$NAME"
        cp -a "$D"/. "$TMP_KEEP/$NAME"/
    fi
done

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

if [[ -d "$ARCHIVE_PATH" ]]; then
    log_info "Копирование из каталога..."
    cp -a "$ARCHIVE_PATH"/. "$INSTALL_DIR"/
else
    log_info "Распаковка архива..."
    case "$ARCHIVE_PATH" in
        *.tar.gz|*.tgz) tar -xzf "$ARCHIVE_PATH" -C "$INSTALL_DIR" ;;
        *.zip)          unzip -q "$ARCHIVE_PATH" -d "$INSTALL_DIR" ;;
        *) log_error "Неизвестный формат архива"; exit 1 ;;
    esac
fi

# --- ФИКС СТРУКТУРЫ: подкаталог архива (как в hpovsd) ---
SUBDIRS=($(find "$INSTALL_DIR" -maxdepth 1 -mindepth 1 -type d))
if [[ ${#SUBDIRS[@]} -eq 1 ]] && [[ ! -f "${INSTALL_DIR}/pyproject.toml" ]]; then
    SUBDIR="${SUBDIRS[0]}"
    log_info "Источники в подкаталоге $(basename "$SUBDIR"), поднимаем наверх..."
    mv "$SUBDIR"/* "$INSTALL_DIR/" 2>/dev/null || true
    mv "$SUBDIR"/.??* "$INSTALL_DIR/" 2>/dev/null || true
    rmdir "$SUBDIR" 2>/dev/null || true
fi

if [[ ! -f "${INSTALL_DIR}/pyproject.toml" ]]; then
    log_error "pyproject.toml не найден в $INSTALL_DIR"
    find "$INSTALL_DIR" -maxdepth 2 | head -30
    exit 1
fi

# --- ВОССТАНОВЛЕНИЕ secrets и uv-python ПОСЛЕ rm -rf ---
for NAME in secrets uv-python; do
    if [[ -d "$TMP_KEEP/$NAME" ]] && [[ -n "$(ls -A "$TMP_KEEP/$NAME" 2>/dev/null)" ]]; then
        mkdir -p "${INSTALL_DIR}/$NAME"
        cp -a "$TMP_KEEP/$NAME"/. "${INSTALL_DIR}/$NAME"/
        log_info "Восстановлен: ${INSTALL_DIR}/$NAME"
    fi
done
rm -rf "$TMP_KEEP"

# --- ПОЧИНКА БИТЫХ СИМЛИНКОВ В uv-python ---
# uv создаёт generic-симлинки (cpython-3.12-<платформа>) с АБСОЛЮТНЫМ
# путём на полный каталог (cpython-3.12.14-<платформа>). После переноса
# или рестора из бэкапа они мертвы -> venv не стартует, сервис падает
# в рестарт-луп. Чиним на ОТНОСИТЕЛЬНЫЕ симлинки — они переживут любой mv.
if [[ -d "$UV_PYTHON_INSTALL_DIR" ]]; then
    while IFS= read -r -d '' LINK; do
        NAME="$(basename "$LINK")"
        STEM="${NAME%%-*}"            # cpython
        TAIL="${NAME#*-}"; VER="${TAIL%%-*}"; PLAT="${TAIL#*-}"   # 3.12 / linux-x86_64-gnu
        REAL="$(find "$UV_PYTHON_INSTALL_DIR" -maxdepth 1 -type d \
            -name "${STEM}-${VER}.*-${PLAT}" | head -1)"
        if [[ -n "$REAL" ]]; then
            ln -sfn "$(basename "$REAL")" "$LINK"
            log_info "Починен симлинк: $NAME -> $(basename "$REAL") (relative)"
        else
            log_warn "Битый симлинк без реального каталога: $LINK (удалите uv-python для переустановки)"
        fi
    done < <(find "$UV_PYTHON_INSTALL_DIR" -maxdepth 1 -type l -xtype l -print0)
fi

# --- ЛИЧНЫЕ ДАННЫЕ В .env ПРОЕКТА (чтобы не тащили наружу секреты) ---
rm -f "${INSTALL_DIR}/.env"

# --- ПАТЧ main.py: транспорт через переменные окружения ---
# Апстрим жёстко вызывает server.run() -> stdio. В mcp 1.4.1 доступны
# только stdio и sse (streamable-http появился в более поздних версиях).
# Хост/порт FastMCP берёт из env FASTMCP_HOST/FASTMCP_PORT (env_prefix="FASTMCP_").
if ! grep -q 'BITRIX_MCP_TRANSPORT' "${INSTALL_DIR}/src/main.py"; then
    log_info "Патч src/main.py: транспорт из env..."
    python3 - "$INSTALL_DIR" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "src" / "main.py"
src = p.read_text(encoding="utf-8")
src = src.replace(
    "    server.run()\n",
    "    import os\n"
    "    server.run(transport=os.getenv('BITRIX_MCP_TRANSPORT', 'stdio'))\n",
)
p.write_text(src, encoding="utf-8")
PYEOF
    log_info "Патч применён."
else
    log_info "main.py уже пропатчен, пропускаем."
fi

# --- ПАТЧ logger.py: имя лог-файла из env ---
# Апстрим захардкодил "app.log". Для единообразия с hpovsd/zabbix логи
# идут в /var/log/mcp/mcp-bitrix24.log через APP_LOG_FILE.
if ! grep -q 'APP_LOG_FILE' "${INSTALL_DIR}/src/infrastructure/logging/logger.py"; then
    log_info "Патч logger.py: имя лог-файла из env..."
    python3 - "$INSTALL_DIR" <<'PYEOF'
import sys, pathlib
p = pathlib.Path(sys.argv[1]) / "src" / "infrastructure" / "logging" / "logger.py"
src = p.read_text(encoding="utf-8")
src = src.replace(
    '    log_file = log_dir / "app.log"\n',
    '    log_file = Path(os.getenv("APP_LOG_FILE", str(log_dir / "app.log")))\n',
)
p.write_text(src, encoding="utf-8")
PYEOF
    log_info "Патч применён."
else
    log_info "logger.py уже пропатчен, пропускаем."
fi

# --- СЕКРЕТЫ: URL вебхука (в ${SECRETS_DIR}, переживают переустановку) ---
if [[ -f "${SECRETS_DIR}/secrets.env" ]] && grep -q '^BITRIX_WEBHOOK_URL=' "${SECRETS_DIR}/secrets.env"; then
    log_info "Секреты уже настроены (${SECRETS_DIR}/secrets.env), пропускаем. Удалите файл для повторного ввода."
else
    log_info "Настройка секретов..."
    read -rp 'Введите BITRIX_WEBHOOK_URL (https://...bitrix24.ru/rest/N/xxx/): ' WEBHOOK_URL
    printf '\n'
    if [[ ! "$WEBHOOK_URL" =~ ^https://.+ ]]; then
        log_error "URL должен начинаться с https://"
        exit 1
    fi

    mkdir -p "$SECRETS_DIR"
    cat > "${SECRETS_DIR}/secrets.env" <<EOF
BITRIX_WEBHOOK_URL=${WEBHOOK_URL}
BITRIX_MCP_TRANSPORT=sse
FASTMCP_HOST=0.0.0.0
FASTMCP_PORT=${HTTP_PORT}
APP_LOG_DIR=${LOG_DIR}
APP_LOG_FILE=${LOG_FILE}
LOG_LEVEL=INFO
EOF
    unset WEBHOOK_URL
    chown root:mcp "${SECRETS_DIR}" "${SECRETS_DIR}/secrets.env"
    chmod 750 "${SECRETS_DIR}"
    chmod 640 "${SECRETS_DIR}/secrets.env"
fi

# --- ЗАВИСИМОСТИ ---
# ВАЖНО: пин 3.12. uv по умолчанию тянет новейший CPython (3.14), а
# pydantic-core 2.27.2 из uv.lock не имеет wheel под 3.14 и падает при
# сборке (pyo3 0.22.6 поддерживает максимум 3.13).
# Managed-Python ставится в ${UV_PYTHON_INSTALL_DIR} (внутри INSTALL_DIR):
# сервис работает от mcp, а /root ему недоступен; uv используется только
# этим развёртыванием.
export UV_PYTHON_INSTALL_DIR
log_info "Установка Python-зависимостей (uv sync, python 3.12)..."
cd "$INSTALL_DIR"
uv python install 3.12
UV_PROJECT_ENVIRONMENT="$INSTALL_DIR/.venv" uv sync --no-dev --frozen --python 3.12
log_info "Интерпретатор venv: $("$INSTALL_DIR/.venv/bin/python" --version 2>&1)"
chown -R mcp:mcp "$INSTALL_DIR"
chown root:mcp "${SECRETS_DIR}" "${SECRETS_DIR}/secrets.env"
chmod 750 "$INSTALL_DIR" "${SECRETS_DIR}"
chmod 640 "${SECRETS_DIR}/secrets.env"

# --- SMOKE-TEST от пользователя mcp ---
# APP_LOG_DIR обязателен: без него логгер пишет в ~/.local/state/b24-mcp,
# который от root недоступен под setpriv.
# Вебхук берём из secrets.env: IoC создаёт Bitrix-клиент на импорте, и
# fast_bitrix24 валидирует формат URL, dummy не пройдёт.
log_info "Smoke-test: импорт пакета..."
SMOKE_WEBHOOK="$(grep -m1 '^BITRIX_WEBHOOK_URL=' "${SECRETS_DIR}/secrets.env" | cut -d= -f2-)"
if [[ -z "$SMOKE_WEBHOOK" ]]; then
    log_error "Не удалось прочитать BITRIX_WEBHOOK_URL из ${SECRETS_DIR}/secrets.env"
    exit 1
fi
setpriv --reuid=mcp --regid=mcp --clear-groups \
    env BITRIX_WEBHOOK_URL="$SMOKE_WEBHOOK" APP_LOG_DIR="$LOG_DIR" APP_LOG_FILE="$LOG_FILE" \
    "$INSTALL_DIR/.venv/bin/python" -c "from src.main import server; print('import OK')" \
    || { log_error "Smoke-test провален"; exit 1; }
unset SMOKE_WEBHOOK

# --- SYSTEMD ---
log_info "Создание systemd-юнита..."
cat > "/etc/systemd/system/mcp-${SERVER_NAME}.service" <<EOF
[Unit]
Description=MCP server for Bitrix24 CRM (contacts/deals)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=mcp
Group=mcp
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${SECRETS_DIR}/secrets.env
Environment=PYTHONUNBUFFERED=1
Environment=UV_PROJECT_ENVIRONMENT=${INSTALL_DIR}/.venv
ExecStart=${INSTALL_DIR}/.venv/bin/bitrix24-mcp
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=${LOG_DIR}

[Install]
WantedBy=multi-user.target
EOF

# --- LOGROTATE ---
log_info "Настройка logrotate..."
cat > "/etc/logrotate.d/mcp-${SERVER_NAME}" <<EOF
${LOG_FILE} {
    weekly
    rotate 5
    size 20M
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF

systemctl daemon-reload
systemctl enable "mcp-${SERVER_NAME}"

# --- ЗАПУСК ---
log_info "Запуск сервиса..."
systemctl start "mcp-${SERVER_NAME}"
sleep 3

if systemctl is-active --quiet "mcp-${SERVER_NAME}"; then
    log_info "Сервис запущен."
    # SSE endpoint держит соединение открытым: curl успевает получить 200
    # и отваливается по timeout (exit 28) — RC будет "200". Это норма.
    # 000 = соединение не установилось, сервис реально не отвечает.
    RC=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
        "http://127.0.0.1:${HTTP_PORT}/sse" 2>/dev/null || true)
    if [[ "$RC" == "200" ]]; then
        log_info "Порт ${HTTP_PORT} отвечает (HTTP 200). Endpoint (SSE): http://<host>:${HTTP_PORT}/sse"
    else
        log_warn "Порт не отвечает (HTTP ${RC}). Логи: journalctl -u mcp-${SERVER_NAME} --no-pager -n 50"
    fi
else
    log_error "Сервис не запустился."
    journalctl -u "mcp-${SERVER_NAME}" --no-pager -n 50
    exit 1
fi

log_info "Готово. Секреты: ${SECRETS_DIR}/secrets.env (root:mcp 640)"
log_info "Логи: ${LOG_FILE} | journalctl -u mcp-${SERVER_NAME} -f"
