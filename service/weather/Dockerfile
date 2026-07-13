FROM maven:3.9.9-eclipse-temurin-21 AS build
WORKDIR /app

COPY pom.xml ./
COPY src ./src

RUN mvn -B -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app

# curl is required by HEALTHCHECK — the base image ships neither curl nor wget.
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Non-root runtime user — containers must not run as root.
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --no-create-home appuser

COPY --from=build /app/target/weather-station-pusher-1.0.0.jar /app/weather-station-pusher.jar

RUN mkdir -p /app/logs && \
    chown appuser:appgroup /app/weather-station-pusher.jar /app/logs

USER appuser

ENV JAVA_OPTS=""

EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -sf http://localhost:8081/actuator/health || exit 1

# exec replaces the shell so Java becomes PID 1 and receives SIGTERM directly.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/weather-station-pusher.jar"]
