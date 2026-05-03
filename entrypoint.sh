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
    cp -r "${SERVER_BIN_DIR}/." /minecraft/
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
    echo '[]' > "${WORLD_DATA_DIR}/permissions.json"
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
# 環境変数からserver.propertiesの値を動的に更新
# property-definitions.json に基づいてループ処理
# ================================================
PROP_DEFS="/minecraft/property-definitions.json"
if [ -f "server.properties" ] && [ -f "$PROP_DEFS" ]; then
    jq -r 'to_entries[] | "\(.key) \(.value.env)"' "$PROP_DEFS" | while read -r prop_name env_name; do
        env_value="${!env_name}"
        if [ -n "$env_value" ]; then
            sed -i "s|^${prop_name}=.*|${prop_name}=${env_value}|" server.properties
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
