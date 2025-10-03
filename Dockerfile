# Minecraft Education Edition Dedicated Server (Beta)
# 公式要件: Ubuntu 18以降
FROM ubuntu:22.04

# 必要最小限のパッケージ
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    libcurl4 \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /minecraft

# サーバーのダウンロードと解凍
RUN wget -O server.zip "https://aka.ms/downloadmee-linuxServerBeta" && \
    unzip server.zip && \
    rm server.zip && \
    chmod +x bedrock_server_edu

# エントリーポイントスクリプト
COPY ./entrypoint.sh /minecraft/
RUN chmod +x /minecraft/entrypoint.sh

# ポート設定 (IPv4: 19132, IPv6: 19133)
EXPOSE 19132/udp 19133/udp

ENTRYPOINT ["/minecraft/entrypoint.sh"]
