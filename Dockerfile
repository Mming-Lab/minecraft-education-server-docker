# Minecraft Education Edition Dedicated Server (Beta)
# 公式要件: Ubuntu 18以降
# サーバーバイナリは起動時に自動ダウンロード・更新される

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Minecraft Education Edition Dedicated Server" \
      org.opencontainers.image.description="Docker container for Minecraft Education Edition Dedicated Server (Beta)" \
      org.opencontainers.image.source="https://github.com/Mming-Lab/minecraft-education-server-docker" \
      org.opencontainers.image.licenses="Apache-2.0"

# ランタイム + ダウンロード用パッケージ
RUN apt-get update && apt-get install -y \
    libcurl4 \
    openssl \
    ca-certificates \
    procps \
    jq \
    wget \
    unzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /minecraft

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

# ヘルスチェック（起動猶予3分、30秒間隔、3回失敗でunhealthy）
# ※ 初回起動時はダウンロード時間が必要なため、起動猶予を3分に延長
HEALTHCHECK --start-period=3m --interval=30s --timeout=10s --retries=3 \
    CMD /minecraft/healthcheck.sh

ENTRYPOINT ["/minecraft/entrypoint.sh"]
