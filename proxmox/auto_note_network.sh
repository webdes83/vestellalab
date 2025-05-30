#!/usr/bin/env bash
#===============================================================================
# auto_note_network.sh
#
# Proxmox VM/CT 네트워크·방화벽·MAC·게스트 인터페이스 매핑 정보를 수집하여
# 기존 description 내 [Auto] network info 영역만 갱신하거나,
# 없으면 맨 앞에 추가한 뒤 description 필드에 적용
#
# Usage: bash auto_note_network.sh [-d|--debug] [-a|--apply] --id <VM/CT ID>
#===============================================================================

set -o errexit
set -o pipefail

DEBUG=0
APPLY=0
ID=""
TMP_MD=""
TYPE=""
CONF_PATH=""
GUEST_CMD=""
API_TYPE=""

echo_usage() {
  echo "Usage: $0 [-d|--debug] [-a|--apply] --id <VM/CT ID>" >&2
  exit 1
}

# 옵션 파싱
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--debug) DEBUG=1; shift ;;
    -a|--apply) APPLY=1; shift ;;
    --id)
      [[ -n "$2" ]] && { ID="$2"; shift 2; } || echo_usage ;;
    *) echo_usage ;;
  esac
done
[[ -z "$ID" ]] && echo_usage
(( DEBUG == 1 )) && set -x

TMP_MD="/tmp/proxmox_net_${ID}.md"

# VM vs CT 판별
if [[ -f "/etc/pve/qemu-server/${ID}.conf" ]]; then
  TYPE="VM"
  CONF_PATH="/etc/pve/qemu-server/${ID}.conf"
  GUEST_CMD="qm guest exec ${ID} --"
  API_TYPE="qemu"
elif [[ -f "/etc/pve/lxc/${ID}.conf" ]]; then
  TYPE="CT"
  CONF_PATH="/etc/pve/lxc/${ID}.conf"
  GUEST_CMD="pct exec ${ID} --"
  API_TYPE="lxc"
else
  echo "[ERROR] No VM or CT configuration found for ID ${ID}" >&2
  exit 1
fi

# Proxmox node & config JSON 한 번만 조회
NODE=$(hostname -s)
CONFIG_JSON=$(
  pvesh get /nodes/"$NODE"/"$API_TYPE"/"$ID"/config \
    --output-format=json
)

# GUEST_NAME 및 기존 description 추출
GUEST_NAME=$(echo "$CONFIG_JSON" | jq -r '.name // ""')
EXISTING=$(echo "$CONFIG_JSON" | jq -r '.description // ""')

# 통일된 JSON 포맷으로 게스트 명령 실행 결과를 반환
guest_exec() {
  local raw exitcode
  raw=$($GUEST_CMD bash -lc "$*" 2>&1)
  exitcode=$?
  printf '%s' "$raw" \
    | jq -Rs --argjson exitcode "$exitcode" \
        '{exitcode: $exitcode, "out-data": .}'
}

# 방화벽 상태 함수
echo_firewall() {
  local fw_file="/etc/pve/firewall/${ID}.fw"
  if [[ ! -f "$fw_file" ]]; then
    echo "enable:❌ policy_in:✅ policy_out:✅"
    return
  fi
  grep -q '^enable:[[:space:]]*1' "$fw_file" && enable=✅ || enable=❌
  grep -q '^policy_in:.*DROP'  "$fw_file" && policy_in=❌ || policy_in=✅
  grep -q '^policy_out:.*DROP' "$fw_file" && policy_out=❌ || policy_out=✅
  echo "enable:${enable} policy_in:${policy_in} policy_out:${policy_out}"
}

declare -A guest_map guest_content

