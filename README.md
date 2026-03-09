# nc_migration_container

Docker-Compose-Setup fuer die stufenweise Migration von `ownCloud 10.16.x` nach `Nextcloud 33.0.0`.

Der produktive Migrationspfad ist `stage1` bis `stage9`.
`stage0` ist nur ein Dummy/Test-Setup.

## Ziel

1. Bestehende ownCloud-`10.16.x`-Instanz uebernehmen.
2. Datenbank-Dump kontrolliert in MySQL 8 importieren.
3. Pro Stage `occ upgrade` ausfuehren.
4. Zielversion `Nextcloud 33.0.0` erreichen.

## Projektstruktur

- `compose/stage0` bis `compose/stage9`: Compose-Dateien pro Migrationsstufe
- `compose/stage1/files/versions.php`: Angepasste Version-Datei fuer Stage 1
- `source/import_db_dump.sh`: DB-Import mit Checks und Report
- `source/upgrade_instance.sh`: OCC-Upgrade-Schritte
- `source/migrate_apps_stage1.sh`: App-Migration in Stage 1
- `source/copy_stage1_version_php.sh`: Kopiert `version.php` in den Container
- `.env.example`: Vorlage fuer alle benoetigten Variablen

## Stage-Matrix

| Stage | Nextcloud-Image | Zweck |
| --- | --- | --- |
| 0 | `nextcloud:25.0.13-apache` | Dummy/Test |
| 1 | `nextcloud:25.0.13-apache` | Start der produktiven Migration |
| 2 | `nextcloud:26.0.13-apache` | Upgrade |
| 3 | `nextcloud:27.1.2-apache` | Upgrade |
| 4 | `nextcloud:28.0.14-apache` | Upgrade |
| 5 | `nextcloud:29.0.16-apache` | Upgrade |
| 6 | `nextcloud:30.0.16-apache` | Upgrade |
| 7 | `nextcloud:31.0.14-apache` | Upgrade |
| 8 | `nextcloud:32.0.6-apache` | Upgrade |
| 9 | `nextcloud:33.0.0-apache` | Zielversion / Betrieb moeglich |

## Voraussetzungen

- Docker Engine + Docker Compose Plugin (`docker compose`)
- Bash-Shell (Linux/macOS, WSL oder Git-Bash unter Windows)
- Optional: `pv` fuer Fortschrittsanzeige beim Import
- Optional: `gzip` bei `.sql.gz`-Dump

## Vorbereitung an der Quellinstanz

1. Externe Apps (`apps-external`) deaktivieren, z. B. mit:
   `occ app:disable <appname>`
2. Maintenance Mode einschalten:
   `occ maintenance:mode --on`
3. Datenverzeichnisse kopieren (`data`, `config`, `apps-external`).
4. DB-Dump erstellen.
5. Berechtigungen pruefen: `data`, `config`, `apps-external` gehoeren `www-data:www-data`.
6. `.env` aus Vorlage erstellen:

```bash
cp .env.example .env
```

## `.env` anpassen

Pflichtwerte:

- `MYSQL_DATABASE` (aus `config.php`)
- `MYSQL_USER` (aus `config.php`)
- `MYSQL_PASSWORD` (aus `config.php`)
- `DB_DUMP_PATH` (Pfad zum Dump, ideal absolut)
- `DB_MOUNT_PATH` (muss gesetzt sein, damit die MySQL-Daten persistent bleiben)
- `REDIS_MOUNT_PATH` (muss gesetzt sein, damit Redis-Daten persistent bleiben)
- `NEXTCLOUD_CONFIG_MOUNT_PATH`
- `NEXTCLOUD_APPS_EXTERNAL_MOUNT_PATH`
- `NEXTCLOUD_DATA_MOUNT_PATH`
- `NEXTCLOUD_FILES_CONTAINER_PATH` (muss exakt zum Pfad aus `config.php` passen)

Hinweis zu Pfaden in `.env`:

- Relative Pfade (z. B. `./db`) werden relativ zur jeweils verwendeten `docker-compose.yml` aufgeloest.

## `config.php` anpassen

Im kopierten Config-Ordner diese Werte setzen:

| Key | Sollwert |
| --- | --- |
| `apps_path[0]['path']` | `/var/www/html/apps` |
| `apps_path[1]['path']` | `/var/www/html/custom_apps` |
| `apps_path[1]['url']` | `custom_apps` |
| `appstoreenabled` | `true` (fuer Migration, danach optional wieder `false`) |
| `redis['host']` | `redis` |
| `cache_path` | `/var/www/html/tmp` |
| `dav.chunk_base_dir` | `/var/www/html/tmp` |
| `dbhost` | `db:3306` |

Wichtige Zusatzhinweise:

- Wenn Config-Snippets genutzt werden, muessen Werte dort angepasst werden, nicht nur in `config.php`.
- Wenn Maintenance Mode per Snippet erzwungen wird, Snippet fuer Migration deaktivieren (`.bak`), da `occ` nur `config.php` aendert.

## Migration (Stage 1 bis Stage 9)

Setze zuerst eine Variable fuer deine Env-Datei:

```bash
ENV_FILE=./.env
```

### 1) Nur Datenbank in Stage 1 starten

```bash
docker compose -f ./compose/stage1/docker-compose.yml --env-file "$ENV_FILE" up db -d
docker ps
```

### 2) Dump importieren

```bash
bash ./source/import_db_dump.sh "$ENV_FILE"
```

### 3) Stage 1 vollstaendig starten

```bash
docker compose -f ./compose/stage1/docker-compose.yml --env-file "$ENV_FILE" down
docker compose -f ./compose/stage1/docker-compose.yml --env-file "$ENV_FILE" up -d
docker compose -f ./compose/stage1/docker-compose.yml --env-file "$ENV_FILE" logs -f
```

Warte, bis Apache gestartet ist und die Initialisierung abgeschlossen wurde.

Dann ausfuehren:

```bash
bash ./source/copy_stage1_version_php.sh "$ENV_FILE"
bash ./source/upgrade_instance.sh "$ENV_FILE"
bash ./source/migrate_apps_stage1.sh "$ENV_FILE"
```

Danach ist die Instanz auf Nextcloud `25.0.13`.

### 4) Stage 2 bis Stage 9 (pro Stage wiederholen)

Beispiel fuer eine Zielstage:

```bash
STAGE=2
PREV_STAGE=$((STAGE - 1))

docker compose -f ./compose/stage${PREV_STAGE}/docker-compose.yml --env-file "$ENV_FILE" down
docker compose -f ./compose/stage${PREV_STAGE}/docker-compose.yml --env-file "$ENV_FILE" rm app -f
docker compose -f ./compose/stage${PREV_STAGE}/docker-compose.yml --env-file "$ENV_FILE" rm cron -f

docker compose -f ./compose/stage${STAGE}/docker-compose.yml --env-file "$ENV_FILE" up -d
docker compose -f ./compose/stage${STAGE}/docker-compose.yml --env-file "$ENV_FILE" logs -f
bash ./source/upgrade_instance.sh "$ENV_FILE"
```

Diese Sequenz fuer `STAGE=2` bis `STAGE=9` wiederholen.

## Hinweise

- Ausgangsbasis ist `ownCloud 10.16.x`.
- `NEXTCLOUD_HTML_MOUNT_PATH` wird nur in `stage0` verwendet.
- Ab `stage1` werden `config`, `custom_apps` und `data` separat gemountet.
- `stage9` kann fuer den dauerhaften Betrieb verwendet werden.
