#!/usr/bin/env bash
# Strikter Modus fuer Redis-Konfigurationsschritt.
set -euo pipefail

log "Running 40-redis.sh"
# Nur wenn der Mount existiert, wird Redis auf externes Datenverzeichnis umgestellt.
if [ -d "/mnt/redis" ]; then
  log "Configuring Redis to use /mnt/redis as data dir"
  mkdir -p /mnt/redis
  chown -R redis:redis /mnt/redis
  # Redis "dir" auf den Mount setzen.
  if grep -q '^dir ' /etc/redis/redis.conf; then
    sed -i 's#^dir .*#dir /mnt/redis#' /etc/redis/redis.conf
  else
    printf '\ndir /mnt/redis\n' >> /etc/redis/redis.conf
  fi
  # Erste gefundene RDB-Datei verwenden, sonst dump.rdb als Fallback.
  REDIS_RDB_FILE=""
  for f in /mnt/redis/*.rdb; do
    if [ -f "$f" ]; then
      REDIS_RDB_FILE="$(basename "$f")"
      break
    fi
  done
  if [ -z "$REDIS_RDB_FILE" ]; then
    REDIS_RDB_FILE="dump.rdb"
  fi
  # dbfilename in redis.conf entsprechend setzen.
  if grep -q '^dbfilename ' /etc/redis/redis.conf; then
    sed -i "s#^dbfilename .*#dbfilename ${REDIS_RDB_FILE}#" /etc/redis/redis.conf
  else
    printf 'dbfilename %s\n' "$REDIS_RDB_FILE" >> /etc/redis/redis.conf
  fi
else
  # Ohne Mount bleibt Redis-Standardkonfiguration aktiv.
  log "/mnt/redis not mounted; using default Redis data dir"
fi
