# Total Migration

Diese Dokumentation beschreibt die Multi-Stage-Migration unter `total_migration` fuer Nextcloud (inkl. Compose-Stages, Env-Konfiguration und Hilfsskripte).

## Ziel

Das Setup erlaubt einen kontrollierten Upgrade-Pfad ueber mehrere Nextcloud-Versionen (Stage1 bis Stage9), statt eines grossen Sprungs in einem Schritt.
`stage0` ist ein separates Demo-Setup und nicht Teil der eigentlichen Migrationskette.

## Ordnerstruktur

```text
total_migration/
|- .env.example
|- compose/
|  |- stage0/
|  |  `- docker-compose.yml
|  |- stage1/
|  |  |- docker-compose.yml
|  |  `- files/
|  |     `- versions.php
|  |- stage2/.../stage9/
|  |  `- docker-compose.yml
`- source/
   |- import_db_dump.sh
   |- copy_stage1_version_php.sh
   |- migrate_apps_stage1.sh
   `- upgrade_instance.sh
```

## Voraussetzungen

- Docker Engine + Docker Compose Plugin
- Bash (Linux/macOS oder z. B. Git Bash/WSL unter Windows)
- Laufender Zugriff auf den Docker-Daemon

Optional:
- `pv` fuer Live-Fortschrittsanzeige bei SQL-Import

## Stage-Uebersicht

| Stage | Rolle | App-Image | Cron-Image |
|---|---|---|---|
| stage0 | Demo (nicht Teil der Migration) | `nextcloud:25.0.13-apache` | `nextcloud:25.0.13-apache` |
| stage1 | Migration | `nextcloud:25.0.13-apache` | `nextcloud:25.0.13-apache` |
| stage2 | Migration | `nextcloud:26.0.13-apache` | `nextcloud:26.0.13-apache` |
| stage3 | Migration | `nextcloud:27.1.2-apache` | `nextcloud:27.1.2-apache` |
| stage4 | Migration | `nextcloud:28.0.14-apache` | `nextcloud:28.0.14-apache` |
| stage5 | Migration | `nextcloud:29.0.16-apache` | `nextcloud:29.0.16-apache` |
| stage6 | Migration | `nextcloud:30.0.16-apache` | `nextcloud:30.0.16-apache` |
| stage7 | Migration | `nextcloud:31.0.14-apache` | `nextcloud:31.0.14-apache` |
| stage8 | Migration | `nextcloud:32.0.6-apache` | `nextcloud:32.0.6-apache` |
| stage9 | Migration | `nextcloud:33.0.0-apache` | `nextcloud:33.0.0-apache` |

Hinweis:
- Die eigentliche Migration laeuft ueber Stage1 bis Stage9.
- Stage0 ist nur fuer Demo-/Testzwecke.
- In Stage0 sind `app` und `cron` auf `25.0.13-apache` fixiert.
- In Stage1 sind `app` und `cron` auf `25.0.13-apache` fixiert.
- `cron` ist in allen Stages auf eine feste Version gesetzt.

## Env-Datei

### Start

```bash
cd total_migration
cp .env.example .env
```

### Wichtige Variablen

