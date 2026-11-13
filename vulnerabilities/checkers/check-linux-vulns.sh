#!/usr/bin/env bash
#
# check_linux_vulns.sh — универсальная проверка уязвимостей ядра и OpenSSH
#
# Сравнивает фактическую версию ядра и OpenSSH с минимальными исправленными
# версиями по CVE из файла Linux_P1_admin_tasks_2026-11-08.csv.
# Работает на Debian/Ubuntu, RHEL/CentOS/AlmaLinux/Rocky/Fedora и прочих Linux.
#
# Использование:
#   ./check_linux_vulns.sh                 # проверка локальной системы
#   ./check_linux_vulns.sh -r report.txt   # отчёт в файл
#   ./check_linux_vulns.sh -h              # справка
#
# Коды возврата: 0 — ничего не найдено, 1 — есть потенциально уязвимые CVE,
#                2 — ошибка окружения (не Linux/нет нужных утилит)

set -uo pipefail

REPORT_FILE="/tmp/linux_vuln_report_$$.txt"
SHOW_HELP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    SHOW_HELP=1; shift ;;
        -r|--report)  REPORT_FILE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ "$SHOW_HELP" -eq 1 ]; then
    cat <<'HELP'
Проверка уязвимостей ядра Linux и OpenSSH по данным Linux_P1_admin_tasks_2026-11-08.csv

  -r FILE   файл подробного отчёта (по умолчанию /tmp/linux_vuln_report_<pid>.txt)
  -h        эта справка

Что делает:
  1. Определяет дистрибутив (/etc/os-release).
  2. Читает версию работающего ядра (uname -r), при возможности —
     версию пакета ядра из dpkg/rpm (для Debian uname и версия пакета расходятся).
  3. Сравнивает с минимальными исправленными версиями по каждому CVE,
     выбирая минимум для своей серии ядра (X.Y).
  4. Проверяет версию OpenSSH против тех же CVE.
  5. Предупреждает, если установленное ядро новее работающего (нужна перезагрузка).

Код возврата: 0 — ок, 1 — найдены потенциально незакрытые CVE, 2 — ошибка.
HELP
    exit 0
fi

