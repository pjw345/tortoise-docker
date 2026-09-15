# Tortoise WoW with Playerbots (Docker)

> **Important:** This repository pins the server source to a tested commit. Always create a full database backup before changing the image or source commit.

Run a private [Turtle WoW](https://turtle-wow.org/) server with Docker, with optional Playerbot support.

This repository maintains the Docker packaging, database initialisation and deployment configuration needed to build and run a tested version of the server.

## Project lineage

This project builds on the work of several related projects:

### Docker packaging

* [Nescabir/tortoise-docker](https://github.com/Nescabir/tortoise-docker) created the original Docker and Compose project.
* [kasperfriend/tortoise-docker](https://github.com/kasperfriend/tortoise-docker) extended that work with updated builds, Playerbot support, configuration files and Windows helper scripts.
* This repository, [pjw345/tortoise-docker](https://github.com/pjw345/tortoise-docker), was created from Kasperfriend’s fork and now maintains a pinned, tested and reproducible deployment.

### Server and Playerbot source

* [tortoise-wow/tortoise-wow](https://github.com/tortoise-wow/tortoise-wow) is the active Tortoise server project.
* [Shyalya/tortoise-wow](https://github.com/Shyalya/tortoise-wow) integrated Playerbots with the Tortoise server.
* [pjw345/tortoise-wow](https://github.com/pjw345/tortoise-wow) preserves the tested integration source used by this Docker project.
* The Playerbot implementation originates from [cmangos/playerbots](https://github.com/cmangos/playerbots).

The currently published images build the server from the pinned commit [`f2df1b6`](https://github.com/pjw345/tortoise-wow/tree/f2df1b6aff7ea589db4682836d7652ada77f9377).

The setup process is demonstrated in this walkthrough:

**[Easiest Automated TurtleWoW 1.18.1 Server with Bots Tutorial](https://youtu.be/BFJes1sIi6c)**

## Published images

GitHub Actions builds and publishes two image variants:

| Variant             | Image                                       |
| ------------------- | ------------------------------------------- |
| Playerbots enabled  | `ghcr.io/pjw345/tortoise-docker:playerbots` |
| Playerbots disabled | `ghcr.io/pjw345/tortoise-docker:no-bots`    |

The published binaries use the portable `x86-64-v2` CPU target, so they do not depend on the instruction set of the GitHub Actions runner that compiled them.

## Requirements

* Docker Desktop, or Docker Engine with Compose v2
* A Turtle WoW **1.18.1** client using **build 7272**
* Extracted client data folders: `dbc`, `maps`, `vmaps` and `mmaps`
* Several gigabytes of free disk space

The Docker images do not contain client data. You must extract these folders from your own game client.

## Quick start

### 1. Download the project

```bash
git clone https://github.com/pjw345/tortoise-docker
cd tortoise-docker
```

### 2. Create your settings file

On Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

On Linux or macOS:

```bash
cp .env.example .env
```

Open `.env` and configure at least:

1. `DB_ROOT_PASSWORD`
2. `DB_PASSWORD`
3. `REALM_ADDRESS`
4. `DATA_PATH`
5. `AI_MIN_RANDOM_BOTS`
6. `AI_MAX_RANDOM_BOTS`

Use strong, different values for `DB_ROOT_PASSWORD` and `DB_PASSWORD`.

Use `127.0.0.1` for `REALM_ADDRESS` only when the game client runs on the same computer as the server. If the client runs on another computer, use an address that computer can reach, such as the server’s LAN IP address.

The bot-count values in `.env` are rendered into the Playerbot configuration whenever the container starts.

### 3. Add the client data

Place the extracted folders under `data`, or the directory selected by `DATA_PATH`:

```text
data/
  dbc/
  maps/
  vmaps/
  mmaps/
```

### 4. Start the server

On Windows, you can use:

```powershell
.\start-server.cmd
```

Alternatively, start it directly with Docker Compose:

```bash
docker compose up -d
```

Check the container state:

```bash
docker compose ps -a
```

On the first start, the database container creates and imports the server databases. Check its progress with:

```bash
docker compose logs -f db-init
```

Wait for:

```text
Database init complete.
```

Press `Ctrl+C` to leave the log viewer. This does not stop the containers.

Now follow the world-server startup:

```bash
docker compose logs -f mangosd
```

The first Playerbot startup can take considerably longer than later starts because the server builds its bot equipment cache. Large numbers of statements involving `ai_playerbot_equip_cache` are expected during this process.

Do not create an account until the log shows:

```text
World server is up and running
```

If the message has scrolled out of view, check for it with PowerShell:

```powershell
docker compose logs mangosd |
    Select-String -Pattern 'World server is up and running'
```

### 5. Create a game account

On Windows, the recommended method is:

```powershell
.\create-account.cmd
```

Alternatively, send the command directly to the world-server console:

```bash
docker compose exec -u turtle mangosd bash -c 'echo "account create myuser mypass" > /opt/turtle/run/mangosd.in'
```

You can verify that the account exists with:

```bash
docker compose exec -T db mariadb -uroot -pYOUR_ROOT_PASSWORD -e "SELECT id, username FROM tw_logon.account;"
```

Replace `YOUR_ROOT_PASSWORD` with the `DB_ROOT_PASSWORD` value from `.env`.

### 6. Connect with the game client

Edit `realmlist.wtf` in your Turtle WoW client:

```text
set realmlist 127.0.0.1
```

Use the same reachable host configured as `REALM_ADDRESS`.

You can then start the client and sign in using the account you created.

## Configuration files

The tracked files under `config` use the `.conf.dist` suffix. These are the configuration templates supplied by the repository.

When a container starts, it creates the corresponding local `.conf` file if one does not already exist. Existing `.conf` files are preserved, allowing local settings to survive container recreation and image updates.

Generated `.conf` files are intentionally excluded from Git.

Where a setting is exposed through `.env`, the startup scripts render its current value into the generated configuration.

## Useful settings

| Setting                |                 Default | Meaning                                                           |
| ---------------------- | ----------------------: | ----------------------------------------------------------------- |
| `REALM_ADDRESS`        |             `127.0.0.1` | Address the game client uses to reach the server                  |
| `REALM_NAME`           |             `TurtleWoW` | Realm name displayed by the client                                |
| `DATA_PATH`            |                `./data` | Directory containing the extracted client data                    |
| `TAG`                  |            `playerbots` | Published image variant: `playerbots` or `no-bots`                |
| `TURTLE_IMAGE`         | Image selected by `TAG` | Optional complete image reference, including locally built images |
| `AI_PLAYERBOT_ENABLED` |                     `1` | Enables or disables Playerbots                                    |
| `AI_MIN_RANDOM_BOTS`   |                    `10` | Minimum number of random bots                                     |
| `AI_MAX_RANDOM_BOTS`   |                    `10` | Maximum number of random bots                                     |

Keep the bot count low for the first startup. After the initial cache has been created, adjust the values in `.env` and recreate `mangosd`:

```bash
docker compose up -d --force-recreate mangosd
```

## Common commands

Show the container status:

```bash
docker compose ps -a
```

Follow the database initialisation log:

```bash
docker compose logs -f db-init
```

Follow the authentication-server log:

```bash
docker compose logs -f realmd
```

Follow the world-server log:

```bash
docker compose logs -f mangosd
```

Stop the running containers without removing them:

```bash
docker compose stop
```

Start the containers again:

```bash
docker compose up -d
```

Stop and remove the containers while retaining the database volumes:

```bash
docker compose down
```

## Backups and updates

Always create a complete database backup before updating an existing installation.

Published images are built only following a deliberate repository update or a manually triggered GitHub Actions workflow. They are not automatically rebuilt from a moving upstream branch.

Before updating:

1. Back up all databases.
2. Confirm which image and source commit will be used.
3. Stop `mangosd` and `realmd`.
4. Pull and test the new image.
5. Retain the previous database volume and backup until the updated server has been verified.

Database migrations may be applied automatically when a newer server image starts. Do not update an important installation without a recoverable backup.

## Resetting the database

> **Warning:** This permanently deletes the project’s accounts, characters, world database and initialisation marker.

Confirm that you are operating on the correct Compose project before running:

```bash
docker compose down -v
docker compose up -d
```

Do not use this procedure when updating an existing installation or attempting to preserve characters.

## CPU compatibility and local builds

If an image exits with code `132` (`SIGILL`), build it locally with the portable CPU target:

```bash
docker build \
  --build-arg BUILD_PLAYERBOTS=ON \
  --build-arg CPU_TARGET=x86-64-v2 \
  -t tortoise-wow:playerbots-local .
```

Select the local image when starting Compose:

```bash
TURTLE_IMAGE=tortoise-wow:playerbots-local docker compose up -d
```

On Windows PowerShell:

```powershell
$env:TURTLE_IMAGE = 'tortoise-wow:playerbots-local'
docker compose up -d
```

Remove the temporary PowerShell environment override afterward with:

```powershell
Remove-Item Env:TURTLE_IMAGE
```

## Troubleshooting

| Problem                                   | What to check                                                                                         |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Login fails or the account is unknown     | Wait for `World server is up and running`, then create or verify the account                          |
| Account creation does nothing             | `mangosd` may still be starting; check its logs and retry once it is ready                            |
| Realm list is empty or offline            | Run `docker compose ps -a` and confirm both `realmd` and `mangosd` are running                        |
| Client hangs after selecting the realm    | Confirm that `REALM_ADDRESS` is reachable from the client and that port `8090` is available           |
| World is empty or NPCs are missing        | Check `docker compose logs db-init` for an incomplete database import                                 |
| Database migration fails                  | Stop `mangosd`, retain the database and inspect the complete migration error before changing any data |
| Playerbots are unavailable                | Use the `playerbots` image and set `AI_PLAYERBOT_ENABLED=1`                                           |
| First startup produces many cache inserts | This is expected while Playerbot equipment data is generated                                          |
| Client reports a corrupt interface        | Use the expected Turtle WoW client and do not remove required Turtle addons                           |

## Credits

This project would not exist without the work of the following projects and contributors:

* Original Docker and Compose project: [Nescabir/tortoise-docker](https://github.com/Nescabir/tortoise-docker)
* Docker and Playerbot deployment work used as the basis of this fork: [kasperfriend/tortoise-docker](https://github.com/kasperfriend/tortoise-docker)
* Setup walkthrough: [Easiest Automated TurtleWoW 1.18.1 Server with Bots Tutorial](https://youtu.be/BFJes1sIi6c)
* Active Tortoise server project: [tortoise-wow/tortoise-wow](https://github.com/tortoise-wow/tortoise-wow)
* Tortoise and Playerbot integration: [Shyalya/tortoise-wow](https://github.com/Shyalya/tortoise-wow)
* Playerbot project: [cmangos/playerbots](https://github.com/cmangos/playerbots)
* Tested integration source: [pjw345/tortoise-wow at `f2df1b6`](https://github.com/pjw345/tortoise-wow/tree/f2df1b6aff7ea589db4682836d7652ada77f9377)
* Installation notes for the tested source: [INSTALL-LINUX.md](https://github.com/pjw345/tortoise-wow/blob/f2df1b6aff7ea589db4682836d7652ada77f9377/INSTALL-LINUX.md)

All original copyright notices and project licences remain applicable.

This repository maintains the Docker packaging and deployment integration. The server and Playerbot source remain governed by their respective upstream licences.

## Disclaimer

This is an unofficial community project. It is not affiliated with or endorsed by Turtle WoW, Blizzard Entertainment or Microsoft.
