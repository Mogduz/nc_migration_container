# nc_migration_container

Container-Setups fuer die Migration von ownCloud nach Nextcloud.
Das Repository ist in zwei Verzeichnisse aufgeteilt: `all_in_one/` und `single/`.

## Wichtiger Hinweis zum Status

- `all_in_one/` ist die derzeit nutzbare Migrationsvariante.
- `single/` ist aktuell in Entwicklung und noch nicht fertig.
- Fuer `single/` gibt es derzeit keine Stabilitaetsgarantie.

## Aktuelle Verzeichnisstruktur

```text
nc_migration_container/
|- README.md
|- LICENSE
|- .gitignore
|- all_in_one/
|  |- .env
|  |- .env.example
|  |- Dockerfile
|  |- docker-compose.yml
|  |- entrypoint.sh
|  |- healthcheck.sh
|  |- migrate.sh
|  |- supervisor.conf
|  |- apt/
|  |  `- ldbv.sources.list
|  |- artifacts/
|  |  |- download_nextcloud_tarball.sh
|  |  `- nextcloud-<version>.tar.bz2 (wird lokal erzeugt)
|  `- entrypoint.d/
|     |- 00-env.sh
|     |- 10-dirs.sh
|     |- 20-apache.sh
|     |- 30-database.sh
|     |- 40-redis.sh
|     `- 50-upgrade-map.sh
`- single/
   |- Dockerfile
   |- docker-compose.yml
   `- entrypoint.sh
```

## Variante `all_in_one` (empfohlen fuer Migration)

Zweck:
- Nextcloud, MySQL, Redis und Apache laufen gemeinsam in einem Container.
- SQL-Dumps aus `${DB_DUMP_DIR}` werden als `/mnt/mysql` in den Container gemountet.
- Redis-Daten aus `${REDIS_DIR}` werden als `/mnt/redis` gemountet.

### Voraussetzungen

- Docker Engine + Docker Compose Plugin.
- Lokale Konfiguration in `all_in_one/.env` (am besten aus `.env.example` erzeugen).
- Lokaler Nextcloud-Tarball in `all_in_one/artifacts/`.

### Wichtige Hinweise

- Der Build laedt Nextcloud nicht mehr aus dem Internet, sondern erwartet den Tarball lokal unter `all_in_one/artifacts/`.
- Das Skript `all_in_one/artifacts/download_nextcloud_tarball.sh` laedt die fest konfigurierte Version `25.0.13`.
- Bei `APT_PROFILE=ldbv` wird `all_in_one/apt/ldbv.sources.list` verwendet und die HTTPS-Zertifikatspruefung fuer APT deaktiviert.
- Wenn du die Nextcloud-Version aendern willst, muessen `ARG NC_VERSION` in `all_in_one/Dockerfile` und das Download-Skript zusammenpassen.

### Setup

1. In das Verzeichnis wechseln:
```bash
cd all_in_one
```

2. `.env` vorbereiten:
```bash
cp .env.example .env
```

3. Nextcloud-Tarball herunterladen:
```bash
bash artifacts/download_nextcloud_tarball.sh
```

4. Pruefen, ob das Artefakt vorhanden ist:
```bash
ls -lh artifacts/nextcloud-25.0.13.tar.bz2
```

5. Optional APT-Profil in `.env` setzen:
- `APT_PROFILE=normal`: Standard-Repositories im Image (Default).
- `APT_PROFILE=ldbv`: `apt/ldbv.sources.list` wird verwendet und HTTPS-Zertifikatspruefung fuer APT ist deaktiviert.

6. Container bauen und starten:
```bash
docker compose up -d --build
```

Aufruf:
- http://localhost:${PORT}

### Migration ausfuehren

Migration im laufenden Container starten:

```bash
docker exec -it nc_migration_all_in_one /usr/local/bin/migrate.sh
```

Alternativ ueber Compose:

```bash
docker compose exec all_in_one /usr/local/bin/migrate.sh
```

### Nuetzliche Checks

- Container-Logs:
```bash
docker compose logs -f all_in_one
```

- Nextcloud-Status:
```bash
docker exec -it nc_migration_all_in_one occ status
```

## Variante `single` (in Entwicklung)

Zweck:
- Einzelcontainer-Ansatz fuer Nextcloud/Apache mit optionaler Initialisierung.
- Aktuell Work-in-Progress und nicht final dokumentiert oder final validiert.

Aktueller Stand:
- Enthalten: `single/Dockerfile`, `single/docker-compose.yml`, `single/entrypoint.sh`
- Verhalten kann sich kurzfristig aendern.
- Noch nicht als stabile Standardvariante vorgesehen.

## Dateiuebersicht

Root:
- `README.md`: Hauptdokumentation.
- `LICENSE`: MIT-Lizenz.
- `.gitignore`: Ignore-Regeln fuer lokale Artefakte und Tooling-Dateien.

`all_in_one/`:
- `all_in_one/Dockerfile`: Build fuer kombinierten Migrationscontainer.
- `all_in_one/docker-compose.yml`: Startkonfiguration fuer den All-in-One-Container.
- `all_in_one/.env.example`: Beispielwerte fuer Ports, Volumes, DB und Build-Profil.
- `all_in_one/apt/ldbv.sources.list`: APT-Quellen fuer `APT_PROFILE=ldbv`.
- `all_in_one/artifacts/download_nextcloud_tarball.sh`: Laedt den lokalen Nextcloud-Tarball fuer den Build.
- `all_in_one/artifacts/nextcloud-<version>.tar.bz2`: Lokales Build-Artefakt fuer Nextcloud (wird per Skript erzeugt).
- `all_in_one/entrypoint.sh`: Fuehrt modulare Startskripte aus `entrypoint.d/` aus.
- `all_in_one/healthcheck.sh`: HTTP-Healthcheck.
- `all_in_one/migrate.sh`: Fuehrt `occ`-Migrationsschritte aus und erstellt DB-Dump.
- `all_in_one/supervisor.conf`: Prozesssteuerung fuer MySQL, Redis, Apache.
- `all_in_one/entrypoint.d/*.sh`: Initialisierung von Env, Verzeichnissen, Apache, DB, Redis und Upgrade-Mapping.

`single/`:
- `single/Dockerfile`: Build fuer die Einzelcontainer-Variante.
- `single/docker-compose.yml`: Compose-Start fuer die Einzelcontainer-Variante.
- `single/entrypoint.sh`: Initialisierung/Startlogik fuer `single`.

## Hinweise

- Das Projekt ist auf Migration und kurzfristige Reproduzierbarkeit ausgelegt.
- PHP 7.4 und Ubuntu 20.04 sind fuer den Migrationskontext ausgewaehlt, aber nicht modern fuer neuen Dauerbetrieb.
- Standard-Passwoerter in lokalen `.env`-Dateien nur lokal nutzen und bei Bedarf sofort ersetzen.
