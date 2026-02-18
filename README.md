# nc_migration_container

Kurzlebige Container-Umgebung fuer die Migration von ownCloud nach Nextcloud.
Der Fokus liegt auf einer pragmatischen Migrationshilfe, nicht auf einem produktiven Dauerbetrieb.

## Ziel und Varianten

Es gibt zwei Betriebsarten:

1. Root-Variante (`Dockerfile` + `entrypoint.sh` im Projektroot)
- Nextcloud + Apache im Container.
- Auto-Install standardmaessig deaktiviert (`NC_AUTO_INSTALL=0`).
- Eignet sich fuer kontrollierte, manuelle Inbetriebnahme.

2. All-in-One (`all_in_one/`)
- Nextcloud + MariaDB + Redis + Supervisor in einem Container.
- Importiert vorhandene SQL-Dumps aus `/mnt/mysql`.
- Setzt Redis optional auf vorhandene RDB-Daten in `/mnt/redis`.
- Fuer Migration/Tests gedacht, nicht fuer produktive Architektur.

## Dateiuebersicht mit Kommentaren

### Root

- `.gitignore`
  - Standard-Python-Ignoreliste.
  - Hält lokale Umgebungen, Caches, Build-Artefakte und Tooling-Dateien aus Git fern.

- `Dockerfile`
  - Baut ein Ubuntu-20.04-Image mit Apache + PHP 7.4 und Nextcloud 25.
  - Aktiviert fuer Nextcloud notwendige Apache-Module.
  - Downloadt eine feste Nextcloud-Version als Build-Artefakt.
  - Legt Konfigurations-Symlink nach `/mnt/NextCloud/config`, damit Konfiguration extern persistiert werden kann.

- `entrypoint.sh`
  - Initialisiert Verzeichnisse und optionales Auto-Install-Verhalten.
  - Bricht absichtlich ab, wenn `config.php` bereits existiert (Schutz vor ungewollter Neuinitialisierung).
  - Fuehrt bei `NC_AUTO_INSTALL=1` ein SQLite-basiertes `occ maintenance:install` aus.
  - Verschiebt erkannte SQLite-DB-Datei in ein externes Verzeichnis und verlinkt zurueck.

- `docker-compose.yml`
  - Definiert App + MariaDB + Redis als lokale Entwicklungs-/Migrationsumgebung.
  - Bind-Mounts fuer Konfiguration und Daten.
  - Standard-Credentials sind fuer lokale Nutzung gesetzt und muessen fuer ernsthafte Nutzung ersetzt werden.

- `README.md`
  - Projektdokumentation, Betriebsmodi, Ablaufschritte und Hinweise.

- `LICENSE`
  - MIT-Lizenz.

### all_in_one

- `all_in_one/Dockerfile`
  - Installiert Apache, PHP 7.4, MariaDB, Redis und Supervisor in einem Image.
  - Aktiviert APCu fuer CLI (`occ`), damit Admin-Befehle stabil laufen.
  - Kopiert modulare Entry-Skripte aus `entrypoint.d`.

- `all_in_one/docker-compose.yml`
  - Startet den All-in-One-Container und bindet persistente Volumes fuer Nextcloud, MySQL-Dumps und Redis-Daten.

- `all_in_one/entrypoint.sh`
  - Fuehrt alle Skripte in `/entrypoint.d` sequentiell aus.
  - Danach Start des Hauptprozesses (Supervisor).

- `all_in_one/healthcheck.sh`
  - Prueft lokal per HTTP, ob Apache/Nextcloud antwortet.

- `all_in_one/migrate.sh`
  - Fuehrt typische Post-Migrations-`occ`-Schritte aus:
    - `upgrade`
    - Maintenance aus
    - fehlende DB-Strukturen nachziehen
    - Apps aktualisieren
  - Erstellt danach einen komprimierten SQL-Dump unter `/mnt/mysql`.

- `all_in_one/supervisor.conf`
  - Orchestriert MySQL, Redis und Apache in einem Containerprozessmodell.

#### `all_in_one/entrypoint.d`

- `00-env.sh`
  - Setzt zentrale Pfade und Default-Umgebungsvariablen.
  - Mapt DB-Variablen auf ownCloud-kompatible Override-Variablen.

- `10-dirs.sh`
  - Erstellt benoetigte Verzeichnisse.
  - Setzt Owner/Permissions fuer Nextcloud-relevante Mounts.
  - Bereitet Schreibrechte fuer `/mnt/mysql` vor.

- `20-apache.sh`
  - Setzt `DocumentRoot` auf Nextcloud.
  - Aktiviert zusätzliche Apache-Conf fuer Nextcloud + Redirect.

- `30-database.sh`
  - Restriktiert MariaDB auf localhost.
  - Initialisiert DB, User und Privilegien.
  - Importiert SQL- oder SQL.GZ-Dumps aus `/mnt/mysql`.
  - Fuehrt einfache SQL-Bereinigung beim Import durch (u. a. `DEFINER` entfernen).

- `40-redis.sh`
  - Nutzt optional `/mnt/redis` als Redis-Datenverzeichnis.
  - Setzt optionales `dbfilename` auf die erste gefundene `*.rdb`.

- `50-upgrade-map.sh`
  - Patcht die Upgrade-Map in `version.php`, damit ownCloud-Quellversionen fuer Migration akzeptiert werden.

## Schnellstart

### Root-Variante

Build:
```bash
docker build -t nc_migration_container:local .
```

Start (ohne Auto-Install):
```bash
docker run -d -p 8080:80 --name nc_migration_container_test \
  -v ./nextcloud_config:/mnt/NextCloud/config \
  -v ./nextcloud_data:/mnt/NextCloud/data \
  nc_migration_container:local
```

Aufruf:
- http://localhost:8080/

### All-in-One

```bash
cd all_in_one
docker compose up --build
```

Aufruf:
- http://localhost:8080/

## Typischer Migrationsablauf (all_in_one)

1. SQL-Dump(s) in `all_in_one/mysql/` legen (`.sql` oder `.sql.gz`).
2. Optional Redis-RDB nach `all_in_one/redis/` legen.
3. Container starten.
4. Nach erfolgreichem Start Migrationsskript ausfuehren:
```bash
docker exec -it nc_migration_all_in_one /usr/local/bin/migrate.sh
```
5. Ergebnis pruefen (`occ status`, Web-Login, Logs).

## Wichtige Umgebungsvariablen

- `NC_AUTO_INSTALL` (Root-Variante): `1` aktiviert Auto-Install.
- `NC_ADMIN_USER`, `NC_ADMIN_PASSWORD`: Initiale Admindaten.
- `NC_TRUSTED_DOMAINS`: Trusted Domain fuer Nextcloud.
- `MYSQL_HOST`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`.
- `DB_TYPE` (all_in_one): Default `mysql`.

## Hinweise

- Diese Umgebung ist auf Migration und kurzfristige Reproduzierbarkeit ausgelegt.
- PHP 7.4 / Ubuntu 20.04 sind funktional fuer den Migrationskontext, aber nicht modern fuer neuen Produktivbetrieb.
- Standard-Passwoerter in Compose-Dateien nur lokal nutzen und bei Bedarf sofort ersetzen.
