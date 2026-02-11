#!/usr/bin/env bash
set -euo pipefail

log "Running 40-redis.sh"
if [ -d "/mnt/redis" ]; then
  log "Configuring Redis to use /mnt/redis as data dir"
  mkdir -p /mnt/redis
  chown -R redis:redis /mnt/redis
  if grep -q '^dir ' /etc/redis/redis.conf; then
    sed -i 's#^dir .*#dir /mnt/redis#' /etc/redis/redis.conf
  else
    printf '\ndir /mnt/redis\n' >> /etc/redis/redis.conf
  fi
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
  if grep -q '^dbfilename ' /etc/redis/redis.conf; then
    sed -i "s#^dbfilename .*#dbfilename ${REDIS_RDB_FILE}#" /etc/redis/redis.conf
  else
    printf 'dbfilename %s\n' "$REDIS_RDB_FILE" >> /etc/redis/redis.conf
  fi
else
  log "/mnt/redis not mounted; using default Redis data dir"
fi