# ───────────────────────── CVE-базисы (из CSV) ─────────────────────────
# Формат: "CVE|СЕРИЯ_X.Y|МИН_ВЕРСИЯ"   (серия = major.minor ядра)
# Для своей серии берётся соответствующий минимум; если серии нет в таблице —
# выводится ПРОВЕРИТЬ (данных по ветке в исходном файле нет).
KERNEL_CVES=(
    "CVE-2025-39682|6.1|6.1.153-1"
    "CVE-2025-39964|4.4|4.4.0-276.310"
    "CVE-2025-39964|4.15|4.15.0-245.257"
    "CVE-2025-39964|5.4|5.4.0-224.244"
    "CVE-2025-39964|5.10|5.10.247-1"
    "CVE-2025-39964|6.1|6.1.158-1"
    "CVE-2026-31431|4.4|4.4.0-"
    "CVE-2026-31431|4.15|4.15.0-250.262"
    "CVE-2026-31431|5.4|5.4.0-230.250"
    "CVE-2026-31431|5.10|5.10.251-3"
    "CVE-2026-31431|5.15|5.15.0-179.189"
    "CVE-2026-31431|6.1|6.1.170-1"
    "CVE-2026-31431|6.8|6.8.0-117.117"
    "CVE-2026-43284|4.15|4.15.0-251.263"
    "CVE-2026-43284|5.4|5.4.0-231.251"
    "CVE-2026-43284|5.10|5.10.251-4"
    "CVE-2026-43284|5.15|5.15.0-181.191"
    "CVE-2026-43284|6.1|6.1.170-3"
    "CVE-2026-43284|6.8|6.8.0-124.124"
    "CVE-2026-43500|5.4|5.4.0-231.251"
    "CVE-2026-43500|5.10|5.10.251-4"
    "CVE-2026-43500|5.15|5.15.0-181.191"
    "CVE-2026-43500|6.1|6.1.170-3"
    "CVE-2026-43500|6.8|6.8.0-124.124"
    "CVE-2026-43503|4.4|4.4.0-283.317"
    "CVE-2026-43503|4.15|4.15.0-253.265"
    "CVE-2026-43503|5.4|5.4.0-233.253"
    "CVE-2026-43503|5.10|5.10.257-1"
    "CVE-2026-43503|5.15|5.15.0-181.191"
    "CVE-2026-43503|6.1|6.1.174-1"
    "CVE-2026-43503|6.8|6.8.0-124.124"
    "CVE-2026-46300|4.4|4.4.0-283.317"
    "CVE-2026-46300|4.15|4.15.0-253.265"
    "CVE-2026-46300|5.4|5.4.0-233.253"
    "CVE-2026-46300|5.10|5.10.257-1"
    "CVE-2026-46300|5.15|5.15.0-181.191"
    "CVE-2026-46300|6.1|6.1.174-1"
    "CVE-2026-46300|6.8|6.8.0-124.124"
    "CVE-2026-46333|5.10|5.10.251-5"
    "CVE-2026-46333|5.15|5.15.0-181.191"
    "CVE-2026-46333|6.1|6.1.172-1"
    "CVE-2026-46333|6.8|6.8.0-124.124"
    "CVE-2026-53266|5.10|5.10.259-1"
    "CVE-2026-53266|5.15|5.15.0-198.208"
    "CVE-2026-53266|6.1|6.1.176-1"
    "CVE-2026-53266|6.8|6.8.0-146.146"
    "CVE-2026-53266|7.0|7.0.0-31.31"
    "CVE-2026-90049|5.15|5.15.0-202.212"
    "CVE-2026-90049|6.1|6.1.190-1"
    "CVE-2026-90049|7.0|7.0.0-42.42"
    "CVE-2026-99999|6.1|6.1.190-1"
    "ZDI-CAN-33367|5.14|"   # минимума в CSV нет — только сверка с эрратой вендора
)

# Формат: "CVE|МИН_VERSия_Ubuntu/RHEL|МИН_версия_Debian|ПРИМЕЧАНИЕ_ветки"
# Пустая колонка Debian + примечание = в ветке Debian фикса нет (проверено
# security-tracker.debian.org на 2026-11-13): УЯЗВИМ до релиза бэкпорта,
# только митигация/документированный приём риска.
# Debian 12 несёт правки безопасности в ревизиях 9.2p1-N+deb12uM (бэкпорт),
# поэтому для debian сравнение идёт по полной версии пакета.
OPENSsh_CVES=(
    "CVE-2024-6387|9.2p1|9.2p1-2+deb12u3|"
    "CVE-2025-26465|9.2p1|9.2p1-2+deb12u5|"
    "CVE-2025-26466|9.6p1|9.2p1-2+deb12u10|"
    "CVE-2025-32728|9.6p1|9.2p1-2+deb12u10|"
    "CVE-2026-106552|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm deb12u10 и trixie 10.0p1 — vulnerable"
    "CVE-2026-106553|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
    "CVE-2026-106555|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
    "CVE-2026-106582|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
    "CVE-2026-106583|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
    "CVE-2026-106584|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
    "CVE-2026-106585|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
    "CVE-2026-106586|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
    "CVE-2026-106587|9.6p1-3ubuntu13.20||фикс только в 10.6p1; bookworm/trixie — vulnerable"
)

