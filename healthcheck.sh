#!/bin/bash
# ================================================
# ヘルスチェック
# ================================================
# プロセスの生存だけでなく、実際にポートを待ち受けているかまで確認する。
#
# プロセスの有無だけ見ていると、サーバーが起動時に Microsoft のサービスへ
# 接続できず「Could not connect to Minecraft services」→「Server stop requested」
# で止まったあとも healthy のままになる（ホスト側のファイアウォールが古い
# FORWARD ルールを持っていると起きる。manual/troubleshooting.md を参照）。
# 待ち受けソケットまで見れば、この状態を unhealthy として検知できる。
#
# transport で見るソケットが変わる:
#   raknet    … server-port を UDP で直接待ち受ける
#   nethernet … server-port は HTTP シグナリング用の TCP。ゲーム通信の UDP は
#               接続ごとに確保されるため、待ち受けの判定には使えない
#
# 判定に使う ss は iproute2（Dockerfile でインストール済み）。
# UDP には LISTEN 状態が無いので、bind されているか（UNCONN）を見る。

# 1. プロセスの生存
pgrep -f bedrock_server_edu > /dev/null 2>&1 || exit 1

# 2. 待ち受けソケット
# 環境変数は compose の environment から入る。entrypoint 側と同じ既定値を使う
PORT="${SERVER_PORT:-19132}"
TRANSPORT="${TRANSPORT:-raknet}"

# 想定外の値（綴り違いなど）のときはソケット判定を行わない。
# 見る先を誤って永久に unhealthy になるより、プロセス生存の判定にとどめる方が安全。
case "$TRANSPORT" in
    nethernet)
        ss -ltnH "sport = :${PORT}" 2>/dev/null | grep -q . || exit 1
        ;;
    raknet)
        ss -lunH "sport = :${PORT}" 2>/dev/null | grep -q . || exit 1
        ;;
    *)
        echo "警告: TRANSPORT の値が想定外です（${TRANSPORT}）。待ち受けの確認を省略します" >&2
        ;;
esac

exit 0
