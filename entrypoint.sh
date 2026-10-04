#!/bin/bash
set -e

# ================================================
# グレースフルシャットダウン
# ================================================
SERVER_PID=""

shutdown_handler() {
    local msg="【$(date '+%Y-%m-%d %H:%M:%S')】シャットダウン信号を受信しました"
    echo ""
    echo "=========================================="
    echo "$msg"
    echo "=========================================="
    if [ -n "$LOG_FILE" ]; then
        echo "==========================================" >> "$LOG_FILE"
        echo "$msg" >> "$LOG_FILE"
        echo "==========================================" >> "$LOG_FILE"
    fi
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -TERM "$SERVER_PID"
        wait "$SERVER_PID" 2>/dev/null
    fi
    exit 0
}

trap 'shutdown_handler' SIGTERM SIGINT

# ================================================
# サーバーバイナリの準備
# server-bin/bedrock_server_edu の有無とバージョンファイルの有無で動作が変わる:
#   バイナリなし                        → 自動ダウンロード → server-bin/ に展開
#   バイナリあり + .server_version なし → 手動配置モード（そのまま使用）
#   バイナリあり + .server_version あり → 自動管理モード（リモートと比較して必要なら更新）
# ================================================
SERVER_BIN="/minecraft/bedrock_server_edu"
SERVER_BIN_DIR="/minecraft/server-bin"
SHARED_BIN="${SERVER_BIN_DIR}/bedrock_server_edu"
SERVER_ZIP="/tmp/server.zip"
VERSION_FILE="${SERVER_BIN_DIR}/.server_version"
DOWNLOAD_URL="https://aka.ms/downloadmee-linuxserver"

apply_server_files() {
    # allowlist.json / permissions.json / packetlimitconfig.json はユーザーデータのため上書きしない
    find "${SERVER_BIN_DIR}" -maxdepth 1 -mindepth 1 \
        ! -name "allowlist.json" \
        ! -name "permissions.json" \
        ! -name "packetlimitconfig.json" \
        -exec cp -r {} /minecraft/ \;
    chmod +x "$SERVER_BIN"
}

fetch_remote_version() {
    local headers
    headers=$(wget --spider -S --no-cache --user-agent="Mozilla/5.0" "$DOWNLOAD_URL" 2>&1 || true)
    local etag modified
    etag=$(echo "$headers" | grep -i "ETag:" | tail -1 | sed 's/.*ETag: *//i' | tr -d '\r')
    modified=$(echo "$headers" | grep -i "Last-Modified:" | tail -1 | sed 's/.*Last-Modified: *//i' | tr -d '\r')
    echo "${etag:-$modified}"
}

download_server() {
    wget -q --show-progress --no-cache --user-agent="Mozilla/5.0" -O "$SERVER_ZIP" "$DOWNLOAD_URL"
    unzip -o "$SERVER_ZIP" -d "$SERVER_BIN_DIR"
    rm -f "$SERVER_ZIP"
    chmod +x "$SHARED_BIN"
}

if [ ! -f "$SHARED_BIN" ]; then
    echo "サーバーバイナリが見つかりません。ダウンロードします..."
    REMOTE_VERSION=$(fetch_remote_version)
    download_server
    [ -n "$REMOTE_VERSION" ] && echo "$REMOTE_VERSION" > "$VERSION_FILE"
    echo "ダウンロードが完了しました。"
    apply_server_files
elif [ ! -f "$VERSION_FILE" ]; then
    echo "手動配置バイナリを使用します。"
    apply_server_files
