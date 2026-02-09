#!/bin/bash
# ヘルスチェック: サーバープロセスの生存確認
# bedrock_server_edu プロセスが存在するかチェック
pgrep -f bedrock_server_edu > /dev/null 2>&1
