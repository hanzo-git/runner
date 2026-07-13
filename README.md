# Git Runner

## Installation

### Prerequisites

Docker Engine Community version is required for docker mode. To install Docker CE, follow the official [install instructions](https://docs.docker.com/engine/install/).

### Download pre-built binary

Visit [here](https://dl.git.hanzo.ai/git-runner/) and download the right version for your platform.

### Build from source

```bash
make build
```

### Build a docker image

```bash
make docker
```

## Quickstart

Actions are disabled by default, so you need to add the following to the configuration file of your Git instance to enable it:

```ini
[actions]
ENABLED=true
```

### Register

```bash
./git-runner register
```

And you will be asked to input:

1. Git instance URL, like `http://192.168.8.8:3000/`. You should use your Git instance ROOT_URL as the instance argument
 and you should not use `localhost` or `127.0.0.1` as instance IP;
2. Runner token, you can get it from `http://192.168.8.8:3000/admin/actions/runners`;
3. Runner name, you can just leave it blank;
4. Runner labels, you can just leave it blank.

The process looks like:

```text
INFO Registering runner, arch=amd64, os=darwin, version=0.1.5.
WARN Runner in user-mode.
INFO Enter the Git instance URL (for example, https://git.hanzo.ai/):
http://192.168.8.8:3000/
INFO Enter the runner token:
fe884e8027dc292970d4e0303fe82b14xxxxxxxx
INFO Enter the runner name (if set empty, use hostname: Test.local):

INFO Enter the runner labels, leave blank to use the default labels (comma-separated, for example, ubuntu-latest:docker://ghcr.io/hanzoai/runner-ubuntu:latest):

INFO Registering runner, name=Test.local, instance=http://192.168.8.8:3000/, labels=[ubuntu-latest:docker://ghcr.io/hanzoai/runner-ubuntu:latest ubuntu-22.04:docker://ghcr.io/hanzoai/runner-ubuntu:latest ubuntu-20.04:docker://ghcr.io/hanzoai/runner-ubuntu:latest].
DEBU Successfully pinged the Git instance server
INFO Runner registered successfully.
```

You can also register with command line arguments.

```bash
./git-runner register --instance http://192.168.8.8:3000 --token <my_runner_token> --no-interactive
```

If the registry succeed, it will run immediately. Next time, you could run the runner directly.

### Run

```bash
./git-runner daemon
```

### Run with docker

```bash
docker run -e GIT_INSTANCE_URL=https://your_git.hanzo.ai -e GIT_RUNNER_TOKEN=<your_token> -v /var/run/docker.sock:/var/run/docker.sock --name my_runner ghcr.io/hanzoai/git-runner:nightly
```

Mount a volume on `/data` if you want the registration file and optional config to survive container recreation (see [scripts/run.sh](scripts/run.sh)).

### Image flavours

The image is published in three flavours, all built from the single multi-stage [Dockerfile](Dockerfile) in this repository. They differ only in how a Docker daemon is made available to the jobs the runner executes; the `git-runner` binary inside them is identical.

| Tag | Build target | Base image | Docker daemon | Process supervisor | Runs as |
| --- | --- | --- | --- | --- | --- |
| `latest` (and `<version>`) | `basic` | `alpine` | none — uses an external daemon you provide | [`tini`](https://github.com/krallin/tini) | `root` |
| `latest-dind` | `dind` | `docker:dind` | bundled, started inside the container | [`s6`](https://skarnet.org/software/s6/) | `root` (privileged) |
| `latest-dind-rootless` | `dind-rootless` | `docker:dind-rootless` | bundled, started rootless inside the container | [`s6`](https://skarnet.org/software/s6/) | `rootless` (UID 1000) |

#### `latest` — basic

The default flavour ships only the runner on a minimal Alpine base. It contains **no Docker daemon of its own**: jobs that use `docker://` images need a daemon supplied from outside the container, typically by bind-mounting the host's socket:

```bash
docker run -e GIT_INSTANCE_URL=https://your_git.hanzo.ai -e GIT_RUNNER_TOKEN=<your_token> \
  -v /var/run/docker.sock:/var/run/docker.sock --name my_runner ghcr.io/hanzoai/git-runner:latest
```

`tini` is the entrypoint (it reaps zombie processes), and it just runs [`scripts/run.sh`](scripts/run.sh), which registers the runner on first start and then execs `git-runner daemon`. This flavour does not need `--privileged`. The trade-off is that jobs share the host's daemon, so they can see other containers and images on that daemon.

#### `latest-dind` — Docker-in-Docker

This flavour is based on the official `docker:dind` image and bundles its own Docker daemon, so it needs no external socket — only the `--privileged` flag that Docker-in-Docker requires:

```bash
docker run --privileged -e GIT_INSTANCE_URL=https://your_git.hanzo.ai -e GIT_RUNNER_TOKEN=<your_token> \
  --name my_runner ghcr.io/hanzoai/git-runner:latest-dind
```

Two processes have to run side by side here (the Docker daemon and the runner), so the entrypoint is the [`s6`](https://skarnet.org/software/s6/) supervision tree under [`scripts/s6`](scripts/s6) instead of `tini`. `s6` starts `dockerd`, and the runner service waits for the daemon to come up (`s6-svwait`) before launching [`run.sh`](scripts/run.sh). Each container has a private daemon isolated from the host's, at the cost of running privileged.

#### `latest-dind-rootless` — rootless Docker-in-Docker

Same idea as `dind`, but built on `docker:dind-rootless` so the bundled daemon and the runner run as an unprivileged user (`rootless`, UID 1000) rather than `root`. `DOCKER_HOST` is preset to `unix:///run/user/1000/docker.sock` so the runner talks to the rootless daemon. This reduces the blast radius compared to the privileged `dind` flavour, but rootless Docker carries the usual rootless limitations (networking, cgroups, storage drivers, and some operations that need additional host configuration such as `/etc/subuid` / `/etc/subgid` mappings and unprivileged user-namespace support).

> **Note on Podman:** these images target the Docker daemon. The bundled `dind`/`dind-rootless` daemons are `dockerd`, not Podman, and the `basic` flavour expects a Docker-compatible socket. Running them under rootless Podman is not a supported configuration, though pointing the `basic` flavour at a Podman socket that emulates the Docker API may work for some workloads.

### Configuration

The runner is configured with a YAML file. Generate a starting point (this matches what ships in the tree):

```bash
./git-runner generate-config > config.yaml
```

Pass it with `-c` / `--config` on any command that loads configuration (`register`, `daemon`, `cache-server`):

```bash
./git-runner -c config.yaml register
./git-runner -c config.yaml daemon
./git-runner -c config.yaml cache-server
```

Every option is described in [config.example.yaml](internal/pkg/config/config.example.yaml) (the same content `generate-config` prints).

#### Without a config file

If you omit `-c`, built-in defaults apply (same as an empty YAML document). A small set of **deprecated** environment variables can still override parts of that default config, but **only when no `-c` path was given**; they are ignored if you use a config file:

| Variable | Effect |
| --- | --- |
| `GIT_DEBUG` | If true, sets log level to `debug` |
| `GIT_TRACE` | If true, sets log level to `trace` |
| `GIT_RUNNER_CAPACITY` | Concurrent jobs (integer) |
| `GIT_RUNNER_FILE` | Registration state file path (default `.runner`) |
| `GIT_RUNNER_ENVIRON` | Extra job env vars as comma-separated `KEY:VALUE` pairs |
| `GIT_RUNNER_ENV_FILE` | Path to an env file merged into job env (same idea as `runner.env_file` in YAML) |

Prefer a YAML file for all settings.

#### Registration vs config labels

If `runner.labels` is set in the YAML file, those labels are used during `register` and the `--labels` CLI flag is ignored.

#### Caching (`actions/cache`)

Each runner starts its own cache server automatically. Cache entries are local to that runner — runners do not share a cache by default.

**Shared cache across multiple runners**

Run one dedicated `git-runner cache-server` that all runners point at.

1. Create a config file for the cache server host:

   ```yaml
   cache:
     dir: /data/actcache
     port: 8088
     external_secret: "replace-with-a-strong-random-secret"
   ```

2. Start the server:

   ```bash
   git-runner -c cache-server-config.yaml cache-server
   ```

3. On every runner:

   ```yaml
   cache:
     external_server: "http://<cache-server-host>:8088/"
     external_secret: "replace-with-a-strong-random-secret"  # must match the server
   ```

Alternatively, mount the same NFS/CIFS share on every runner and point `cache.dir` at it — simpler, but with weaker isolation between repositories.

**S3 / MinIO** — mount object storage as a FUSE filesystem (e.g. [s3fs](https://github.com/s3fs-fuse/s3fs-fuse) or [goofys](https://github.com/kahing/goofys)) and set `cache.dir` to the mount point.

Flags `--dir`, `--host`, and `--port` on `cache-server` override the corresponding `cache.*` YAML keys; all other settings, including `external_secret`, require the config file.

#### Official Docker image

Besides `GIT_INSTANCE_URL` and `GIT_RUNNER_TOKEN`, the image entrypoint supports optional variables such as `CONFIG_FILE` (passed through as `-c`), `GIT_RUNNER_LABELS`, `GIT_RUNNER_EPHEMERAL`, `GIT_RUNNER_ONCE`, `GIT_RUNNER_NAME`, `GIT_MAX_REG_ATTEMPTS`, `RUNNER_STATE_FILE`, and `GIT_RUNNER_TOKEN_FILE`. See [scripts/run.sh](scripts/run.sh) for exact behavior.

For a fuller container-oriented walkthrough, see [examples/docker](examples/docker/README.md).

When `container.bind_workdir` is enabled, stale task workspace directories can be cleaned while the runner is idle:
- directories older than `runner.workdir_cleanup_age` are removed (default: `24h`; set `0` to disable)
- cleanup runs every `runner.idle_cleanup_interval` (default: `10m`; set `0` to disable)
- only purely numeric subdirectories under `container.workdir_parent` are treated as task workspaces and may be removed
- cleanup assumes `container.workdir_parent` is not shared across multiple runners

#### Post-task script (`runner.post_task_script`)

Optional host script that runs **after** each task's built-in cleanup (post-steps, container teardown, bind-workdir removal). Use it for extra machine housekeeping — Docker pruning, disk cleanup, and similar.

**While the script runs, the runner stops task heartbeats and stays offline from Git's perspective until the script exits (or hits `runner.post_task_script_timeout`, default `5m`).** A script that blocks without exiting keeps the runner from taking new work for up to that timeout. Script output goes to the runner log, not the job log; a non-zero exit is warned but does not change the job result.

On Windows, use `.exe`, `.bat`, or `.cmd` paths; **PowerShell (`.ps1`) is not supported yet** as the configured path — wrap commands in a `.cmd` file instead.

See **[docs/post-task-script.md](docs/post-task-script.md)** for lifecycle details, environment variables, timeout interaction, and platform notes.

### Example Deployments

Check out the [examples](examples) directory for sample deployment types.
