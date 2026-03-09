# nc_migration_container

Docker-Compose-Setup fuer eine stufenweise Migration von `ownCloud 10.16.x` auf `Nextcloud 33.0.0`.

Die produktive Migration erfolgt ueber `stage1` bis `stage9`. Pro Stage wird ein Compose-File mit einer festen Nextcloud-Version genutzt. Daten, Konfiguration und Custom Apps bleiben ueber Bind-Mounts persistent. `stage0` ist ein Dummy/Test-Setup und nicht Teil des eigentlichen Migrationspfads.

## Ziel

1. Eine bestehende ownCloud-`10.16.x`-Instanz kontrolliert in Nextcloud ueberfuehren.
2. Datenbank-Dump kontrolliert importieren.
3. Versionsspruenge mit `occ upgrade` pro Stage (`stage1` bis `stage9`) ausfuehren.
4. Am Ende auf Nextcloud `33.0.0` landen.

## Projektstruktur

- `compose/stage0` bis `compose/stage9`: Compose-Dateien pro Migrationsstufe
- `compose/stage1/files/versions.php`: Stage-1-Version-Datei (`25.0.13`)
- `source/import_db_dump.sh`: DB-Import mit Readiness-Check und Report
- `source/upgrade_instance.sh`: `occ`-Upgradeablauf
- `source/migrate_apps_stage1.sh`: App-Migration fuer Stage 1
- `source/copy_stage1_version_php.sh`: Kopiert `version.php` fuer Stage 1
- `.env.example`: Vorlage fuer alle Umgebungsvariablen

## Stage-Matrix

| Stage | Nextcloud-Image |
| --- | --- |
| 0 | `nextcloud:25.0.13-apache` (Dummy/Test-Setup) |
| 1 | `nextcloud:25.0.13-apache` |
| 2 | `nextcloud:26.0.13-apache` |
| 3 | `nextcloud:27.1.2-apache` |
| 4 | `nextcloud:28.0.14-apache` |
| 5 | `nextcloud:29.0.16-apache` |
| 6 | `nextcloud:30.0.16-apache` |
| 7 | `nextcloud:31.0.14-apache` |
| 8 | `nextcloud:32.0.6-apache` |
| 9 | `nextcloud:33.0.0-apache` |

Hinweis: Der eigentliche Migrationspfad ist `stage1` bis `stage9`.

## Voraussetzungen

- Docker Engine + Docker Compose Plugin (`docker compose`)
- Bash-Shell (Linux/macOS, WSL oder Git-Bash unter Windows)
- Optional: `pv` fuer Import-Fortschrittsanzeige
- Optional: `gzip` bei `.gz`-Dumps

## Ablauf

### Vorbereitung

- Alle Apps die im Verzeichniss apps-external liegen per webInterface oder occ Befehl 'occ app:disable <appname>' deaktivieren
- Instanz in den Maintance Mode versetzen 'occ maintancemode --on'
- Alle Daten (samt config Dateien und External-Apps) kopieren
- Datenank Dump erstellen
- Berechtigungen anpasssen - Die Ordner data, config, apps-external müssen dem user und der Gruppe www-data gehören
- .env.example kopieren

### Anpassung .env

Die folgenden Variablen müssen angepasst werden!

- MYSQL_DATABASE (zu finden in der instanz config.php)
- MYSQL_USER (zu finden in der instanz config.php)
- MYSQL_PASSWORD (zu finden in der instanz config.php)
- DB_DUMP_PATH (Pfad zur zuvor erstellten Dump Datei - am besten absolut)
- DB_MOUNT_PATH (Pfad an dem die Daten des Mysql 8 Containers ausgemountet werden. Dieser Pfad sollte am besten in das Verzeichniss mit gelegt werden in dem auch die Kopierten Daten liegen)
- REDIS_MOUNT_PATH (Pfad an dem die redis Daten ausgelagert werden)
- NEXTCLOUD_CONFIG_MOUNT_PATH (Pfad von dem aus die Config in den Container gemounted wird.)
- NEXTCLOUD_APPS_EXTERNAL_MOUNT_PATH (Pfad von dem aus die externen Apps in den Container gemounted werden)
- NEXTCLOUD_DATA_MOUNT_PATH (Datenverzeichniss der Instanz welches in den container gemounted wird)
- NEXTCLOUD_FILES_CONTAINER_PATH (!!WICHTIG!!: Diese Variable bestimmt den Pfad an dem das Datenverzeichniss in den Container gemounted wird. Der Pfad ist in der Instanz config.php zu finden und muss hier genauso eingetragen werden. Sonst funktioniert es nicht oder die Pfade müssen in der Datenbank geändert werden)
  
### Anpassung Instanz Config

