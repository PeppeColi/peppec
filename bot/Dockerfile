FROM python:3.12-slim
# Claude Code, used only to show the Claude usage on the dashboard (it renews the login)
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL https://claude.ai/install.sh | bash \
    && apt-get purge -y curl && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*
ENV PATH="/root/.local/bin:$PATH" CLAUDE_CONFIG_DIR=/claude DISABLE_AUTOUPDATER=1
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bot.py dashboard.html ./
ARG VERSION=dev
ENV PEPPEC_VERSION=$VERSION
CMD ["python", "-u", "bot.py"]