parse_guest_config() {
  # 1) Netplan (*.yaml 만)
  local raw_ls code files
  raw_ls=$(guest_exec "ls /etc/netplan/*.yaml 2>/dev/null || true")
  code=$(echo "$raw_ls" | jq -r '.exitcode')
  if [[ $code -eq 0 ]]; then
    files=$(echo "$raw_ls" | jq -r '."out-data"' | sed '/^$/d')
    IFS=$'\n' read -r -a files <<<"$files"
    for name in "${files[@]}"; do
      local path="/etc/netplan/$name"
      local raw_cat content
      raw_cat=$(guest_exec "cat '$path'")
      code=$(echo "$raw_cat" | jq -r '.exitcode')
      [[ $code -ne 0 ]] && continue
      content=$(echo "$raw_cat" | jq -r '."out-data"')
      guest_content["$path"]="$content"

      echo "$content" \
        | yq eval -j - 2>/dev/null \
        | jq -r '
            .network.ethernets // {}
          | to_entries[]
          | "\(.value.networkmanager.name // \"legacy\"):\(.key)|\((.value.routes // [] | length)>0)"' \
        | while IFS='|' read -r idf has; do
            local iface raw_mac mac
            iface=${idf#*:}
            raw_mac=$(guest_exec "cat /sys/class/net/${iface}/address")
            mac=$(echo "$raw_mac" | jq -r '."out-data" // empty' | tr '[:upper:]' '[:lower:]' | tr -d '\n')
            guest_map[$mac]="$idf|$has|$path"
          done
    done
  fi

  # 2) NetworkManager (*.nmconnection 만)
  local raw_nm code nm_files
  raw_nm=$(guest_exec "ls /etc/NetworkManager/system-connections/*.nmconnection 2>/dev/null || true")
  code=$(echo "$raw_nm" | jq -r '.exitcode')
  if [[ $code -eq 0 ]]; then
    nm_files=$(echo "$raw_nm" | jq -r '."out-data"' | sed '/^$/d')
    IFS=$'\n' read -r -a nm_files <<<"$nm_files"
    for f in "${nm_files[@]}"; do
      local raw_cat content id iface has raw_mac mac
      raw_cat=$(guest_exec "cat '$f'")
      code=$(echo "$raw_cat" | jq -r '.exitcode')
      [[ $code -ne 0 ]] && continue
      content=$(echo "$raw_cat" | jq -r '."out-data"')
      guest_content["$f"]="$content"

      id=$(grep -m1 '^id=' <<<"$content" | cut -d= -f2)
      iface=$(grep -m1 '^interface-name=' <<<"$content" | cut -d= -f2)
      has=$(grep -q '^routes=' <<<"$content" && echo "true" || echo "false")
      raw_mac=$(guest_exec "cat /sys/class/net/${iface}/address")
      mac=$(echo "$raw_mac" | jq -r '."out-data" // empty' | tr '[:upper:]' '[:lower:]' | tr -d '\n')
      guest_map[$mac]="$id:$iface|$has|$f"
    done
  fi

  # 3) /etc/network/interfaces (up route / post-up ip route)
  local raw_intf content
  raw_intf=$(guest_exec "cat /etc/network/interfaces")
  code=$(echo "$raw_intf" | jq -r '.exitcode')
  if [[ $code -eq 0 ]]; then
    content=$(echo "$raw_intf" | jq -r '."out-data"')
    guest_content["/etc/network/interfaces"]="$content"
    echo "$content" \
      | awk '
          /^iface/ { ifc=$2 }
          /^(up route|post-up ip route)/ { has[ifc]=1 }
          END { for (i in has) print "legacy:" i "|" has[i] }' \
      | while IFS='|' read -r idf has; do
          local raw_mac mac r
          raw_mac=$(guest_exec "cat /sys/class/net/${idf#*:}/address")
          mac=$(echo "$raw_mac" | jq -r '."out-data" // empty' | tr '[:upper:]' '[:lower:]' | tr -d '\n')
          r=$([[ "$has" -eq 1 ]] && echo "true" || echo "false")
          guest_map[$mac]="$idf|$r|/etc/network/interfaces"
        done
  fi
}

generate_markdown() {
  cat > "$TMP_MD" <<-EOF
<!-- BEGIN_AUTO_NETWORK_INFO -->
---

### [Auto] network info

**firewall-cfg:** $(echo_firewall)

#### ${ID} ${GUEST_NAME} ${TYPE}

EOF

  grep -E '^net[0-9]+' "$CONF_PATH" | while IFS= read -r line; do
    local dev props bridge vlan entry idf has route_flag src
    dev=$(cut -d: -f1 <<<"$line")
    props=$(sed 's/,/ /g' <<<"$line")
    bridge=$(grep -Po '(?<=bridge=)[^ ]+' <<<"$props" || echo '❌')
    vlan=$(grep -Po '(?<=tag=)[^ ]+'    <<<"$props" || echo '❌')

    entry=${guest_map[$(grep -Po '(?<=virtio=|hwaddr=|mac=)[0-9A-Fa-f:]+' <<<"$props" | tr '[:upper:]' '[:lower:]')]:-"_:false|"}
    idf=${entry%%|*}
    has=${entry#*|}
    route_flag=$([[ "$has" == "true" ]] && echo '✅' || echo '❌')
    src=${entry##*|}

    if [[ -n "$src" && -n "${guest_content[$src]}" ]]; then
      cat >> "$TMP_MD" <<-DETAIL

<details><summary>${dev} | ${bridge}:${vlan} | ${idf} | routes=${route_flag}</summary>

filepath: $src
\`\`\`text
$(echo "${guest_content[$src]}" | sed 's/^/    /')
\`\`\`
</details>
DETAIL
    fi
  done

  cat >> "$TMP_MD" <<-'EOF'
---
<!-- END_AUTO_NETWORK_INFO -->
---
EOF
}

# main
parse_guest_config
generate_markdown

if (( APPLY == 1 )); then
  NEW_SEC=$(cat "$TMP_MD")

  if grep -q '<!-- BEGIN_AUTO_NETWORK_INFO -->' <<<"$EXISTING"; then
    PREFIX=$(printf '%s\n' "$EXISTING" | sed '/<!-- BEGIN_AUTO_NETWORK_INFO -->/,$d')
    SUFFIX=$(printf '%s\n' "$EXISTING" | sed -n '/<!-- END_AUTO_NETWORK_INFO -->/,$p' | sed '1d')
    MERGED="${PREFIX}"$'\n'"${NEW_SEC}"$'\n'"${SUFFIX}"
  else
    MERGED="${NEW_SEC}"$'\n'"${EXISTING}"
  fi

  pvesh set /nodes/"$NODE"/"$API_TYPE"/"$ID"/config \
    --description "$MERGED"
  echo "[DONE] description updated"
else
  cat "$TMP_MD"
fi
