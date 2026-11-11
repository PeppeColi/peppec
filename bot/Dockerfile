FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY bot.py dashboard.html ./
ARG VERSION=dev
ENV PEPPEC_VERSION=$VERSION
CMD ["python", "-u", "bot.py"]
