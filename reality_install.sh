#!/bin/bash


function check() {
    if [ $(id -u) != "0" ]; then
        echo "错误：必须使用root用户运行此脚本！"
        exit 1
    fi
    if ![pidof systemd > /dev/null]; then
        echo "系统不支持systemd"
        exit 1
    fi
    echo "检查系统发行版"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        release=$ID
        version=$VERSION_ID
        echo "系统发行版为：$release"
        echo "系统版本为：$version"
    else
        echo "无法检测到系统发行版信息。"
        exit 1
    fi
    arch=$(uname -m)
    if [ $arch == "x86_64" ]; then
        arch="64"
        echo "系统架构为：$arch"
    elif [ $arch == "aarch64" ]; then
        arch="arm64-v8a"
        echo "系统架构为：$arch"
    else
        echo "系统架构为：$arch"
        echo "不支持的系统架构。"
        exit 1
    fi
}

function xray_install_path() {
  xray_path="/opt/xray"
  read -p "请输入Xray安装路径(默认/opt/xray)" input_path
  if [ -n "$input_path" ]; then
        xray_path="$input_path"
    fi
  if [ -f "$xray_path" ]; then
      echo "目标文件已存在：$xray_path"
      exit 1
  fi
}

function install_packages() {
    echo "安装必要的工具"
    if [ "$release" == "centos" ]; then
        yum install -y curl wget unzip zip jq > /dev/null 2>&1
    else
        apt-get install -y curl wget unzip zip jq > /dev/null 2>&1
    fi
}

function install_xray() {
  echo "开始下载Xray"
  latest_release=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest)
  version=$(echo $latest_release | jq -r '.tag_name')
  wget -q --show-progress --progress=bar:force -O /tmp/Xray.zip https://github.com/XTLS/Xray-core/releases/download/$version/Xray-linux-$arch.zip
  unzip /tmp/Xray.zip -d $xray_path
  chmod +x $xray_path/xray
  if [[ -f /etc/systemd/system/xray.service ]]; then
    echo "/etc/systemd/system/xray.service 文件已存在。"
  else
    cat > /etc/systemd/system/xray.service << EOF
    [Unit]
    Description=Xray
  
    [Service]
    ExecStart=$xray_path/xray -c config.json
    WorkingDirectory=$xray_path
    Restart=on-failure
  
    [Install]
    WantedBy=default.target
EOF
    echo "/etc/systemd/system/xray.service 文件已创建。"
  fi
  read -p "Systemd守护进程写入完成，是否开机自启动？(Y/n)" auto_start
  if [ "$auto_start" == "Y" ]||[ "$auto_start" == "y" ]; then
      systemctl enable xray
  fi
}

