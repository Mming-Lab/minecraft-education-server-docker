# Minecraft Education Edition Dedicated Server - Docker

Minecraft Education Edition Dedicated Serverを公式設定に準拠した完全な環境で実行。

## セットアップ

```bash
# 1. ビルド
docker-compose build

# 2. 起動
docker-compose up -d

# 3. 認証（初回のみ）
docker-compose logs -f minecraft-edu
```

## ディレクトリ構成
```
minecraft-education-server-docker/
├── Dockerfile                    # Ubuntu 22.04ベース
├── docker-compose.yml           # コンテナ設定
├── entrypoint.sh                # 起動スクリプト（自動生成処理含む）
├── .env                         # 環境変数設定（すべての設定を管理）
├── edu_server_session.json      # 認証セッション（初回は空、認証後に自動生成）
├── allowlist.json               # ホワイトリスト（ホストで編集可能）
├── permissions.json             # 権限設定（ホストで編集可能）
├── packetlimitconfig.json       # パケット制限設定（ホストで編集可能）
└── README.md                    # このファイル

# 以下はDocker起動時に自動作成されます
└── worlds/                      # ワールドデータ（永続化）

# 以下はコンテナ内でentrypoint.shが自動生成します
└── server.properties            # サーバー設定（.envから生成）
```

## 主要設定（.env）

### サーバー基本設定
```env
SERVER_PUBLIC_IP=localhost       # サーバーIPアドレス
SERVER_PORT=19132                # IPv4ポート
SERVER_PORTV6=19133             # IPv6ポート
```

### ゲーム設定
```env
GAMEMODE=creative                # ゲームモード (survival/creative/adventure)
DIFFICULTY=easy                  # 難易度 (peaceful/easy/normal/hard)
MAX_PLAYERS=40                   # 最大プレイヤー数
ALLOW_CHEATS=false              # チート許可
ALLOW_LIST=false                # ホワイトリスト有効化
CHAT_RESTRICTION=None           # チャット制限 (None/Dropped/Disabled)
```

### ワールド設定
```env
LEVEL_NAME=Education level        # ワールド名
LEVEL_SEED=                     # ワールドシード（空白でランダム）
VIEW_DISTANCE=32                # 描画距離（チャンク数）
TICK_DISTANCE=4                 # ティック距離 (4-12)
```

### プレイヤー設定
```env
PLAYER_IDLE_TIMEOUT=30          # アイドルタイムアウト（分）
DEFAULT_PLAYER_PERMISSION_LEVEL=member  # デフォルト権限 (visitor/member/operator)
```

### パフォーマンス設定
```env
MAX_THREADS=8                   # 最大スレッド数
TEXTUREPACK_REQUIRED=true       # テクスチャパック必須
CONTENT_LOG_FILE_ENABLED=false  # コンテンツログ有効化
```

## 設定の仕組み

### .envファイルで一元管理
すべての設定は`.env`ファイルで管理されます。コンテナ起動時に：
1. `entrypoint.sh`が環境変数を読み込む
2. `server.properties`を動的に生成・更新

### 設定変更方法
1. `.env`ファイルを編集
2. コンテナを再起動：`docker-compose restart`

環境変数で設定された値が優先され、起動時にserver.propertiesに反映されます。

## コマンド

```bash
# ログ確認
docker-compose logs -f minecraft-edu

# 再起動
docker-compose restart

# 停止
docker-compose down

# ボリューム含めて削除
docker-compose down -v
```

## ポート設定

- **19132/udp**: IPv4接続用（デフォルト）
- **19133/udp**: IPv6接続用

ファイアウォールで両ポートを開放してください。

## 注意事項

- **初回起動時はAzure AD認証が必要です**（Device Code認証）
- `edu_server_session.json`は認証後に自動生成され、永続化されます
- すべての設定は`.env`で管理し、起動時に自動反映されます
- `server.properties`やその他の設定ファイルを直接編集する必要はありません

## トラブルシューティング

### 認証エラー
```bash
# セッションファイルを削除して再認証
rm edu_server_session.json
docker-compose restart
```

### パフォーマンス問題
`.env`ファイルで以下を調整：
- `MAX_THREADS`: CPUコア数に応じて調整
- `VIEW_DISTANCE`: 低減して負荷軽減
- `TICK_DISTANCE`: 4-12の範囲で調整

## 参考資料

- [公式ドキュメント](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)