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
# サーバーバイナリの自動更新
# ================================================
SERVER_BIN="/minecraft/bedrock_server_edu"
SERVER_ZIP="/tmp/server.zip"
VERSION_FILE="/minecraft/.server_version"
DOWNLOAD_URL="https://aka.ms/downloadmee-linuxserver"


# リモートのファイル情報を取得（ETag or Last-Modified でバージョン判定）
REMOTE_HEADERS=$(wget --spider -S "$DOWNLOAD_URL" 2>&1 || true)
REMOTE_ETAG=$(echo "$REMOTE_HEADERS" | grep -i "ETag:" | tail -1 | sed 's/.*ETag: *//i' | tr -d '\r')
REMOTE_MODIFIED=$(echo "$REMOTE_HEADERS" | grep -i "Last-Modified:" | tail -1 | sed 's/.*Last-Modified: *//i' | tr -d '\r')
REMOTE_VERSION="${REMOTE_ETAG:-$REMOTE_MODIFIED}"

# ローカルのバージョン情報と比較
LOCAL_VERSION=""
if [ -f "$VERSION_FILE" ]; then
    LOCAL_VERSION=$(cat "$VERSION_FILE")
fi

NEED_UPDATE=false
if [ ! -f "$SERVER_BIN" ]; then
    echo "サーバーバイナリが見つかりません。ダウンロードします..."
    NEED_UPDATE=true
elif [ -n "$REMOTE_VERSION" ] && [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ]; then
    echo "サーバーの新しいバージョンが利用可能です。更新します..."
    NEED_UPDATE=true
else
    echo "サーバーは最新です。"
fi

if [ "$NEED_UPDATE" = true ]; then
    wget -q --show-progress -O "$SERVER_ZIP" "$DOWNLOAD_URL"
    unzip -o "$SERVER_ZIP" -d /minecraft
    rm -f "$SERVER_ZIP"
    chmod +x "$SERVER_BIN"
    if [ -n "$REMOTE_VERSION" ]; then
        echo "$REMOTE_VERSION" > "$VERSION_FILE"
    fi
    echo "サーバーの更新が完了しました。"
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

# ================================================
# 初期ファイル作成（存在しない場合のみ）
# ================================================
if [ ! -f "${WORLD_DATA_DIR}/allowlist.json" ]; then
    echo '[]' > "${WORLD_DATA_DIR}/allowlist.json"
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
ln -sf "${WORLD_DATA_DIR}/packetlimitconfig.json" packetlimitconfig.json

# ゲームワールドデータへのシンボリックリンク
ln -sf "${WORLD_DATA_DIR}/worlds" worlds


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