else
    REMOTE_VERSION=$(fetch_remote_version)
    LOCAL_VERSION=$(cat "$VERSION_FILE")
    if [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
        echo "新しいバージョンが利用可能です。更新します..."
        download_server
        echo "$REMOTE_VERSION" > "$VERSION_FILE"
        echo "更新が完了しました。"
    else
        echo "サーバーは最新です。"
    fi
    apply_server_files
fi

# ================================================
# 設定値
# ================================================
WORLD_DATA_DIR="/minecraft/world-data"
SESSION_DIR="sessions"
SESSION_FILE="${SESSION_DIR}/edu_server_session.json"

# ================================================
# ワールドデータディレクトリの初期化
# ================================================
mkdir -p "${WORLD_DATA_DIR}"
mkdir -p "${WORLD_DATA_DIR}/worlds"
mkdir -p "${WORLD_DATA_DIR}/worlds/${LEVEL_NAME}"

# ================================================
# 初期ファイル作成（存在しない場合のみ）
# ================================================
if [ ! -f "${WORLD_DATA_DIR}/allowlist.json" ]; then
    echo '[]' > "${WORLD_DATA_DIR}/allowlist.json"
fi

if [ ! -f "${WORLD_DATA_DIR}/permissions.json" ]; then
    if [ -n "${OPERATOR_XUID}" ]; then
        cat > "${WORLD_DATA_DIR}/permissions.json" << EOF
[
   {
      "permission" : "operator",
      "xuid" : "${OPERATOR_XUID}"
   }
]
EOF
    else
        echo '[]' > "${WORLD_DATA_DIR}/permissions.json"
    fi
fi

if [ ! -f "${WORLD_DATA_DIR}/packetlimitconfig.json" ]; then
    cat > "${WORLD_DATA_DIR}/packetlimitconfig.json" << 'EOF'
{
	"limitGroups": [{
		"minecraftPacketIds": [193, 4],
		"algorithm": {
            "name": "BucketPacketLimitAlgorithm",
            "params": {
                "drainRatePerSec": 0.0013,
                "maxBucketSize": 1
            }
        }
	}, {
		"minecraftPacketIds": [9],
        "algorithm": {
            "name": "BucketPacketLimitAlgorithm",
            "params": {
                "drainRatePerSec": 10,
                "maxBucketSize": 50
            }
        }
	}]
}
EOF
fi

# ================================================
# ワールドデータフォルダへのシンボリックリンク作成
# ================================================
# サーバーが /minecraft 直下から参照するため、シンボリックリンクでマップ
ln -sf "${WORLD_DATA_DIR}/allowlist.json" allowlist.json
ln -sf "${WORLD_DATA_DIR}/permissions.json" permissions.json
ln -sf "${WORLD_DATA_DIR}/packetlimitconfig.json" packetlimitconfig.json

# ゲームワールドデータへのシンボリックリンク
ln -sf "${WORLD_DATA_DIR}/worlds" worlds

# ホスト側パック置き場を確保（シンボリックリンクは使わない）
# ※ サーバーバイナリが unzip 時に /minecraft/behavior_packs/ を実ディレクトリとして作成するため、
#   ln -sf はシンボリックリンクをその中に作ってしまい二重パスになる。
#   代わりに起動時にホスト側のパックをサーバーの実ディレクトリへ直接コピーする。
mkdir -p "${WORLD_DATA_DIR}/behavior_packs"
mkdir -p "${WORLD_DATA_DIR}/resource_packs"

# worlds/world{N}/behavior_packs/ 内のユーザー提供パックをサーバーの behavior_packs/ にコピー
for user_pack in "${WORLD_DATA_DIR}/behavior_packs"/*/; do
    [ -d "$user_pack" ] || continue
    pack_name=$(basename "$user_pack")
    rm -rf "behavior_packs/${pack_name}"
    cp -r "$user_pack" "behavior_packs/${pack_name}"
    echo "ユーザーパック配置 (behavior): ${pack_name}"
done

# worlds/world{N}/resource_packs/ 内のユーザー提供パックをサーバーの resource_packs/ にコピー
for user_pack in "${WORLD_DATA_DIR}/resource_packs"/*/; do
    [ -d "$user_pack" ] || continue
    pack_name=$(basename "$user_pack")
    rm -rf "resource_packs/${pack_name}"
    cp -r "$user_pack" "resource_packs/${pack_name}"
    echo "ユーザーパック配置 (resource): ${pack_name}"
done

# ================================================
# 公開アドレスの LAN / WAN 切り替え
# SERVER_NETWORK (lan|wan) に応じて SERVER_PUBLIC_IP を確定する
# ================================================
SERVER_NETWORK="${SERVER_NETWORK:-lan}"
if [ "$SERVER_NETWORK" = "wan" ]; then
    SERVER_PUBLIC_IP="$SERVER_PUBLIC_IP_WAN"
else
    SERVER_PUBLIC_IP="$SERVER_PUBLIC_IP_LAN"
fi
# 選択したほうが空なら、もう一方にフォールバック（設定漏れ対策）
if [ -z "$SERVER_PUBLIC_IP" ]; then
    SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP_LAN:-$SERVER_PUBLIC_IP_WAN}"
    echo "警告: SERVER_NETWORK=${SERVER_NETWORK} 用のアドレスが未設定のためフォールバックしました (server-public-ip=${SERVER_PUBLIC_IP})"
