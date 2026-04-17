FROM maven:3.9.9-eclipse-temurin-21 AS water-build
WORKDIR /build/waterservice

COPY service/waterservice/pom.xml ./
COPY service/waterservice/src ./src

RUN mvn -B -DskipTests package

FROM maven:3.9.9-eclipse-temurin-21 AS weather-build
WORKDIR /build/weather

COPY service/weather/pom.xml ./
COPY service/weather/src ./src

RUN mvn -B -DskipTests package

FROM eclipse-temurin:21-jre
WORKDIR /app

COPY --from=water-build /build/waterservice/target/water-station-pusher-1.0.0.jar /app/water-station-pusher.jar
COPY --from=weather-build /build/weather/target/weather-station-pusher-1.0.0.jar /app/weather-station-pusher.jar
COPY service/start-services.sh /app/start-services.sh

RUN chmod +x /app/start-services.sh

ENV JAVA_OPTS=""

ENTRYPOINT ["/app/start-services.sh"]