function xray_config() {
  read -p "是否自动生成UUID(Y/N)" uuid
  if [[ "$uuid" == "Y" || "$uuid" == "y" || "$uuid" != "N" && "$uuid" != "n" ]]; then
      uuid=$(cat /proc/sys/kernel/random/uuid)
      echo "UUID为：$uuid"
  else
      read -p "请输入UUID:" uuid
  fi

  read -p "请输入端口号(默认8080)：" port
  if [[ -z "$port" ]]; then
    port=8080
  elif ! [[ "$port" =~ ^[0-9]+$ ]]; then
    echo "错误：端口号必须是数字。"
    exit 1
  fi
  echo "端口：$port"

  read -p "是否自动生成公私钥(Y/n)：" key
  if [[ "$key" =~ ^[Yy]$ || ! "$key" =~ ^[Nn]$ ]]; then
    # 使用xray x25519生成公私钥并解析值
    key=$($xray_path/xray x25519)
    private_key=$(echo "$key" | grep -oP 'Private key: \K[^ ]+')
    public_key=$(echo "$key" | grep -oP 'Public key: \K[^ ]+')
    echo "公钥为：$public_key"
    echo "私钥为：$private_key"
  else
    read -p "请输入公钥:" public_key
    read -p "请输入私钥:" private_key
  fi

  echo "预设伪装域名：1.addons.mozilla.org 2.icloud.cdn-apple.com 3.dl.google.com 4.自定义伪装域名"
  read -p "请选择伪装域名(默认2):" domain
  case "$domain" in
    1) domain="addons.mozilla.org" ;;
    2) domain="icloud.cdn-apple.com" ;;
    3) domain="dl.google.com" ;;
    4) read -p "请输入自定义伪装域名:" domain ;;
    *) domain="icloud.cdn-apple.com";echo "选择(2)" ;;
  esac
  echo "伪装域名：$domain"

  echo "选择指纹: 1.firefox 2.chrome 3.360 4.qq 5.edge 6.android 7.safari 8.ios"
  read -p "请选择或输入自定义指纹(默认8):" fingerpint
  case "$fingerpint" in
      1) fingerpint="firefox" ;;
      2) fingerpint="chrome" ;;
      3) fingerpint="360" ;;
      4) fingerpint="qq" ;;
      5) fingerpint="edge" ;;
      6) fingerpint="android" ;;
      7) fingerpint="safari" ;;
      8) fingerpint="ios" ;;
      *) fingerpint="ios";echo "选择(8)" ;;
  esac
  echo "生成配置文件"
  cat > $xray_path/config.json << EOF
  {
    "log": null,
    "routing": {
      "rules": [
        {
          "inboundTag": [
            "api"
          ],
          "outboundTag": "api",
          "type": "field"
        },
        {
          "ip": [
            "geoip:private"
          ],
          "outboundTag": "blocked",
          "type": "field"
        },
        {
          "outboundTag": "blocked",
          "protocol": [
            "bittorrent"
          ],
          "type": "field"
        }
      ]
    },
    "dns": null,
    "inbounds": [
      {
        "listen": "127.0.0.1",
        "port": 62789,
        "protocol": "dokodemo-door",
        "settings": {
          "address": "127.0.0.1"
        },
        "streamSettings": null,
        "tag": "api",
        "sniffing": null
      },
      {
        "listen": null,
        "port": $port,
        "protocol": "vless",
        "settings": {
          "clients": [
            {
              "id": "$uuid",
              "email": "test",
              "flow": "xtls-rprx-vision"
          }
          ],
          "decryption": "none",
          "fallbacks": []
        },
        "streamSettings": {
          "network": "tcp",
          "security": "reality",
          "realitySettings": {
            "show": false,
            "dest": "$domain:443",
            "xver": 0,
            "serverNames": [
              "$domain"
            ],
            "privateKey": "$private_key",
            "publicKey": "$public_key",
            "minClient": "",
            "maxClient": "",
            "maxTimediff": 0,
            "shortIds": [
              "",
              "14",
              "d580",
              "aa4bde",
              "63a83b07"
            ]
          },
          "tcpSettings": {
            "header": {
              "type": "none"
            },
            "acceptProxyProtocol": false
          }
        },
        "tag": "inbound-8080",
        "sniffing": {
          "enabled": true,
          "destOverride": [
            "http",
            "tls",
            "quic"
          ]
        }
      }
    ],
    "outbounds": [
      {
        "protocol": "freedom",
        "settings": {}
      },
      {
        "protocol": "blackhole",
        "settings": {},
        "tag": "blocked"
      }
    ],
    "transport": null,
    "policy": {
      "levels": {
        "0": {
          "handshake": 10,
          "connIdle": 100,
          "uplinkOnly": 2,
          "downlinkOnly": 3,
          "statsUserUplink": true,
          "statsUserDownlink": true,
          "bufferSize": 10240
        }
      },
      "system": {
        "statsInboundDownlink": true,
        "statsInboundUplink": true
      }
    },
    "api": {
      "services": [
       "HandlerService",
        "LoggerService",
        "StatsService"
      ],
      "tag": "api"
    },
    "stats": {},
    "reverse": null,
    "fakeDns": null
  }
EOF
  echo "配置文件生成完毕"
}

function xray_finish() {
  echo "Xray安装完毕"
  systemctl start xray > /dev/null 2>&1

  if systemctl is-active --quiet xray; then
    echo "Xray成功启动"
  else
    echo "Xray启动失败，请检查日志"
    systemctl status xray
    exit 1
  fi

  ip=$(curl -4 -s https://api64.ipify.org)
  vless="vless://$uuid@$ip:$port?security=reality&sni=$domain&fp=$fingerpint&pbk=$public_key&type=tcp&flow=xtls-rprx-vision&encryption=none#$ip:$port"
  echo "服务器IP：$ip"
  echo "端口：$port"
  echo "UUID：$uuid"
  echo "协议: vless"
  echo "加密方式: none"
  echo "流控: xtls-rprx-vision"
  echo "传输协议: tcp"
  echo "伪装类型: none"
  echo "伪装路径: none"
  echo "传输层安全: reality"
  echo "伪装域名: $domain"
  echo "指纹: $fingerpint"
  echo "公钥: $public_key"
  echo "链接：$vless"
  echo "请复制链接到客户端"
  rm /tmp/Xray.zip -f
}

check
xray_install_path
install_packages
install_xray
xray_config
xray_finish