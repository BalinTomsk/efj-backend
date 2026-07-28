# Pinned by digest for reproducible, tamper-resistant builds.
# maven:3.9.9-eclipse-temurin-21
FROM maven@sha256:3a4ab3276a087bf276f79cae96b1af04f53731bec53fb2e651aca79e4b10211e AS build
WORKDIR /app

COPY pom.xml ./
COPY src ./src

RUN mvn -B -DskipTests package

# eclipse-temurin:21-jre
FROM eclipse-temurin@sha256:8ec353b20d3aab0758572236b81b967c7077c40c4d0819ce97f9a1329d684603
WORKDIR /app

COPY --from=build /app/target/docapi-1.0.0.jar /app/docapi.jar

# The temurin JRE image ships without wget/curl; install wget so HEALTHCHECK can actually run.
RUN apt-get update \
 && apt-get install -y --no-install-recommends wget \
 && rm -rf /var/lib/apt/lists/*

# Run as an unprivileged user. Pre-create the writable logs directory owned by that user
# so the container can run with a read-only root filesystem (mount a volume/tmpfs at /app/logs).
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home app \
 && mkdir -p /app/logs \
 && chown -R app:app /app
USER 10001:10001

ENV JAVA_OPTS=""

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/docapi.jar"]
