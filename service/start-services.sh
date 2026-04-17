#!/bin/sh
set -eu

term_handler() {
  if [ -n "${WATER_PID:-}" ]; then
    kill "$WATER_PID" 2>/dev/null || true
  fi
  if [ -n "${WEATHER_PID:-}" ]; then
    kill "$WEATHER_PID" 2>/dev/null || true
  fi
  wait || true
}

trap term_handler INT TERM

java ${WATER_JAVA_OPTS:-$JAVA_OPTS} -jar /app/water-station-pusher.jar &
WATER_PID=$!

java ${WEATHER_JAVA_OPTS:-$JAVA_OPTS} -jar /app/weather-station-pusher.jar &
WEATHER_PID=$!

while kill -0 "$WATER_PID" 2>/dev/null && kill -0 "$WEATHER_PID" 2>/dev/null; do
  sleep 1
done

if kill -0 "$WATER_PID" 2>/dev/null; then
  wait "$WEATHER_PID"
  EXIT_CODE=$?
else
  wait "$WATER_PID"
  EXIT_CODE=$?
fi

term_handler
exit "$EXIT_CODE"
