ARG BASE_IMAGE=eclipse-temurin:21-jre
FROM ${BASE_IMAGE}

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
    xvfb \
    xauth \
    libgtk-3-0 \
    libwebkit2gtk-4.1-0 \
    libxtst6 \
    libxrender1 \
    libxi6 \
    libxrandr2 \
    libxss1 \
    libasound2t64 \
    fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/* \
 && addgroup --system --gid 10001 glauco \
 && adduser --system --uid 10001 --ingroup glauco --home /home/glauco glauco \
 && mkdir -p /home/glauco /app/tmp \
 && chown -R 10001:10001 /home/glauco /app/tmp

COPY dist/glauco-app.jar /app/glauco-app.jar
RUN printf '%s\n' \
    '#!/usr/bin/env sh' \
    'set -eu' \
    'if [ "${GLAUCO_USE_HOST_DISPLAY:-0}" = "1" ]; then' \
    '  exec java -jar /app/glauco-app.jar' \
    'fi' \
    'exec xvfb-run --auto-servernum --server-args="-screen 0 1280x800x24 -nolisten tcp" java -jar /app/glauco-app.jar' \
    > /app/glauco-entrypoint \
 && chmod +x /app/glauco-entrypoint

ENV PORT=8080
ENV BIND_ADDRESS=0.0.0.0
ENV HOME=/home/glauco
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -Dfile.encoding=UTF-8 -Djava.io.tmpdir=/app/tmp -Dorg.eclipse.swt.browser.DefaultType=webkit"
ENV SWT_GTK3=1
ENV DISPLAY=:99

USER 10001:10001

ENTRYPOINT ["/app/glauco-entrypoint"]
