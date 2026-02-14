# Minecraft Education Edition Dedicated Server - Docker

Docker環境でMinecraft Education Edition Dedicated Serverを実行します。

> **注意**: Dedicated Server はベータ版です。サーバーバイナリはコンテナ起動時に自動で最新版がダウンロードされます。

## システム要件

- Docker & Docker Compose
- Azure AD グローバル管理者権限（初回認証とサーバー管理に必要）

## クイックスタート

### 1. 環境設定

`.env`ファイルを作成（**必須**）：

```bash
# .env.example をコピーして .env を作成
cp .env.example .env

# 作成した .env ファイルを編集（以下の項目は最低限設定が必要）
```

`.env`に以下を設定：

```bash
# 公開IPアドレス（必須設定）
SERVER_PUBLIC_IP=192.168.1.100

# ポート番号（必須設定）
SERVER_PORT_WORLD_1=19132
```

**詳細な設定項目は `.env.example` を参照してください。**

### 2. サーバー起動

```bash
# サーバー起動
docker compose up -d minecraft-edu-world1

# ログ確認（Device Codeを確認）
docker compose logs -f minecraft-edu-world1
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
│  # --- Git管理ファイル ---
├── Dockerfile                # コンテナイメージ定義
├── docker-compose.yml        # サービス定義（ワールド1）
├── docker-compose.world.yml  # 追加ワールド用テンプレート
├── entrypoint.sh             # 起動スクリプト（設定反映・グレースフルシャットダウン）
├── healthcheck.sh            # ヘルスチェック（サーバープロセス生存確認）
├── property-definitions.json # サーバー設定の環境変数マッピング定義
├── .env.example              # 環境変数テンプレート（コピーして .env を作成）
├── .dockerignore             # Dockerビルドコンテキスト除外設定
├── LICENSE                   # Apache License 2.0
│
├── docker-compose.loggifly.yml  # LoggiFly（ログ監視+通知）Override
├── loggifly/
│   ├── config.yaml.example      # LoggiFly 設定テンプレート
│   └── config.yaml              # LoggiFly 設定（Git対象外・トークン含む）
│
│  # --- 実行時に作成されるファイル（Git対象外） ---
├── .env                      # 環境変数設定（.env.example からコピーして編集）
│
├── worlds/                   # ワールドデータ
│   └── world{N}/             # 各ワールドのデータ（フォルダごと移植可能）
│       ├── worlds/           # ゲームワールドデータ（自動生成）
│       ├── behavior_packs/   # 動作パック（オプション）
│       ├── resource_packs/   # リソースパック（オプション）
│       ├── allowlist.json    # ホワイトリスト（初回起動時に自動生成）
│       ├── packetlimitconfig.json # パケット制限（初回起動時に自動生成）
│       └── server-icon.png   # サーバーアイコン（手動配置）
│
├── sessions/                 # Azure AD認証セッション
│   └── world{N}/             # IP/ポート変更時に再認証が必要
│
└── logs/                     # サーバーログ（日次ローテーション）
    └── world{N}/
        └── server_YYYY-MM-DD.log
```

**移植**: `worlds/world{N}/` フォルダをまとめてコピーするだけで、ワールド全体を別環境に移植できます。

## 複数ワールド運用

### ワールド追加手順

1. **テンプレートをコピー**
   ```bash
   cp docker-compose.world.yml docker-compose.world2.yml
   ```

2. **{N}を実際の番号に置換**
   - エディタの「検索・置換」機能で `{N}` → `2` に一括置換

3. **.envにポート番号を設定（必須）**
   ```bash
   SERVER_PORT_WORLD_2=19134
   ```

4. **起動**
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.world2.yml up -d
   ```

### 3段階フォールバック設定

設定の優先順位：**個別設定 > 共通設定 > デフォルト値**

```bash
# .envファイルの例
GAMEMODE_COMMON=creative       # 全ワールドのデフォルト
GAMEMODE_WORLD_1=survival      # World1だけ個別設定
# GAMEMODE_WORLD_2は未設定 → GAMEMODE_COMMONが使われる
```

## ログ監視・通知（LoggiFly）

[LoggiFly](https://github.com/clemcer/LoggiFly)でサーバーログを監視し、プレイヤーの参加/退出やサーバーイベントを通知できます。

### セットアップ

1. **設定ファイルを作成**
   ```bash
   cp loggifly/config.yaml.example loggifly/config.yaml
   ```

2. **`loggifly/config.yaml` に通知先を設定**
   - ntfy: `notifications.ntfy` セクションにトピック名を設定
   - LINE / Discord / Email 等: `apprise_url` に [Apprise URL](https://github.com/caronc/apprise/wiki) を設定

3. **起動**
   ```bash
   docker compose -f docker-compose.yml -f docker-compose.loggifly.yml up -d
   ```

### コンテナ別の通知先切り替え

コンテナ単位で `ntfy_topic` や `apprise_url` を指定すると、ワールドごとに通知先を変えられます。
空文字列 `""` を指定するとそのチャネルを無効化できます。

```yaml
# 例: world1 は LINE のみ、world2 は ntfy のみ
containers:
  minecraft-edu-world1:
    ntfy_topic: ""                          # ntfy を無効化
    apprise_url: "line://TOKEN/USER_ID_A"   # LINE に通知
    keywords: ...
  minecraft-edu-world2:
    apprise_url: ""                         # apprise を無効化（ntfy のみ）
    keywords: ...
```

## トラブルシューティング

### サーバーに接続できない

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
   docker compose logs minecraft-edu-world1 | grep "port:"
   # 出力例: IPv4 supported, port: 192.168.1.100:19132
   ```
   このIPアドレスとポート番号でクライアントから接続できるか確認
2. **.envの設定確認**
   - `SERVER_PUBLIC_IP`: DockerホストのIPアドレス（LAN内ならプライベートIP、インターネット経由ならパブリックIP/ドメイン）
   - `SERVER_PORT_WORLD_1`: ポート番号が設定されているか
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

リポジトリのコード: [PolyForm Noncommercial 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/)（非商用利用のみ許可）

Minecraft Education Edition サーバーバイナリ: [Microsoft Software License Terms](https://aka.ms/MinecraftEULA)
