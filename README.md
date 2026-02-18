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
|  |- Dockerfile
|  |- docker-compose.yml
|  |- entrypoint.sh
|  |- healthcheck.sh
|  |- migrate.sh
|  |- supervisor.conf
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
- Nextcloud, MariaDB, Redis und Apache laufen gemeinsam in einem Container.
- SQL-Dumps aus `/mnt/mysql` werden beim Start importiert.
- Redis kann optional vorhandene `*.rdb` aus `/mnt/redis` verwenden.

Start:
```bash
cd all_in_one
docker compose up --build
```

Aufruf:
- http://localhost:8080/

Typischer Migrationsablauf:
1. SQL-Dump(s) nach `all_in_one/mysql/` legen (`.sql` oder `.sql.gz`).
2. Optional Redis-RDB nach `all_in_one/redis/` legen.
3. Container starten.
4. Migration abschliessen:
```bash
docker exec -it nc_migration_all_in_one /usr/local/bin/migrate.sh
```
5. Ergebnis pruefen (`occ status`, Web-Login, Logs).

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
- Standard-Passwoerter in Compose-Dateien nur lokal nutzen und bei Bedarf sofort ersetzen.