fi
export SERVER_PUBLIC_IP
echo "公開アドレス: server-public-ip=${SERVER_PUBLIC_IP} (network=${SERVER_NETWORK})"

# ================================================
# NetherNet（transport=nethernet）用の UDP ポート設定
# ================================================
# 公式 how-to（bedrock_server_how_to.html）より:
#   raknet   … server-port を UDP で直接待ち受ける（従来方式）
#   nethernet… server-port は HTTP シグナリング用の「TCP」デュアルスタックソケット。
#              ゲーム通信はクライアントごとにネゴシエートされる UDP で流れ、
#              既定では OS のエフェメラルポートから確保される。
#
# 【重要】NetherNet は「参加したプレイヤー1人につき UDP ポート1つ」を確保する。
# プレイヤーが自宅で世界をホストする P2P 実装をそのまま流用しているためで、
# server-udp-ports に単一ポートを書くと内部の min=max となり、同時1接続しか
# 受け付けられなくなる（1人目は入れるので、2人目が入れないまで気づけない）。
# したがって必ず「同時接続数ぶんの範囲」を指定する。
#   書式: [ip:]external[-external]:internal[-internal]
# raknet のときは無視されるプロパティなので、混乱を避けるため一切書き込まない。
TRANSPORT="${TRANSPORT:-raknet}"
if [ "$TRANSPORT" = "nethernet" ]; then
    if [ -n "${SERVER_UDP_PORTS:-}" ]; then
        # .env で明示指定された場合はそのまま使う（NAT で外部ポートを付け替える等の
        # 特殊構成向け）。本数が足りないと静かに接続不能になるため検査して警告する。
        _udp_count=0
        _old_ifs="$IFS"
        IFS=','
        for _entry in $SERVER_UDP_PORTS; do
            # 内部側は必ず最後の ':' 区切りフィールド（IPv6 リテラル表記でも同じ）
            _internal="${_entry##*:}"
            case "$_internal" in
                *-*)
                    _udp_count=$((_udp_count + ${_internal##*-} - ${_internal%%-*} + 1))
                    ;;
                *)
                    _udp_count=$((_udp_count + 1))
                    ;;
            esac
        done
        IFS="$_old_ifs"
        if [ "$_udp_count" -le 1 ]; then
            echo "警告: SERVER_UDP_PORTS の内部ポートが1つしかありません (${SERVER_UDP_PORTS})"
            echo "      NetherNet は接続ごとに UDP ポートを1つ使うため、この設定では"
            echo "      同時1接続しか参加できません。範囲指定に変更してください"
        elif [ "$_udp_count" -lt "${MAX_PLAYERS:-0}" ]; then
            echo "警告: SERVER_UDP_PORTS の内部ポート数 (${_udp_count}) が max-players (${MAX_PLAYERS}) 未満です"
            echo "      同時接続が ${_udp_count} 人を超えると参加できなくなる可能性があります"
        fi
    elif [ -n "${SERVER_UDP_RANGE:-}" ]; then
        # 通常の経路。make add が .env に採番した範囲から組み立てる。
        # compose が同じ範囲をホスト側へ公開しているので、内部＝外部で対応させる。
        SERVER_UDP_PORTS="${SERVER_PUBLIC_IP}:${SERVER_UDP_RANGE}:${SERVER_UDP_RANGE}"
    else
        echo "エラー: transport=nethernet ですが、ゲーム通信用の UDP ポート範囲が未設定です" >&2
        echo "      NetherNet は接続ごとに UDP ポートを1つ消費するため、範囲の確保が必須です" >&2
        echo "      （単一ポートで起動すると同時1接続に制限されるため、ここで停止します）" >&2
        echo "" >&2
        echo "      ホスト側で割り当てを確認し、.env に追記してください:" >&2
        echo "        make ports       # 現在の割り当てと空きブロックを表示" >&2
        echo "        # .env に SERVER_UDP_RANGE_WORLD_<N>=<PORT+1>-<PORT+99> の形式で追記" >&2
        echo "        make up          # compose 側の公開ポートも再生成される" >&2
        exit 1
    fi
    # 補足: server-udp-ports はカンマ区切りで LAN/WAN 両方のアドレスを広告できるが、
    # クライアントはまず server-public-ip:server-port へシグナリング接続する必要があり、
    # その宛先は1つしか持てない。データ経路だけ増やしても「校内は LAN・校外は WAN」の
    # 両立にはならないため、LAN/WAN の切り替えは SERVER_NETWORK で従来どおり行う。
    export SERVER_UDP_PORTS
    echo "NetherNet: シグナリング=${SERVER_PORT}/tcp, server-udp-ports=${SERVER_UDP_PORTS}"
else
    # raknet では無視されるプロパティなので書き込まない
    unset SERVER_UDP_PORTS
fi

# ================================================
# 環境変数からserver.propertiesの値を動的に更新
# property-definitions.json に基づいてループ処理
# ================================================
PROP_DEFS="/minecraft/property-definitions.json"
if [ -f "server.properties" ] && [ -f "$PROP_DEFS" ]; then
    jq -r 'to_entries[] | "\(.key) \(.value.env)"' "$PROP_DEFS" | while read -r prop_name env_name; do
        env_value="${!env_name}"
        if [ -n "$env_value" ]; then
            if grep -q "^${prop_name}=" server.properties; then
                sed -i "s|^${prop_name}=.*|${prop_name}=${env_value}|" server.properties
            else
                # 既定でコメントアウトされているプロパティ（server-udp-ports 等）は追記する
                echo "${prop_name}=${env_value}" >> server.properties
            fi
        fi
    done
fi

# ================================================
# 初回起動チェック
# ================================================
FIRST_BOOT=false
if [ ! -f "${SESSION_FILE}" ] || [ ! -s "${SESSION_FILE}" ]; then
    FIRST_BOOT=true
    # 空ファイルを作成（存在確認用）
    touch "${SESSION_FILE}"
fi

# セッションファイルへのシンボリックリンクを作成（サーバーが参照するため）
ln -sf "${SESSION_FILE}" edu_server_session.json

# ================================================
# ログディレクトリの初期化
# ================================================
mkdir -p /minecraft/logs

# ログファイルパス
LOG_FILE="/minecraft/logs/server_$(date +%Y-%m-%d).log"

# ================================================
# サーバー起動時のメッセージをログに出力
# ================================================
echo "==========================================" >> "$LOG_FILE"
echo "【$(date '+%Y-%m-%d %H:%M:%S')】Minecraft Education Edition Server Start" >> "$LOG_FILE"
echo "World: ${LEVEL_NAME} | Mode: ${GAMEMODE} | Port: ${SERVER_PORT}" >> "$LOG_FILE"
if [ "$FIRST_BOOT" = true ]; then
    echo "【初回起動】Device Code認証が必要です" >> "$LOG_FILE"
fi
echo "==========================================" >> "$LOG_FILE"

# 初回起動メッセージをコンソール出力
if [ "$FIRST_BOOT" = true ]; then
    echo "=============================================="
    echo "【${LEVEL_NAME}】初回起動 - Device Code認証が必要"
    echo "=============================================="
fi

# ================================================
# サーバー起動（ログ出力 + シグナルハンドリング）
# ================================================
./bedrock_server_edu 2>&1 | tee -a "$LOG_FILE" &

sleep 1
SERVER_PID=$(pgrep -f bedrock_server_edu)

# サーバープロセスの終了を待機
wait "$SERVER_PID"
