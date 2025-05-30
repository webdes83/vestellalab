#!/bin/bash
set -e

ID="$1"
[ -z "$ID" ] && echo "Usage: $0 <VMID|CTID>" && exit 1

LXC_CONF="/etc/pve/lxc/$ID.conf"
VM_CONF="/etc/pve/qemu-server/$ID.conf"
MODE=""
if [ -f "$LXC_CONF" ]; then
    MODE="lxc"
elif [ -f "$VM_CONF" ]; then
    MODE="vm"
else
    echo "Not found: $ID (not LXC nor VM)"
    exit 1
fi

# 기존 description 읽기
if [ "$MODE" = "lxc" ]; then
    OLD_NOTE=$(pct config "$ID" | awk -F': ' '/^description:/ {print substr($0, index($0,$2))}')
    GET_SVC="pct exec $ID --"
    GET_FILE="pct exec $ID -- cat"
else
    OLD_NOTE=$(qm config "$ID" | awk -F': ' '/^description:/ {print substr($0, index($0,$2))}')
    GET_SVC="qm guest exec $ID --"
    GET_FILE="qm guest exec $ID -- cat"
fi

# 네트워크/브릿지/VLAN 정보 추출
if [ "$MODE" = "lxc" ]; then
    NET_LINE=$(grep '^net0:' "$LXC_CONF")
else
    NET_LINE=$(grep '^net0:' "$VM_CONF")
fi
BRIDGE=$(echo "$NET_LINE" | grep -oP 'bridge=\\K[^,]+')
VLAN=$(echo "$NET_LINE" | grep -oP 'tag=\\K[0-9]+')
IPINFO=$($GET_SVC bash -c "ip -4 -o addr show | grep -v '127\\.0\\.0\\.1' | awk '{print \$2\": \"\$4}'" 2>/dev/null)

# 서비스 및 소스 정보 (서비스별로 영역 생성)
SERVICES="openresty npm lamp node pm2"
SERVICE_INFO=""
for s in $SERVICES; do
    STATUS=$($GET_SVC systemctl is-active "$s".service 2>/dev/null || true)
    # 예시: 소스 정보 가져오기 (없으면 -로 표시)
    SRC_MARK="-"
    if [ "$s" = "openresty" ]; then
        SRC_MARK=$($GET_FILE /etc/openresty/nginx.conf 2>/dev/null | grep -E 'server_name|server {' | xargs 2>/dev/null || echo "-")
    elif [ "$s" = "lamp" ]; then
        SRC_MARK=$($GET_FILE /etc/apache2/sites-enabled/000-default.conf 2>/dev/null | grep -E 'ServerName|ServerAlias|DocumentRoot' | xargs 2>/dev/null || echo "-")
    elif [ "$s" = "npm" ]; then
        SRC_MARK=$($GET_FILE /opt/npm/.env 2>/dev/null | grep -v '^#' | xargs 2>/dev/null || echo "-")
    elif [ "$s" = "node" ]; then
        SRC_MARK=$($GET_SVC pm2 list 2>/dev/null | head -n 20 | xargs 2>/dev/null || echo "-")
    fi
    [ -z "$SRC_MARK" ] && SRC_MARK="-"
    if [ "$STATUS" = "active" ]; then
        SERVICE_INFO+="$s: active\n[소스 정보]\n$SRC_MARK\n\n"
    else
        SERVICE_INFO+="$s: inactive\n[소스 정보]\n$SRC_MARK\n\n"
    fi
done

CRONTAB_LIST=$($GET_SVC bash -c "for user in \$(cut -f1 -d: /etc/passwd); do crontab -u \$user -l 2>/dev/null | grep -q . && echo \$user; done" 2>/dev/null)
[ -n "$CRONTAB_LIST" ] && SERVICE_INFO+="crontab: $CRONTAB_LIST\n"

NEW_HEADER="### [Auto] 네트워크 정보\n$IPINFO (bridge: $BRIDGE, vlan: $VLAN)\n\n### [Auto] 서비스/소스 상태\n$SERVICE_INFO---\n"

# 기존 note에서 고정영역과 나머지 영역 분리
if echo "$OLD_NOTE" | grep -q '^### \[Auto\]'; then
    EXIST_AUTO=$(echo "$OLD_NOTE" | awk 'BEGIN{a=0} /^### \\[Auto\\]/ {a=1} a{print} /^---$/ {a=0}')
    REST_NOTE=$(echo "$OLD_NOTE" | awk 'BEGIN{a=0} /^---$/ {a=1; next} a{print}')
else
    EXIST_AUTO=""
    REST_NOTE="$OLD_NOTE"
fi

# diff 및 strikethrough
if [ -n "$EXIST_AUTO" ]; then
    DIFF_RESULT=$(
        diff -u <(echo "$EXIST_AUTO") <(echo -e "$NEW_HEADER") | \
        awk '
            /^-/ && !/^-{3}/ {print "~~" substr($0,2) "~~"}
            /^[+]/ && !/^\+\+\+/ {print substr($0,2)}
            /^[^+-]/ {if($0!~/^@/)print}
        '
    )
    HEADER="$DIFF_RESULT"
else
    HEADER="$NEW_HEADER"
fi

FINAL_NOTE="${HEADER}\n${REST_NOTE}"

# description 반영
if [ "$MODE" = "lxc" ]; then
    pct set "$ID" -description "$FINAL_NOTE"
else
    qm set "$ID" -description "$FINAL_NOTE"
fi

echo "✅ Note updated for $MODE $ID"
