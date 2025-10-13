# Minecraft Education Edition Dedicated Server - Docker

Docker環境でMinecraft Education Edition Dedicated Serverを実行します。

> **注意**: ベータ版（v1.21.110）を使用しています。

## システム要件

- Docker & Docker Compose
- 2コア以上のCPU、1GB以上のRAM
- Azure AD グローバル管理者権限（初回認証とサーバー管理に必要）

## クイックスタート

### 1. 環境設定

`.env`ファイルを編集してポート番号を設定：

```bash
# 必須設定
SERVER_PORT_WORLD1=19132
SERVER_PUBLIC_IP=

# 任意設定（IPv6を使用する場合）
#SERVER_PORTV6_WORLD1=19133

# SERVER_PUBLIC_IPの設定例
# 例1（LAN内のみ）: SERVER_PUBLIC_IP=192.168.1.100
# 例2（インターネット公開）: SERVER_PUBLIC_IP=203.0.113.10 またはドメイン名
```

> **セキュリティ推奨**: デフォルトポート19132/19133以外の使用を推奨します（例: 19142/19143）。

### 2. サーバー起動

```bash
# ビルドと起動
docker-compose build
docker-compose up -d

# 初回認証（ログに表示されるURLとコードでブラウザ認証）
docker-compose logs -f minecraft-edu-world1

# 複数ワールドの場合は各ワールドごとに認証
# docker-compose logs -f minecraft-edu-world2
```

### 3. サーバー有効化

**重要**: サーバー起動後、[Python Notebook](https://aka.ms/MCEDU-DS-Tooling)で`Enabled=True`に設定する必要があります。

```python
# tooling/edit_server_info セルで実行
{
    "Enabled": True,
    "ServerName": "My Server",
    "IsBroadcasted": False
}
```

詳細は[公式ガイド](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)を参照してください。

## ディレクトリ構成

```
.
├── Dockerfile              # Ubuntu 22.04ベースのコンテナイメージ定義
├── docker-compose.yml      # サービス定義（単一/複数ワールド対応）
├── entrypoint.sh           # 起動スクリプト（設定ファイル自動生成）
└── .env                    # 環境変数設定（全設定を管理・要編集）
```

## 設定管理

すべての設定は`.env`ファイルで管理します。設定変更後は`docker-compose restart`で反映されます。

詳細な設定項目は`.env`ファイルを参照してください。

## 複数ワールド運用

### ワールド追加手順

1. **docker-compose.ymlのテンプレートをコピー**
   ```yaml
   # ファイル末尾の「ワールド追加用テンプレート」をコピー
   ```

2. **{N}を実際の番号に置換**
   - エディタの「検索・置換」機能で `{N}` → `2` に一括置換
   - 例: `minecraft-edu-world{N}` → `minecraft-edu-world2`

3. **.envにポート番号を設定**
   ```bash
   # .env
   SERVER_PORT_WORLD2=19134
   #SERVER_PORTV6_WORLD2=19135  # IPv6を使用する場合のみ
   ```

4. **コンテナを起動**
   ```bash
   docker-compose up -d minecraft-edu-world2
   ```

### 3段階フォールバック設定

設定の優先順位：**個別設定 > 共通設定 > デフォルト値**

#### 例: ゲームモードの設定

**シナリオ**: World1はクリエイティブ、World2以降は全てサバイバル

```bash
# .envファイル
GAMEMODE_COMMON=survival      # 全ワールドのデフォルト
GAMEMODE_WORLD1=creative      # World1だけ個別設定
# GAMEMODE_WORLD2は未設定 → GAMEMODE_COMMONが使われる
```

**結果**:
- **World1** → `creative`（個別設定が優先）
- **World2以降** → `survival`（共通設定を使用）
- **すべて未設定の場合** → docker-compose.ymlのデフォルト値を使用

## コマンド

```bash
# ログ確認
docker-compose logs -f minecraft-edu-world1

# 設定変更反映
docker-compose restart

# 停止
docker-compose down

# 完全削除（ワールドデータも削除）
docker-compose down -v
```

## トラブルシューティング

### 1. サーバーに接続できない

#### 症状: サーバーIDを入力しても接続できない

![サーバーID入力](docs/images/client-server-id-input.png)

#### 原因と対処法

**原因1: サーバーが有効化されていない（Enabled=False）**

![サーバー無効時のエラー](docs/images/server-disabled-error.png)

**対処法**: [Python Notebook](https://aka.ms/MCEDU-DS-Tooling)で`Enabled=True`に設定

```python
# tooling/edit_server_info セルで実行
{
    "Enabled": True,
    "ServerName": "My Server",
    "IsBroadcasted": False
}
```

有効化後は接続成功します：

![接続成功](docs/images/server-enabled-success.png)

**原因2: ポート設定またはファイアウォールの問題**

![接続エラー](docs/images/connection-error.png)

**対処法**:
1. **サーバーログで接続情報を確認**
   ```bash
   docker-compose logs minecraft-edu-world1 | grep "port:"
   # 出力例: IPv4 supported, port: 192.168.1.100:19132
   ```
   このIPアドレスとポート番号でクライアントから接続できるか確認
2. **.envの設定確認**
   - `SERVER_PUBLIC_IP`: DockerホストのIPアドレス（LAN内ならプライベートIP、インターネット経由ならパブリックIP/ドメイン）
   - `SERVER_PORT_WORLD1`と`SERVER_PORTV6_WORLD1`: ポート番号が設定されているか
3. **ファイアウォール確認**: 該当ポートのUDPが開放されているか
4. **ルーター/NAT確認**（インターネット経由の場合）: ポートフォワーディングが設定されているか

## 管理ツール

- **[IT管理ポータル](https://aka.ms/dedicatedservers)** - テナント設定（機能有効化）
- **[サーバー管理ツール（Python Notebook）](https://aka.ms/MCEDU-DS-Tooling)** - サーバー詳細設定

## 参考資料

- [Dedicated Server 101](https://edusupport.minecraft.net/hc/en-us/articles/41758309283348)
- [インストールガイド](https://edusupport.minecraft.net/hc/en-us/articles/41757415076884)
- [API ドキュメント](https://aka.ms/MCEDU-DS-Docs)

## ライセンス

リポジトリのコード: Apache License 2.0

Minecraft Education Edition サーバーバイナリ: [Microsoft Software License Terms](https://aka.ms/MinecraftEULA)
