# Tortoise WoW with Playerbots on Ubuntu (Docker Engine)

> **Important:** This repository pins the server source to a tested commit. Always create a full database backup before changing the image or source commit.

Run a private [Turtle WoW](https://turtle-wow.org/) server with Docker, with optional Playerbot support.

This repository maintains the Docker packaging, database initialisation and deployment configuration needed to build and run a tested version of the server.

## Current deployment

On 2026-10-11 we completed the migration from Windows Docker Desktop to an
**Ubuntu Server VM hosted by Windows Hyper-V**. Development, compilation and
server containers now run inside Ubuntu. Windows runs Hyper-V and the game
client; Docker Desktop and the old Windows server/build folders were retired.

```text
Windows host: Hyper-V + Turtle WoW client
  Ubuntu Server VM: Docker Engine + Compose
    MariaDB -> db-init -> realmd + mangosd (Playerbots)
```

The tested core revision is `76c1741d80e44ba5050b87445b5a8f729d1f6a10` on
[`pjw345/tortoise-wow`, branch `playerbots-development`](https://github.com/pjw345/tortoise-wow/tree/playerbots-development).
Follow the local build below to reproduce that revision. This documentation
change does not update the Dockerfile default or rebuild GHCR images.

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

The Dockerfile and publishing workflow currently default to the older pinned
commit [`7f3cd5e`](https://github.com/pjw345/tortoise-wow/tree/7f3cd5e660db013e6d64965621ef77b2666390b1).
The walkthrough below explicitly builds `76c1741d`; do not assume a mutable
published tag contains the same source.

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

* An x86-64 Hyper-V host with hardware virtualization enabled, or an existing Linux server
* Ubuntu Server and Docker Engine with the Compose plugin (`docker compose`)
* A Turtle WoW **1.18.1** client using **build 7272**
* Extracted client data folders: `dbc`, `maps`, `vmaps` and `mmaps`
* For local compilation: a practical starting allocation of 4 vCPUs, 12 GB RAM and a 120 GB virtual disk; compile with two jobs initially

The Docker images do not contain client data. You must extract these folders from your own game client.

## Ubuntu Hyper-V setup

These instructions are for a **new installation**. Our VM was validated on
Ubuntu Server 26.04.1 LTS, with 12 GB fixed RAM, 10 vCPUs and approximately
120 GB disk. The container OS remains Ubuntu 22.04. Different bot counts and
build concurrency change memory/disk needs; leave capacity on the Windows host.

### 1. Prepare the VM

1. Enable Hyper-V on a supported Windows edition and create a **Generation 2** VM.
2. Use fixed memory initially and attach an **External virtual switch** so the Windows client can reach the VM on the LAN.
3. Attach the Ubuntu Server amd64 ISO and boot from its DVD drive. For Secure Boot, select **Microsoft UEFI Certificate Authority**; a virtual TPM is not required for this setup.
4. Install Ubuntu Server with OpenSSH, then detach the ISO and boot from the installed disk.
5. Reserve the VM's LAN address in DHCP. If using a hostname, ensure it resolves from every client; `.localdomain` is not automatically supplied by Hyper-V.
6. Disable automatic checkpoints for this deployment; create deliberate recovery points when needed. Checkpoints are not independent database backups.

See Microsoft's [VM creation guide](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/create-a-virtual-machine-in-hyper-v)
and [Linux Secure Boot guidance](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/best-practices-for-running-linux-on-hyper-v).

Connect using SSH (MobaXTerm on Windows is suitable):

```bash
ssh youruser@YOUR_VM_IP
```

Run the remaining commands **inside Ubuntu**, as your regular user.

### 2. Install Docker Engine

Install Git and follow Docker's [official Ubuntu apt-repository instructions](https://docs.docker.com/engine/install/ubuntu/)
to configure the Docker package repository, then install its packages:

```bash
sudo apt update
sudo apt install -y git ca-certificates curl
# After configuring Docker's official apt repository:
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Disconnect and reconnect SSH for group membership to take effect. The Docker
group grants control of the host daemon; use it only for trusted users.

```bash
docker version
docker compose version
```

Docker Desktop and nested virtualization are not needed: Linux containers run
directly on the Ubuntu VM's kernel.

## Fresh installation

Keep this checkout separate from any existing production deployment. Do not
copy the example settings over a populated server or use a new Compose project
as a substitute for migrating its database volumes.

### 1. Download the project

```bash
mkdir -p ~/development
cd ~/development
git clone --branch master https://github.com/pjw345/tortoise-docker.git
cd tortoise-docker
```

### 2. Build the tested Playerbots revision

```bash
SOURCE_COMMIT=76c1741d80e44ba5050b87445b5a8f729d1f6a10
docker build \
  --build-arg SOURCE_COMMIT="$SOURCE_COMMIT" \
  --build-arg BUILD_PLAYERBOTS=ON \
  --build-arg BUILD_JOBS=2 \
  --build-arg CPU_TARGET=x86-64-v2 \
  --tag tortoise-wow:playerbots-76c1741d .
docker run --rm --entrypoint cat tortoise-wow:playerbots-76c1741d /opt/turtle/SOURCE_COMMIT
```

Check that the printed full SHA matches `SOURCE_COMMIT`. The Dockerfile fetches
source from GitHub; it does not compile an adjacent working copy. New source
changes must be committed and pushed before building their revision. A first
build downloads dependencies and compiles the full server; allow plenty of time.

### 3. Create your settings file

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Open `.env` and configure at least:

1. `DB_ROOT_PASSWORD`
2. `DB_PASSWORD`
3. `REALM_ADDRESS`
4. `DATA_PATH`
5. `AI_MIN_RANDOM_BOTS`
6. `AI_MAX_RANDOM_BOTS`

Also set `TURTLE_IMAGE` to the local build. For example, replace the network
address below with **your VM's reserved address**:

```dotenv
TURTLE_IMAGE=tortoise-wow:playerbots-76c1741d
REALM_ADDRESS=192.168.2.130
GAME_BIND_IP=192.168.2.130
DATA_PATH=./data
AI_MIN_RANDOM_BOTS=10
AI_MAX_RANDOM_BOTS=10
```

The sample IP is not a required address. `REALM_ADDRESS` is advertised to the
client; `GAME_BIND_IP` selects a VM interface for the published ports. Database
port 3306 stays bound to VM loopback in the supplied Compose file. Clients need
TCP ports 3724 and 8090. Configure LAN/firewall access deliberately; Docker port
publishing can bypass ordinary UFW rules (see the Docker installation guide).

Use strong, different values for `DB_ROOT_PASSWORD` and `DB_PASSWORD`.

Use `127.0.0.1` for `REALM_ADDRESS` only when the game client runs on the same computer as the server. If the client runs on another computer, use an address that computer can reach, such as the server’s LAN IP address.

The bot-count values in `.env` are rendered into the Playerbot configuration whenever the container starts.

### 4. Add the client data

Place the extracted folders under `data`, or the directory selected by `DATA_PATH`:

```text
data/
  dbc/
  maps/
  vmaps/
  mmaps/
```

Use extractors built from the matching core revision: `mapextractor` produces
`dbc` and `maps`; `vmapextractor` followed by `vmap_assembler` produces `vmaps`;
`MoveMapGen` produces `mmaps`. Run extraction against your own matching client
files; generating movement maps can take hours. You can transfer already
verified folders from your client machine using SFTP/MobaXTerm.

To build an extractor image from this packaging, use the same Docker build
above with `USE_EXTRACTORS=ON`, `EXTRACTORS_ONLY=ON` and a different image tag.
Those tools are installed under `/opt/turtle/bin`; mount your client directory
and run them with that directory as their working directory. Keep this image
separate from the server image: it contains extractors rather than server binaries.

Validate DBC files with the core repository's
[`dbc_verifier.py` and expected manifest](https://github.com/pjw345/tortoise-wow/tree/playerbots-development/tools/dbc_verification).
The source README specifies the required build and hotfix level. Do not download
unrelated map/DBC packs and assume they match this fork.

### 5. Start the server

```bash
docker compose config --quiet
docker compose up -d realmd mangosd
```

Check the container state:

```bash
docker compose ps -a
```

On the first start, MariaDB becomes healthy and the one-shot `db-init` service
imports schemas, world content, Playerbot tables and migration records. Named
volumes preserve the database, initialization marker and logs. Check progress with:

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

If the message has scrolled out of view, check it in Ubuntu:

```bash
docker compose logs mangosd | grep 'World server is up and running'
```

### 6. Create a game account

Once the world server is ready, send the command to its console. Replace the
example username/password; this is a **game account**, separate from GitHub:

```bash
docker compose exec -u turtle mangosd bash -c 'echo "account create myuser mypass" > /opt/turtle/run/mangosd.in'
```

Check the response in `docker compose logs --tail 30 mangosd`.

### 7. Connect with the game client

Edit `realmlist.wtf` in your Turtle WoW client:

```text
set realmlist 192.168.2.130
```

Replace the example with the same reachable host configured as `REALM_ADDRESS`.

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
docker compose stop -t 120 mangosd realmd db
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

For the default four database names, take a logical backup while the game and
login services are stopped and MariaDB remains running:

```bash
umask 077
backup_dir="$HOME/turtlewow-backups/$(date -u +%Y%m%d-%H%M%S)"
mkdir -p "$backup_dir"
docker compose stop -t 120 mangosd realmd
docker compose exec -T db sh -c 'exec mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --single-transaction --routines --events --triggers --databases tw_logon tw_world tw_char tw_logs' > "$backup_dir/databases.sql"
tar -czf "$backup_dir/deployment.tar.gz" .env docker-compose.yml config docker
(cd "$backup_dir" && sha256sum databases.sql deployment.tar.gz > SHA256SUMS)
```

Check each command succeeded before relying on the backup. Adjust database
names if you changed them in `.env`. Also retain the image reference/embedded
source SHA, initialization-marker state and matching client data (or a verified
way to regenerate it). Protect backups as credentials/account data, copy them
outside the VM and test a restore using separate volumes and no published ports.
For a physical database-volume backup, stop MariaDB cleanly first and use a
compatible MariaDB version to restore it. Do not copy its live data directory.

Restart the server after a successful backup with
`docker compose up -d realmd mangosd`.

Published images are built only following a deliberate repository update or a manually triggered GitHub Actions workflow. They are not automatically rebuilt from a moving upstream branch.

Before updating:

1. Back up all databases.
2. Confirm which image and source commit will be used.
3. Stop `mangosd` and `realmd`.
4. Pull and test the new image.
5. Retain the previous database volume and backup until the updated server has been verified.

Database migrations may be applied automatically when a newer server image starts. Do not update an important installation without a recoverable backup.

For source updates, clone `pjw345/tortoise-wow` on `playerbots-development`,
review and commit/push changes, then supply the full new SHA as `SOURCE_COMMIT`
and use a new image tag. Set that tag in `.env` as `TURTLE_IMAGE`, then recreate
`realmd` and `mangosd` with `docker compose up -d --force-recreate realmd mangosd`.
Verify `/opt/turtle/SOURCE_COMMIT`, startup logs and the affected gameplay.
Keep the previous image and database backup: an older binary may not be
compatible with a database after newer migrations.

## Disk and log retention

Check usage regularly:

```bash
df -h /
docker system df
docker image ls
docker volume ls
```

Keep the current server image and one known-good rollback image, plus images
referenced by containers. Remove only reviewed obsolete tags with
`docker image rm IMAGE_TAG`. Build cache can be bounded with
`docker buildx prune --max-used-space 20GB`; it does not delete database volumes.
Do not use `docker system prune --volumes` for routine cleanup.

Configure Docker's container-log rotation and rotate the separate world/Playerbot
files in the `mangosd-logs` volume. Container log rotation alone does not rotate
those application files. Our deployment uses the Docker `local` driver with
10 MB / three-file limits, a 20 GB builder-cache target and weekly image review;
these are host settings, **not automatically installed by cloning this repository**.
Retain independent backups until a newer backup has passed an isolated restore.

## GitHub authentication for development

Public cloning/building does not need a GitHub login. To push your own changes
from Ubuntu, install GitHub CLI and authenticate as an account with repository
write permission (or push to your own fork):

```bash
sudo apt install -y gh
gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git
gh auth status
```

Complete the one-time code flow in your Windows browser. Credentials stay in
your Ubuntu user profile; do not add them to `.env`, images or Git. Development
commits and README changes do not update the running server until you build and
select a new image.

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
  --build-arg SOURCE_COMMIT=76c1741d80e44ba5050b87445b5a8f729d1f6a10 \
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
* Tested Ubuntu deployment source: [pjw345/tortoise-wow at `76c1741d`](https://github.com/pjw345/tortoise-wow/tree/76c1741d80e44ba5050b87445b5a8f729d1f6a10)

All original copyright notices and project licences remain applicable.

This repository maintains the Docker packaging and deployment integration. The server and Playerbot source remain governed by their respective upstream licences.

## Disclaimer

This is an unofficial community project. It is not affiliated with or endorsed by Turtle WoW, Blizzard Entertainment or Microsoft.


## Incremental development builds on the Ubuntu VM

The TurtleWoW dashboard uses the local core checkout and the `local-builder`
stage. The normal self-contained Docker/GHCR build remains the default and
continues fetching its pinned revision from GitHub.

For normal operation use the dashboard or guarded manager CLI:

```bash
python3 ~/development/turtlewow-manager/manager.py build
```

This stops the realm, verifies a cold backup, builds a uniquely tagged image and
checks its embedded source SHA. Activation and startup remain separate actions.
The manager supplies `--build-context local-core=PATH` and
`--build-arg BUILD_SOURCE=local-builder`; no host compiler installation is needed.
The context must be a complete Git checkout with local objects for the requested
core and initialized submodule revisions. The builder only reads that checkout.

A locked BuildKit cache retains a single source checkout, CMake build tree and
object files per platform. Unchanged files retain timestamps; changed source,
headers and flags trigger the normal dependency rebuild. ccache provides a
secondary compiler-result cache capped at 3 GB. The complete object tree consumes
additional disk space. Image packaging still runs when necessary.

The first build populates the cache. Cache eviction/pruning, compiler changes or
broad header changes can still cause a substantial rebuild. Retain build cache
during routine image cleanup; it contains no game database or deployment secrets.
The runtime image keeps the same binaries, SQL, source SHA and entrypoint layout.

Validate the incremental dependency contract without a game/database:

```bash
docker build --target local-toolchain -t turtlewow-incremental-toolchain:test .
python3 tests/test_incremental.py turtlewow-incremental-toolchain:test
docker image rm turtlewow-incremental-toolchain:test
```

The isolated offline fixture verifies unchanged/documentation-only object reuse,
single-file and shared-header dependency rebuilds, older revision selection,
submodule access, compilation failure and missing-source rejection.
