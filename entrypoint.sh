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

# アドオンのパック適用設定（存在しないか空・無効な JSON の場合に初期化）
# ホスト側の worlds/{LEVEL_NAME}/ から直接編集可能
if ! jq '.' "${WORLD_DATA_DIR}/worlds/${LEVEL_NAME}/world_behavior_packs.json" > /dev/null 2>&1; then
    echo '[]' > "${WORLD_DATA_DIR}/worlds/${LEVEL_NAME}/world_behavior_packs.json"
fi
if ! jq '.' "${WORLD_DATA_DIR}/worlds/${LEVEL_NAME}/world_resource_packs.json" > /dev/null 2>&1; then
    echo '[]' > "${WORLD_DATA_DIR}/worlds/${LEVEL_NAME}/world_resource_packs.json"
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

# アドオン（behavior_packs / resource_packs）へのシンボリックリンク
# worlds/world{N}/behavior_packs/ にパックを配置することで有効になる
mkdir -p "${WORLD_DATA_DIR}/behavior_packs"
mkdir -p "${WORLD_DATA_DIR}/resource_packs"
ln -sf "${WORLD_DATA_DIR}/behavior_packs" behavior_packs
ln -sf "${WORLD_DATA_DIR}/resource_packs" resource_packs

# ================================================
# アドオン自動配置
# /minecraft/addons/ 以下の全フォルダを behavior_packs/ にコピーし
# world_behavior_packs.json に自動登録する
# ================================================
ADDONS_SRC="/minecraft/addons"
PACKS_FILE="${WORLD_DATA_DIR}/worlds/${LEVEL_NAME}/world_behavior_packs.json"

if [ -d "$ADDONS_SRC" ]; then
    for addon_dir in "$ADDONS_SRC"/*/; do
        [ -d "$addon_dir" ] || continue
        addon_name=$(basename "$addon_dir")
        manifest="${addon_dir}manifest.json"
        [ -f "$manifest" ] || continue

        # behavior_packs/ にコピー（既存を削除してから上書き）
        # cp -r はコピー先が存在すると内部に重複フォルダを作るため事前削除が必要
        rm -rf "${WORLD_DATA_DIR}/behavior_packs/${addon_name}"
        cp -r "$addon_dir" "${WORLD_DATA_DIR}/behavior_packs/${addon_name}"

        # pack_id と version を取得
        pack_id=$(jq -r '.header.uuid' "$manifest")
        pack_version=$(jq -c '.header.version' "$manifest")

        # world_behavior_packs.json に未登録なら追加
        if ! jq -e ".[] | select(.pack_id == \"$pack_id\")" "$PACKS_FILE" > /dev/null 2>&1; then
            jq --arg id "$pack_id" --argjson ver "$pack_version" \
                '. += [{"pack_id": $id, "version": $ver}]' "$PACKS_FILE" > /tmp/packs_tmp.json
            mv /tmp/packs_tmp.json "$PACKS_FILE"
            echo "アドオン登録: ${addon_name} (${pack_id})"
        else
            echo "アドオン配置: ${addon_name} (登録済み)"
        fi
    done
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
# Beta APIs 有効化（level.dat が存在する場合のみ）
# 初回起動ではサーバーが level.dat を生成するため、2回目以降に適用される
# ================================================
LEVEL_DAT="${WORLD_DATA_DIR}/worlds/${LEVEL_NAME}/level.dat"
if [ -f "$LEVEL_DAT" ]; then
    echo "Beta APIs を有効化しています: $LEVEL_DAT"
    python3 /minecraft/enable_beta_apis.py "$LEVEL_DAT" 2>&1 | tee -a "$LOG_FILE"
else
    echo "level.dat が未生成のため Beta APIs 設定をスキップします（初回起動後に再起動してください）"
fi

# ================================================
# サーバー起動（ログ出力 + シグナルハンドリング）
# ================================================
./bedrock_server_edu 2>&1 | tee -a "$LOG_FILE" &

sleep 1
SERVER_PID=$(pgrep -f bedrock_server_edu)

# サーバープロセスの終了を待機
wait "$SERVER_PID"
