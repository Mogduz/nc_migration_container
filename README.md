# nc_migration_container

Container fuer die kurzfristige Migration von OwnCloud nach Nextcloud.

## Standard-Container

Bauen:
```bash
docker build -t nc_migration_container:local .
```

Starten (ohne Auto-Install):
```bash
docker run -d -p 8080:80 --name nc_migration_container_test \
  -v ./nextcloud_config:/mnt/NextCloud/config \
  -v ./nextcloud_data:/mnt/NextCloud/data \
  nc_migration_container:local
```

Aufruf im Browser:
- http://localhost:8080/

Hinweis:
- Die Installation erfolgt nicht automatisch. Die `config.php` wird ueber das gemountete Verzeichnis bereitgestellt.

## All-in-One (Nextcloud + MySQL + Redis)

Diese Variante ist nur fuer die Migration gedacht (kurzlebig), nicht fuer Serverbetrieb.

Bauen und Starten per Compose (im Ordner `all_in_one`):
```bash
cd all_in_one
docker compose up --build
```

Mounts:
- `./nextcloud_config:/mnt/NextCloud/config`
- `./nextcloud_data:/mnt/NextCloud/data`
- `./mysql:/mnt/mysql` (SQL-Dumps `*.sql` oder `*.sql.gz`)
- `./redis:/mnt/redis` (Redis RDB `*.rdb`)

Aufruf im Browser:
- http://localhost:8080/

Hinweise:
- Der Dump-Import aus `/mnt/mysql` wird beim Start ausgefuehrt.
- Redis nutzt direkt `/mnt/redis` als Datenverzeichnis und die erste `*.rdb` Datei.