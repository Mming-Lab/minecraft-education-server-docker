# Minecraft Education Edition Dedicated Server (Beta)
# 公式要件: Ubuntu 18以降

# ================================================
# ビルドステージ: サーバーのダウンロードと解凍
# ================================================
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /minecraft

RUN wget -O server.zip "https://aka.ms/downloadmee-linuxServerBeta" && \
    unzip server.zip && \
    rm server.zip && \
    chmod +x bedrock_server_edu

# ================================================
# 実行ステージ: 最小限のランタイム環境
# ================================================
FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Minecraft Education Edition Dedicated Server" \
      org.opencontainers.image.description="Docker container for Minecraft Education Edition Dedicated Server (Beta)" \
      org.opencontainers.image.source="https://github.com/Mming-Lab/minecraft-education-server-docker" \
      org.opencontainers.image.licenses="Apache-2.0"

# ランタイムに必要なパッケージのみ（wget, unzip は不要）
RUN apt-get update && apt-get install -y \
    libcurl4 \
    openssl \
    ca-certificates \
    procps \
    jq \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /minecraft

# ビルドステージからサーバーファイルをコピー
COPY --from=builder /minecraft /minecraft

# 非rootユーザーの作成
RUN groupadd -r minecraft && useradd -r -g minecraft -d /minecraft minecraft && \
    chown -R minecraft:minecraft /minecraft

# 設定定義・エントリーポイント・ヘルスチェックスクリプト
COPY --chown=minecraft:minecraft ./property-definitions.json ./entrypoint.sh ./healthcheck.sh /minecraft/
# Windows環境での改行コード問題を防止（CRLF→LF変換）
RUN sed -i 's/\r$//' /minecraft/entrypoint.sh /minecraft/healthcheck.sh && \
    chmod +x /minecraft/entrypoint.sh /minecraft/healthcheck.sh

# 非rootで実行
USER minecraft

# ポート設定 (IPv4: 19132, IPv6: 19133)
EXPOSE 19132/udp 19133/udp

# ヘルスチェック（起動猶予2分、30秒間隔、3回失敗でunhealthy）
HEALTHCHECK --start-period=2m --interval=30s --timeout=10s --retries=3 \
    CMD /minecraft/healthcheck.sh

ENTRYPOINT ["/minecraft/entrypoint.sh"]
