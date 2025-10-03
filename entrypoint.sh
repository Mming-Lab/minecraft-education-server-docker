#!/bin/bash
set -e

# 初期ファイル作成（存在しない場合のみ）
if [ ! -f "allowlist.json" ]; then
    echo '[]' > allowlist.json
fi

if [ ! -f "permissions.json" ]; then
    echo '[]' > permissions.json
fi

if [ ! -f "packetlimitconfig.json" ]; then
    cat > packetlimitconfig.json << 'EOF'
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

# 環境変数からserver.propertiesの値を動的に更新
if [ -f "server.properties" ]; then
    # server-public-ip
    if [ -n "$SERVER_PUBLIC_IP" ]; then
        sed -i "s|^server-public-ip=.*|server-public-ip=${SERVER_PUBLIC_IP}|" server.properties
    fi

    # server-port
    if [ -n "$SERVER_PORT" ]; then
        sed -i "s|^server-port=.*|server-port=${SERVER_PORT}|" server.properties
    fi

    # server-portv6
    if [ -n "$SERVER_PORTV6" ]; then
        sed -i "s|^server-portv6=.*|server-portv6=${SERVER_PORTV6}|" server.properties
    fi

    # gamemode
    if [ -n "$GAMEMODE" ]; then
        sed -i "s|^gamemode=.*|gamemode=${GAMEMODE}|" server.properties
    fi

    # difficulty
    if [ -n "$DIFFICULTY" ]; then
        sed -i "s|^difficulty=.*|difficulty=${DIFFICULTY}|" server.properties
    fi

    # allow-cheats
    if [ -n "$ALLOW_CHEATS" ]; then
        sed -i "s|^allow-cheats=.*|allow-cheats=${ALLOW_CHEATS}|" server.properties
    fi

    # chat-restriction
    if [ -n "$CHAT_RESTRICTION" ]; then
        sed -i "s|^chat-restriction=.*|chat-restriction=${CHAT_RESTRICTION}|" server.properties
    fi

    # max-players
    if [ -n "$MAX_PLAYERS" ]; then
        sed -i "s|^max-players=.*|max-players=${MAX_PLAYERS}|" server.properties
    fi

    # allow-list
    if [ -n "$ALLOW_LIST" ]; then
        sed -i "s|^allow-list=.*|allow-list=${ALLOW_LIST}|" server.properties
    fi

    # view-distance
    if [ -n "$VIEW_DISTANCE" ]; then
        sed -i "s|^view-distance=.*|view-distance=${VIEW_DISTANCE}|" server.properties
    fi

    # tick-distance
    if [ -n "$TICK_DISTANCE" ]; then
        sed -i "s|^tick-distance=.*|tick-distance=${TICK_DISTANCE}|" server.properties
    fi

    # player-idle-timeout
    if [ -n "$PLAYER_IDLE_TIMEOUT" ]; then
        sed -i "s|^player-idle-timeout=.*|player-idle-timeout=${PLAYER_IDLE_TIMEOUT}|" server.properties
    fi

    # max-threads
    if [ -n "$MAX_THREADS" ]; then
        sed -i "s|^max-threads=.*|max-threads=${MAX_THREADS}|" server.properties
    fi

    # level-name
    if [ -n "$LEVEL_NAME" ]; then
        sed -i "s|^level-name=.*|level-name=${LEVEL_NAME}|" server.properties
    fi

    # level-seed
    if [ -n "$LEVEL_SEED" ]; then
        sed -i "s|^level-seed=.*|level-seed=${LEVEL_SEED}|" server.properties
    fi

    # default-player-permission-level
    if [ -n "$DEFAULT_PLAYER_PERMISSION_LEVEL" ]; then
        sed -i "s|^default-player-permission-level=.*|default-player-permission-level=${DEFAULT_PLAYER_PERMISSION_LEVEL}|" server.properties
    fi

    # texturepack-required
    if [ -n "$TEXTUREPACK_REQUIRED" ]; then
        sed -i "s|^texturepack-required=.*|texturepack-required=${TEXTUREPACK_REQUIRED}|" server.properties
    fi

    # content-log-file-enabled
    if [ -n "$CONTENT_LOG_FILE_ENABLED" ]; then
        sed -i "s|^content-log-file-enabled=.*|content-log-file-enabled=${CONTENT_LOG_FILE_ENABLED}|" server.properties
    fi
fi

# 初回起動チェック
if [ ! -f "edu_server_session.json" ] || [ ! -s "edu_server_session.json" ]; then
    echo "===================================="
    echo "初回起動 - Device Code認証が必要"
    echo "===================================="
    # 空ファイルを作成（存在確認用）
    touch edu_server_session.json
fi

# サーバー起動
exec ./bedrock_server_edu
