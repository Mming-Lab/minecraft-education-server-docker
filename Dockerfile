# Minecraft Education Edition Dedicated Server
# 公式要件: Ubuntu 18.04 以降（64bit・2コア以上・RAM 1GB 以上）
# サーバーバイナリは起動時に自動ダウンロード・更新される

FROM ubuntu:22.04

LABEL org.opencontainers.image.title="Minecraft Education Edition Dedicated Server" \
      org.opencontainers.image.description="Docker container for Minecraft Education Edition Dedicated Server" \
      org.opencontainers.image.source="https://github.com/Mming-Lab/minecraft-education-server-docker" \
      org.opencontainers.image.licenses="PolyForm-Noncommercial-1.0.0"

# ランタイム + ダウンロード用パッケージ
#   procps   … プロセス確認（entrypoint のシャットダウン処理でも使う）
#   iproute2 … ss コマンド。nethernet は接続ごとに UDP ソケットを確保するため、
#              実際に何本開いているかを ss -lunp で確認できるようにしておく
RUN apt-get update && apt-get install -y \
    libcurl4 \
    openssl \
    ca-certificates \
    procps \
    jq \
    wget \
    unzip \
    iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 日本語などマルチバイト文字の stdout 出力を正しく扱うための locale 設定
ENV LANG=C.UTF-8

WORKDIR /minecraft

# 実行ユーザーの UID/GID（ホスト側のマウント先と揃えるため可変にする）
# 通常は Makefile が make 実行ユーザーの id -u / id -g を自動で渡す。
# ここの既定値 1000 は、docker compose を直接実行した場合のフォールバック。
ARG PUID=1000
ARG PGID=1000

# 非rootユーザーの作成（同じ UID/GID が既に存在する場合はそれを再利用する）
RUN set -eux; \
    if ! getent group "${PGID}" >/dev/null; then groupadd -g "${PGID}" minecraft; fi; \
    if ! getent passwd "${PUID}" >/dev/null; then \
        useradd -u "${PUID}" -g "${PGID}" -d /minecraft -M -s /usr/sbin/nologin minecraft; \
    fi; \
    chown -R "${PUID}:${PGID}" /minecraft

# 設定定義・エントリーポイント・ヘルスチェックスクリプト
COPY --chown=${PUID}:${PGID} ./property-definitions.json ./entrypoint.sh ./healthcheck.sh /minecraft/
# Windows環境での改行コード問題を防止（CRLF→LF変換）
RUN sed -i 's/\r$//' /minecraft/entrypoint.sh /minecraft/healthcheck.sh && \
    chmod +x /minecraft/entrypoint.sh /minecraft/healthcheck.sh

# 非rootで実行（ホストのマウント先と同じ UID/GID）
USER ${PUID}:${PGID}

# ポートは EXPOSE しない。
# このイメージは1ホストで複数ワールドを動かす前提で、ワールドごとに別の
# ポート帯（19200-19299, 19300-19399, …）を使うため、固定値を書くと必ず嘘になる。
# 実際の公開は compose の ports で行う（docker-compose.world{N}.yml.example 参照）:
#   raknet    … server-port を UDP で待ち受け
#   nethernet … server-port は TCP（シグナリング）。ゲーム通信は別の UDP 範囲
# なお EXPOSE はメタデータでしかなく、記述してもポートは公開されない
#（docker run -P を使う場合のみ影響するが、本構成では compose で明示している）。

# ヘルスチェック（起動猶予3分、30秒間隔、3回失敗でunhealthy）
# ※ 初回起動時はダウンロード時間が必要なため、起動猶予を3分に延長
HEALTHCHECK --start-period=3m --interval=30s --timeout=10s --retries=3 \
    CMD /minecraft/healthcheck.sh

ENTRYPOINT ["/minecraft/entrypoint.sh"]