Im kopierten Config Ordner müssen folgende Werte geändert werden:

#### 'apps_path'

- array eintrag 0 path: /var/www/html/apps
- array eintrag 1 path: /var/www/html/custom_apps, url: custom_apps

#### 'appstoreenabled'

- Den Wert für die Migration auf true setzen (Kann danach wieder deaktiviert werden)

#### 'redis'

- Im Array den Host Wert auf 'redis' setzen. Dies ist damit der nC Container den redis Container findet

#### 'cache_path'

- Den Pfad auf '/var/www/html/tmp' ändern (Wichtig: Wenn nicht geändert funktioniert zwar die nextCloud aber die external Apps funktioneren dann nicht mehr.)

#### 'dav.chunk_base_dir'

- Den Pfad auf '/var/www/html/tmp' ändern

#### 'dbhost'

- Für die Migration und den weiteren Betrieb im Container den Wert auf 'db:3306' Wichtig: Der Port muss auch mit geändert werden!

#### Wichtig sollte die Config in Snippets augeteilt sein so müssen die Werte in den Snippets geändert werden da diese die config.php überschreiben

#### Sollte der Maintance Mode über ein snippet gesteuert werden so muss dieses Snippet enfernt oder mit suffix .bak versehen werden da während der Migration den Maintance Mode per occ Befehl mehrmals aktiviert und deaktiviert wird. Ein occ Behfehl manipuliert aber immer nur die config.php und niemals ein snippet. Daher bitte deaktivieren

### Migration

1. starten der Datenbank
   - im repo root 'docker compose -f ./compose/stage1/docker-compose.yml --env-file <pfad zur env Datei> up db -d'
   - ob die Datebank läuft kann via 'docker ps' verifiziert werden
2. Dump importieren
   - Für den import des Datenbank Dumps soll das Script 'import_db_dump.sh' im source Ordner verwendet werden.
   - Dem Script muss die Pfad zu env Datei übergeben werden. Nach dem Start lies dieses selbständig die env aus importiert automatisch den Dump in den Container
   - 'bash ./source/import_db_dump.sh <pfad zur env Datei>'
3. Datenbank stoppen
   - Nach erfolgreichem import die Datenbank stoppen mit 'docker compose -f ./compose/stage1/docker-compose.yml --env-file <pfad zur env Datei> down'
4. Stage1
   - komplette stage1 starten mit 'docker compose -f ./compose/stage1/docker-compose.yml --env-file <pfad zur env Datei> up -d'
   - Nach dem Start mit 'docker compose -f ./compose/stage1/docker-compose.yml --env-file <pfad zur env Datei> logs -f' dem Logoutput der Container folgen.
   - Warten bis der Apache sich meldet und die Intialisierung des Containers fertig (Kann bei großen Instanzen länger dauern)
   - Danach das script copy_stage1_version_php.sh ausführen. Dieses Script benötigt auch die env Datei als Argument und kopiert automatisch eine angepasse version.php an den richtigen Ort im Caontainer. (Wird benötigt da nC standartmäßig in dieser version Nur Instanzen migriren lässt die in der Version 10.13.x sind).
   - 'bash ./source/copy_stage1_version_php.sh <pfad zu env Datei>'
   - Danach die eigentlich Migration via 'bash ./source/upgrade_instance.sh <pfad zu env Datei>' ausführen. (Dies kann mehrere Minuten in anspruch nehmen)
   - Nach der Migration müssen noch die Apps migriert werden. 'bash ./source/migrate_apps_stage1.sh <pfad zu env Datei>'
   - Danach ist die Instanz vollständig auf Nextcloud 25.0.13 migriert
5. Stage2 - Stage9
   - Die folgenden Stages sind im Ablauf alle gleich.
   - Es muss immer die vorherige Stage gestoppt werden.
   - Es müssen zwingend die container 'app' und 'cron' aus dem Compose gelöscht werden.
   - 'docker compose -f ./compose/stage<StageNummer>/docker-compose.yml --env-file <pfad zur env Datei> rm app -f'
   - 'docker compose -f ./compose/stage<StageNummer>/docker-compose.yml --env-file <pfad zur env Datei> rm cron -f'
   - Danach muss die Stage gestarted werden 'docker compose -f ./compose/stage<StageNummer>/docker-compose.yml --env-file <pfad zur env Datei> up -d'
   - Wenn der Apache sich gemeldet wieder das upgrade_instance.sh script ausführen 'bash ./source/upgrade_instance.sh <pfad zu env Datei>'
   - Die vorherigen Punke aus Nummer 5 für die Stages 2 - 9 wiederholen. Danach ist die Version der Nextcloud 33.0.0 (Stage9 kann auch für den Normalen Betrieb verwendet werden)