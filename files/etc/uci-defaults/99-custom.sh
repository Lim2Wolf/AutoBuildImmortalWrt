#!/bin/sh
# 99-custom.sh：immortalwrt 固件首次启动时运行的脚本
LOGFILE="/tmp/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >> $LOGFILE

# 默认防火墙规则：允许 WAN 区域访问本地服务，方便首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名解析（解决安卓 TV 联网问题）
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# PPPoE 设置读取（保留原逻辑）
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ -f "$SETTINGS_FILE" ]; then
  . "$SETTINGS_FILE"
else
  echo "PPPoE settings file not found. Skipping." >> $LOGFILE
fi

# 计算物理网卡数量
count=0
ifnames=""
for iface in /sys/class/net/*; do
  iface_name=$(basename "$iface")
  if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
    count=$((count + 1))
    ifnames="$ifnames $iface_name"
  fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1') # 去空格

if [ "$count" -eq 1 ]; then
  # 单网口设备：旁路由典型模式，自动获取 IP（不改 IP，避免冲突）
  uci set network.lan.proto='dhcp'
elif [ "$count" -gt 1 ]; then
  wan_ifname=$(echo "$ifnames" | awk '{print $1}')
  lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)

  uci set network.wan=interface
  uci set network.wan.device="$wan_ifname"
  uci set network.wan.proto='dhcp'

  uci set network.wan6=interface
  uci set network.wan6.device="$wan_ifname"
  uci set network.wan6.proto='dhcp'

  section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
  if [ -z "$section" ]; then
    echo "Error: cannot find device 'br-lan'." >> $LOGFILE
  else
    uci -q delete "network.$section.ports"
    for port in $lan_ifnames; do
      uci add_list "network.$section.ports"="$port"
    done
    echo "ports of device 'br-lan' are updated." >> $LOGFILE
  fi

  # 设置 LAN 口静态 IP（旁路由默认访问地址）
  uci set network.lan.proto='static'
  uci set network.lan.ipaddr='192.168.2.1'
  uci set network.lan.netmask='255.255.255.0'
  uci set network.lan.gateway='192.168.2.31'
  uci set network.lan.dns='192.168.2.31'
  echo "LAN configured for 192.168.2.1 with gateway 192.168.2.31" >> $LOGFILE

  # 可选：启用 PPPoE 拨号（如启用）
  if [ "$enable_pppoe" = "yes" ]; then
    uci set network.wan.proto='pppoe'
    uci set network.wan.username="$pppoe_account"
    uci set network.wan.password="$pppoe_password"
    uci set network.wan.peerdns='1'
    uci set network.wan.auto='1'
    uci set network.wan6.proto='none'
    echo "PPPoE enabled." >> $LOGFILE
  fi
fi

# 所有接口允许访问 ttyd 和 SSH
uci delete ttyd.@ttyd[0].interface
uci set dropbear.@dropbear[0].Interface=''

# 设置编译者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Compiled by wukongdaily"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

uci commit
exit 0
