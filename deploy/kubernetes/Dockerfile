ARG BASE_IMAGE=eclipse-temurin:21-jre
FROM ${BASE_IMAGE}

WORKDIR /app

RUN addgroup --system --gid 10001 glauco \
 && adduser --system --uid 10001 --ingroup glauco glauco

COPY dist/glauco-app.jar /app/glauco-app.jar

ENV PORT=8080
ENV BIND_ADDRESS=0.0.0.0
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -Dfile.encoding=UTF-8 -Djava.io.tmpdir=/tmp"

USER 10001:10001

ENTRYPOINT ["java", "-jar", "/app/glauco-app.jar"]