# Собирает активные (не закомментированные) директивы sshd_config (+ .d/*)
sshd_active() {
    local files=()
    [ -f /etc/ssh/sshd_config ] && files+=(/etc/ssh/sshd_config)
    local f
    for f in /etc/ssh/sshd_config.d/*.conf; do [ -f "$f" ] && files+=("$f"); done
    for f in "${files[@]}"; do
        grep -v '^[[:space:]]*#' "$f" 2>/dev/null | grep -v '^[[:space:]]*$' || true
    done
}

# Значение активной директивы (first-match, как в sshd_config)
sshd_val() {
    local key="$1"
    sshd_active | awk -v k="$key" 'tolower($1)==tolower(k){print $2; exit}'
}

try() { local out; out=$("$@" 2>/dev/null) || true; echo "$out"; }

# numcmp: -1 / 0 / 1 для двух компонентов версии
_numcmp() {
    local x="$1" y="$2"
    # чистые числа — численно
    if [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]]; then
        if (( x > y )); then echo 1; elif (( x < y )); then echo -1; else echo 0; fi
        return
    fi
    # иначе: сравнить цифровой префикс численно, при равенстве — строку
    # ("deb12u3" vs "deb12u10", "el9_8" vs "el9_10")
    local xn=0 yn=0
    [[ "$x" =~ ^([0-9]+) ]] && xn="${BASH_REMATCH[1]}"
    [[ "$y" =~ ^([0-9]+) ]] && yn="${BASH_REMATCH[1]}"
    if [ "$xn" != "$yn" ]; then
        [ "$xn" -gt "$yn" ] && echo 1 || echo -1
        return
    fi
    if [[ "$x" == "$y" ]]; then echo 0
    elif [[ "$x" > "$y" ]]; then echo 1
    else echo -1; fi
}

# vercmp: -1 / 0 / 1 для версий (5.10.226-1, 6.8.0-124.142, 9.2p1-2+deb12u3, 5.14.0-687.5.3.el9_8)
vercmp() {
    # точная семантика Debian, если доступен dpkg
    if command -v dpkg >/dev/null 2>&1; then
        if dpkg --compare-versions "$1" gt "$2" 2>/dev/null; then echo 1; return; fi
        if dpkg --compare-versions "$1" lt "$2" 2>/dev/null; then echo -1; return; fi
        if dpkg --compare-versions "$1" eq "$2" 2>/dev/null; then echo 0; return; fi
        # если dpkg не смог сравнить (не его формат) — падаем в bash-фолбэк
    fi
    local a="$1" b="$2"
    a="${a#*:}"; b="${b#*:}"                       # снять epoch "1:"
    local a_main="${a%%-*}" a_rev="" b_main="${b%%-*}" b_rev=""
    [ "$a" != "$a_main" ] && a_rev="${a#*-}"
    [ "$b" != "$b_main" ] && b_rev="${b#*-}"

    local IFS=.; local -a am bm
    read -r -a am <<< "$a_main"; read -r -a bm <<< "$b_main"
    local n=${#am[@]}; [ ${#bm[@]} -gt "$n" ] && n=${#bm[@]}
    local i r
    for ((i=0; i<n; i++)); do
        r=$(_numcmp "${am[i]:-0}" "${bm[i]:-0}")
        [ "$r" != "0" ] && { echo "$r"; return; }
    done
    if [ -n "$a_rev" ] || [ -n "$b_rev" ]; then
        local IFS=.; local -a ar br
        read -r -a ar <<< "$a_rev"; read -r -a br <<< "$b_rev"
        n=${#ar[@]}; [ ${#br[@]} -gt "$n" ] && n=${#br[@]}
        for ((i=0; i<n; i++)); do
            r=$(_numcmp "${ar[i]:-0}" "${br[i]:-0}")
            [ "$r" != "0" ] && { echo "$r"; return; }
        done
    fi
    echo 0
}

ver_ge() { [ "$(vercmp "$1" "$2")" != "-1" ]; }

# ───────────────────────── определение системы ─────────────────────────

OS_ID=unknown; OS_VERSION_ID=""; OS_NAME="Unknown"; OS_FAMILY=generic
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"; OS_VERSION_ID="${VERSION_ID:-}"; OS_NAME="${NAME:-Unknown}"
    case "$OS_ID" in
        ubuntu|debian)                      OS_FAMILY=debian ;;
        rhel|centos|rocky|almalinux|ol|fedora) OS_FAMILY=rhel ;;
        *)                                  OS_FAMILY=generic ;;
    esac
fi

KERNEL_FULL="$(try uname -r)"
KERNEL_SERIES="$(echo "$KERNEL_FULL" | awk -F. '{print $1"."$2}')"
HOSTNAME_S="$(try hostname)"

# Версия пакета ядра для сравнения с минимумами из CSV:
#  - Ubuntu: uname совпадает с пакетом (6.8.0-142-generic → 6.8.0-142.142)
#  - Debian: пакет отличается (uname 5.10.0-26-amd64 ↔ пакет 5.10.226-1) → берём dpkg
#  - RHEL/Alma: uname ≈ пакет (5.14.0-687.5.3.el9_8)
KERNEL_PKGVER="$KERNEL_FULL"
PKG_SOURCE="uname"
if command -v dpkg-query >/dev/null 2>&1; then
    for p in "linux-image-$KERNEL_FULL" "linux-image-$KERNEL_SERIES" "linux-image-generic"; do
        v="$(try dpkg-query -W -f='${Version}' "$p")"
        if [ -n "$v" ]; then KERNEL_PKGVER="$v"; PKG_SOURCE="dpkg:$p"; break; fi
    done
fi
if [ "$PKG_SOURCE" = "uname" ] && command -v rpm >/dev/null 2>&1; then
    # новый запущенный пакет ядра
    v="$(try rpm -q --qf '%{VERSION}-%{RELEASE}' "kernel-$KERNEL_FULL")"
    [ -z "$v" ] && v="$(try rpm -q --last kernel | head -1 | awk '{print $1}' | sed 's/^kernel-//')"
    [ -n "$v" ] && { KERNEL_PKGVER="$v"; PKG_SOURCE="rpm"; }
fi

# OpenSSH: на Debian полная версия пакета важнее баннера (нужна ревизия deb12uN)
SSH_RAW=""
if [ "$OS_FAMILY" = "debian" ] && command -v dpkg-query >/dev/null 2>&1; then
    SSH_RAW="$(try dpkg-query -W -f='${Version}' openssh-server)"
fi
if [ -z "$SSH_RAW" ] && command -v sshd >/dev/null 2>&1; then
    SSH_RAW="$(sshd -V 2>&1 | grep -oiP 'OpenSSH[ _]+\K[0-9][0-9.pP+-]+[0-9.pP+~a-z]*' || true)"
fi
if [ -z "$SSH_RAW" ] && command -v ssh >/dev/null 2>&1; then
    SSH_RAW="$(ssh -V 2>&1 | grep -oiP 'OpenSSH[ _]+\K[0-9][0-9.pP]+' || true)"
fi
if [ -z "$SSH_RAW" ] && command -v rpm >/dev/null 2>&1; then
    SSH_RAW="$(try rpm -q --qf '%{VERSION}-%{RELEASE}' openssh-server)"
fi
# нормализация до апстрима: 1:9.2p1-2+deb12u3 / openssh-8.9p1-1.el8 / 9.6p1-3ubuntu13.8 → X.Y[pZ]
upstream() {
    local v="${1#*:}"
    if [[ "$v" =~ ^([0-9]+\.[0-9]+(p[0-9]+)?) ]]; then echo "${BASH_REMATCH[1]}"; else echo "$v"; fi
}
SSH_VER="$(upstream "$SSH_RAW")"

# ───────────────────────── проверки ─────────────────────────

KERNEL_VULN=()     # потенциально уязвимые CVE ядра
KERNEL_VERIFY=()   # нет данных по серии / пустой минимум
KERNEL_MATCHED=0   # сколько CVE реально сверены для этой серии
for entry in "${KERNEL_CVES[@]}"; do
    IFS='|' read -r cve series min <<< "$entry"
    if [ "$series" != "$KERNEL_SERIES" ]; then continue; fi
    if [ -z "$min" ]; then
        KERNEL_VERIFY+=("$cve (нет минимума в CSV — сверьте эррату $OS_NAME)")
        continue
    fi
    KERNEL_MATCHED=$((KERNEL_MATCHED+1))
    if ! ver_ge "$KERNEL_PKGVER" "$min"; then
        KERNEL_VULN+=("$cve (нужно ≥ $min)")
    fi
done
[ "$KERNEL_MATCHED" -eq 0 ] && KERNEL_VERIFY+=("для серии $KERNEL_SERIES в карте нет минимумов — проверьте эрраты $OS_NAME вручную")

SSH_VULN=()
SSH_VERIFY=()
if [ -n "$SSH_VER" ]; then
    for entry in "${OPENSsh_CVES[@]}"; do
        IFS='|' read -r cve min_common min_deb note <<< "$entry"
        if [ "$OS_FAMILY" = "debian" ]; then
            if [ -n "$min_deb" ]; then
                if [ "$SSH_RAW" = "$SSH_VER" ]; then
                    # ревизия пакета неизвестна (версия из баннера ssh -V)
                    SSH_VERIFY+=("$cve (нужно ≥ $min_deb; ревизия не определена — проверьте dpkg -l openssh-server)")
                    continue
                fi
                if ! ver_ge "$SSH_RAW" "$min_deb"; then
                    SSH_VULN+=("$cve (для Debian нужно ≥ $min_deb, стоит $SSH_RAW)")
                fi
            elif [ -n "$note" ]; then
                # проверено в security-tracker: в ветке Debian фикса нет
                SSH_VULN+=("$cve (в ветке Debian фикса нет — митигация/приём риска; $note)")
            else
                SSH_VERIFY+=("$cve (минимум $min_common — для Ubuntu/RHEL; статус Debian сверьте в security-tracker)")
            fi
        else
            min_up="$(upstream "$min_common")"
            if ! ver_ge "$SSH_VER" "$min_up"; then
                SSH_VULN+=("$cve (нужно ≥ $min_up; учитывайте ревизию пакета вендора)")
            fi
        fi
    done
fi

# Установлено ядро новее работающего? (нужна перезагрузка)
# Сравниваем версии пакетов, берём только состояние installed (не rc!).
NEWER_INSTALLED=""
if [ "$OS_FAMILY" = "debian" ] && command -v dpkg-query >/dev/null 2>&1; then
    while read -r status ver pkg; do
        [ "$status" = "installed" ] || continue
        [ "$(vercmp "$ver" "$KERNEL_PKGVER")" = "1" ] && NEWER_INSTALLED+="$pkg ($ver); "
    done < <(dpkg-query -W -f='${db:Status-Status} ${Version} ${Package}\n' 'linux-image-*' 2>/dev/null)
elif [ "$OS_FAMILY" = "rhel" ] && command -v rpm >/dev/null 2>&1; then
    while read -r ver; do
        [ "$(vercmp "$ver" "$KERNEL_PKGVER")" = "1" ] && NEWER_INSTALLED+="kernel-$ver; "
    done < <(rpm -q kernel --qf '%{VERSION}-%{RELEASE}\n' 2>/dev/null)
fi

# ───────────────────────── проверка митигаций ─────────────────────────
MIT_COMPRESSION="?"
MIT_GSSAPI="?"
MIT_SFTP="?"
MIT_RESTRICT="?"
MIT_NONE="?"

if command -v sshd >/dev/null 2>&1 || [ -f /etc/ssh/sshd_config ]; then
    c_val="$(sshd_val Compression)"
    case "$(echo "$c_val" | tr '[:upper:]' '[:lower:]')" in
        no|none) MIT_COMPRESSION="mitigated" ;;
        yes)     MIT_COMPRESSION="NOT mitigated (Compression yes)" ;;
        "")      MIT_COMPRESSION="NOT mitigated (по умолчанию сжатие включено)" ;;
        *)       MIT_COMPRESSION="неизвестно ($c_val)" ;;
    esac

    g_val="$(sshd_val GSSAPIAuthentication)"
    case "$(echo "$g_val" | tr '[:upper:]' '[:lower:]')" in
        no|none|"") MIT_GSSAPI="mitigated (по умолчанию отключено)" ;;
        yes)        MIT_GSSAPI="NOT mitigated (GSSAPIAuthentication yes)" ;;
        *)          MIT_GSSAPI="неизвестно ($g_val)" ;;
    esac

    if sshd_active | grep -qiE '^[[:space:]]*subsystem[[:space:]]+sftp'; then
        MIT_SFTP="NOT mitigated (подсистема sftp включена)"
    else
        MIT_SFTP="mitigated (подсистема sftp отключена)"
    fi

    if grep -rl 'restrict' /home/*/.ssh/authorized_keys /etc/ssh/authorized_keys* 2>/dev/null | grep -q .; then
        MIT_RESTRICT="найдены ключи с restrict — проверьте семантику туннелирования"
    else
        MIT_RESTRICT="mitigated (ключей с restrict нет)"
    fi

    none_hits="$(sshd_active | grep -iE '^[[:space:]]*[A-Za-z_]+[[:space:]]+none[[:space:]]*$' || true)"
    if [ -n "$none_hits" ]; then
        MIT_NONE="проверьте: $(echo "$none_hits" | tr '\n' '; ')"
    else
        MIT_NONE="mitigated (none как значение не используется)"
    fi
else
    MIT_COMPRESSION="n/a (sshd не установлен/конфиг не найден)"
    MIT_GSSAPI="n/a"
    MIT_SFTP="n/a"
    MIT_RESTRICT="n/a"
    MIT_NONE="n/a"
fi

# ───────────────────────── отчёт ─────────────────────────

{
    echo "============================================================"
    echo " Проверка уязвимостей Linux"
    echo " Дата       : $(date '+%Y-%m-%d %H:%M:%S')"
    echo " Хост       : ${HOSTNAME_S:-?}"
    echo " ОС         : $OS_NAME ($OS_ID $OS_VERSION_ID) [$OS_FAMILY]"
    echo " Ядро       : $KERNEL_FULL   (серия $KERNEL_SERIES)"
    echo " Версия для сравнения: $KERNEL_PKGVER  [источник: $PKG_SOURCE]"
    echo " OpenSSH    : ${SSH_RAW:-не определена} (апстрим: ${SSH_VER:-?})"
    echo "============================================================"
    echo ""
    echo "ЯДРО:"
    if [ ${#KERNEL_VULN[@]} -gt 0 ]; then
        printf '  УЯЗВИМ: %s\n' "${KERNEL_VULN[@]}"
    elif [ "$KERNEL_MATCHED" -gt 0 ]; then
        echo "  OK — закрыты все отслеживаемые CVE для серии $KERNEL_SERIES"
    fi
    [ ${#KERNEL_VERIFY[@]} -gt 0 ] && printf '  ПРОВЕРИТЬ: %s\n' "${KERNEL_VERIFY[@]}"
    echo ""
    echo "OpenSSH:"
    if [ -z "$SSH_VER" ]; then
        echo "  Версия не определена — проверьте вручную"
    else
        if [ ${#SSH_VULN[@]} -eq 0 ]; then
            echo "  OK — закрыты все отслеживаемые CVE для этой ветки"
        else
            printf '  УЯЗВИМ: %s\n' "${SSH_VULN[@]}"
        fi
        [ ${#SSH_VERIFY[@]} -gt 0 ] && printf '  ПРОВЕРИТЬ: %s\n' "${SSH_VERIFY[@]}"
    fi
    echo ""
    echo "Перезагрузка:"
    if [ -n "$NEWER_INSTALLED" ]; then
        echo "  ВНИМАНИЕ: установлены пакеты новее работающего ядра: ${NEWER_INSTALLED%;}"
        echo "  Требуется перезагрузка: обновление пакета не меняет работающее ядро."
    else
        echo "  Перезагрузка не требуется: работающее ядро совпадает с установленным (или новее установленных)."
    fi
    echo ""
    echo "Митигация OpenSSH (CVE-2026-106xxx без фикса в ветке Debian):"
    echo "  Compression : $MIT_COMPRESSION"
    echo "  GSSAPIAuth  : $MIT_GSSAPI"
    echo "  sftp        : $MIT_SFTP"
    echo "  restrict    : $MIT_RESTRICT"
    echo "  none-знач.  : $MIT_NONE"
    echo ""
    # Определяем, какая митигация требует действия
    needs_action() { case "$1" in mitigated*) return 1 ;; *) return 0 ;; esac; }
    is_na()       { case "$1" in n/a*) return 0 ;; *) return 1 ;; esac; }

    echo "Рекомендации:"
    echo "  1. Ставьте последний поддерживаемый пакет ветки, а не минимальный минимум."
    echo "  2. Закрытие = повторное чтение версий + проверка ключевых сервисов."
    echo "  3. Если нет возможности обновиться — задокументируйте livepatch."
    echo ""

    if needs_action "$MIT_COMPRESSION" || needs_action "$MIT_GSSAPI" || needs_action "$MIT_SFTP" || needs_action "$MIT_RESTRICT" || needs_action "$MIT_NONE"; then
        echo "  4. CVE без фикса в ветке Debian — примените митигацию (только недостающие):"
        needs_action "$MIT_COMPRESSION" && echo "       • CVE-2026-106582/106585 (сжатие): Compression no  →  sshd_config, ssh_config"
        needs_action "$MIT_GSSAPI"     && echo "       • CVE-2026-106553/106555 (GSSAPI): GSSAPIAuthentication no"
        needs_action "$MIT_SFTP"       && echo "       • CVE-2026-106552 (sftp traversal): отключить Subsystem sftp при неиспользовании"
        needs_action "$MIT_RESTRICT"   && echo "       • CVE-2026-106586 (restrict): пересмотреть authorized_keys с restrict"
        needs_action "$MIT_NONE"       && echo "       • CVE-2026-106583/584/587: проверить конфиги/сертификаты/none-значения"
        echo ""
        echo "     Применение (после правок — валидация и перезагрузка):"
        needs_action "$MIT_COMPRESSION" && echo "       sed -i 's/^#*Compression.*/Compression no/' /etc/ssh/sshd_config /etc/ssh/ssh_config"
        needs_action "$MIT_GSSAPI"     && echo "       sed -i 's/^#*GSSAPIAuthentication.*/GSSAPIAuthentication no/' /etc/ssh/sshd_config"
        needs_action "$MIT_SFTP"       && echo "       sed -i '/^Subsystem[[:space:]]\\+sftp/d' /etc/ssh/sshd_config"
        echo "       sshd -t && systemctl reload ssh"
        echo "     Статус бэкпортов: security-tracker.debian.org/tracker/source-package/openssh"
    else
        echo "  4. Все проверенные митигации для CVE без фикса в ветке Debian УЖЕ применены —"
        echo "     остается документировать приём риска до появления бэкпорта (deb12uN+)."
        echo "     Статус бэкпортов: security-tracker.debian.org/tracker/source-package/openssh"
    fi
    echo "============================================================"
} > "$REPORT_FILE"

echo "Подробный отчёт: $REPORT_FILE"
echo ""
cat "$REPORT_FILE"

# итоговый код возврата
if [ ${#KERNEL_VULN[@]} -gt 0 ] || [ ${#SSH_VULN[@]} -gt 0 ]; then exit 1; fi
exit 0