| Variable | Bedeutung |
|---|---|
| `NEXTCLOUD_PORT` | Externer Port fuer den App-Container |
| `DB_CONTAINER_NAME` | Containername fuer MySQL |
| `REDIS_CONTAINER_NAME` | Containername fuer Redis |
| `NEXTCLOUD_APP_CONTAINER_NAME` | Containername fuer Nextcloud App |
| `NEXTCLOUD_CRON_CONTAINER_NAME` | Containername fuer Nextcloud Cron |
| `MYSQL_HOST` | DB-Host in Nextcloud (`db`) |
| `MYSQL_DATABASE` | Datenbankname |
| `MYSQL_USER` | DB-Benutzer |
| `MYSQL_PASSWORD` | DB-Passwort |
| `MYSQL_ROOT_PASSWORD` | Root-Passwort MySQL |
| `REDIS_HOST` | Redis-Host (`redis`) |
| `DB_DUMP_PATH` | Pfad zum SQL-Dump (`.sql` oder `.sql.gz`), relativ zur Env-Datei oder absolut |
| `MYSQL_WAIT_TIMEOUT_SECONDS` | Timeout fuer MySQL-Readiness im Importskript |
| `http_proxy` / `https_proxy` / `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | Optionale Proxy-Werte |
| `DB_MOUNT_PATH` | Host-Pfad fuer MySQL-Daten |
| `REDIS_MOUNT_PATH` | Host-Pfad fuer Redis-Daten |
| `NEXTCLOUD_CONFIG_MOUNT_PATH` | Host-Pfad fuer Nextcloud `config` |
| `NEXTCLOUD_APPS_EXTERNAL_MOUNT_PATH` | Host-Pfad fuer `custom_apps` |
| `NEXTCLOUD_DATA_MOUNT_PATH` | Host-Pfad fuer Files/Data |
| `NEXTCLOUD_FILES_CONTAINER_PATH` | Zielpfad im Container fuer den Data-Mount |
| `NEXTCLOUD_HTML_MOUNT_PATH` | Nur Stage0: Full-Mount auf `/var/www/html` |

Optional fuer OCC-Skripte:
- `OCC_CONTAINER_NAME` kann gesetzt werden; falls leer, wird `NEXTCLOUD_APP_CONTAINER_NAME` verwendet.

Hinweis:
- `NEXTCLOUD_VERSION` wird in den aktuellen Stage-Compose-Dateien nicht verwendet.

## Compose verwenden

Beispiel Stage starten:

```bash
cd total_migration/compose/stage1
docker compose --env-file ../../.env up -d
```

Beispiel Stage stoppen:

```bash
cd total_migration/compose/stage1
docker compose --env-file ../../.env down
```

Zwischen Stages wechseln (typisch, Migration Stage1 bis Stage9):
1. Aktuelle Stage `down`
2. Naechste Stage `up -d`
3. Upgrade-/Hilfsskripte ausfuehren
4. Funktion testen

## Skripte in `source/`

Alle Skripte erwarten als erstes Argument einen Pfad zur `.env`.

### 1) Datenbankimport

Datei: `source/import_db_dump.sh`

```bash
bash total_migration/source/import_db_dump.sh total_migration/.env
```

Was passiert:
- Liest `.env`
- Wartet auf MySQL-Readiness
- Legt Root/User/DB und Grants an
- Importiert Dump als `MYSQL_USER`
- Gibt einen Report aus (Tabellenanzahl, Groesse, Top-Tabellen)

### 2) Stage1 `version.php` in laufenden Container kopieren

Datei: `source/copy_stage1_version_php.sh`

```bash
bash total_migration/source/copy_stage1_version_php.sh total_migration/.env
```

Was passiert:
- Kopiert `compose/stage1/files/versions.php` per `docker exec` in den App-Container
- Ziel: `/var/www/html/version.php`
- Setzt Owner/Group auf `www-data:www-data`

### 3) Apps migrieren (Stage1-spezifischer Ablauf)

Datei: `source/migrate_apps_stage1.sh`

```bash
bash total_migration/source/migrate_apps_stage1.sh total_migration/.env
```

Ablauf:
- Deaktiviert + entfernt: `calendar`, `gallery`, `brute_force_protection`
- Deaktiviert (nicht entfernen): `files_antivirus`
- Installiert + aktiviert wieder: `calendar`

Alle OCC-Aufrufe erfolgen per `docker exec` als `www-data`.

### 4) Instanz-Upgrade (OCC)

Datei: `source/upgrade_instance.sh`

```bash
bash total_migration/source/upgrade_instance.sh total_migration/.env
```

Ablauf:
1. `maintenance:mode --on`
2. `upgrade`
3. `maintenance:mode --off`
4. `db:add-missing-columns`
5. `db:add-missing-indices`
6. `db:add-missing-primary-keys`
7. `db:convert-filecache-bigint`
8. Abschlusscheck: `status || true`

Eigenschaften:
- non-interactive (`--no-interaction`)
- Auto-Yes fuer Rueckfragen (`yes | ...`)
- OCC via `php occ` als `www-data`

## Empfohlener Migrationsablauf (Kurzform)

1. `.env` erstellen und Variablen setzen
2. Gewuenschte Stage starten
3. Falls noetig Dump importieren (`import_db_dump.sh`)
4. Bei Stage1 ggf. `version.php` kopieren (`copy_stage1_version_php.sh`)
5. Upgrade-Schritte ausfuehren (`upgrade_instance.sh`)
6. Stage1-spezifische App-Anpassungen (`migrate_apps_stage1.sh`)
7. Funktion pruefen, dann naechste Stage (bis Stage9)

## Troubleshooting

### `Container is not running`

- Richtige Stage gestartet?
- Containername in `.env` korrekt?

### OCC findet `occ` nicht

- Script setzt `-w /var/www/html` und nutzt `php occ`.
- Sicherstellen, dass der App-Container ein Nextcloud-Container ist.

### SQL-Import scheitert mit Auth-Fehlern

- `MYSQL_ROOT_PASSWORD`, `MYSQL_USER`, `MYSQL_PASSWORD` in `.env` pruefen
- CRLF in `.env` wird in den Skripten abgefangen

### Falsche Pfade bei Mounts

- Host-Pfade in `.env` kontrollieren
- Relative Pfade sind relativ zur jeweils genutzten `docker-compose.yml`

## Hinweise

- Diese Migration arbeitet bewusst Stage-basiert.
- Bei produktiven Daten immer Backups vor jedem Stage-Wechsel erstellen.
