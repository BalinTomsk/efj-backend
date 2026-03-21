# DigitalOcean Deployment

This service is a background worker with no HTTP API. On DigitalOcean, the best fit is:

- `DigitalOcean Container Registry (DOCR)` to store the image
- `App Platform` with a `Worker` component to run it

If you want to manage the VM yourself, you can also run the same image on a Droplet. App Platform is the simpler option.

## 1. Register the image in DigitalOcean Container Registry

### Option A: push a locally built image

If you already built the image locally:

```powershell
docker build -t water-station-pusher:1.0.1 .
```

Create a registry in DigitalOcean:

1. Open `cloud.digitalocean.com`.
2. Go to `Container Registry`.
3. Click `Create Registry`.
4. Choose a registry name and plan.

Install and authenticate `doctl`, then log Docker in to DOCR:

```powershell
doctl auth init
doctl registries login envfish
```

Current `doctl` requires the registry name as an argument. If you do not know it yet:

```powershell
doctl registries list
```

Tag the local image for your registry:

```powershell
docker tag water-station-pusher:1.0.1 registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.1
```

Push it:

```powershell
docker push registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.1
```

### Option B: push the existing tar image from this repo

This repo already contains `water-station-pusher-1.0.1.tar`.

Load it into Docker first:

```powershell
docker load -i water-station-pusher-1.0.1.tar
```

Then find the loaded image:

```powershell
docker images
```

Tag and push it to DOCR:

```powershell
docker tag water-station-pusher:1.0.1 registry.digitalocean.com/<registry-name>/waterservice/water-station-pusher:1.0.1
docker push registry.digitalocean.com/<registry-name>/waterservice/water-station-pusher:1.0.1
```

After the push, confirm the repository and tag appear in `Container Registry` in the DigitalOcean control panel.

### Notes about what you see in the registry UI

The DigitalOcean control panel can show multiple image entries for a single push. That does not necessarily mean you built or pushed the app three times.

Typical layout:

- one tagged digest such as `1.0.1`
- one larger digest that contains the actual platform image
- one small untagged digest shown as `none`

DOCR counts digests and manifests, not just the human-facing tag. Small extra entries are commonly metadata or manifest artifacts. If you want to inspect what was pushed:

```powershell
doctl registries repository list-v2 envfish
doctl registries repository list-tags envfish waterservice/water-station-pusher
```

## 2. Run it on DigitalOcean App Platform

Because this service has no HTTP port, deploy it as a `Worker`, not a `Web Service`.

### Create the app

1. Open `cloud.digitalocean.com`.
2. Click `Create`.
3. Click `Apps`.
4. Choose `Container Registry` as the source.
5. Select `<registry-name>/waterservice/water-station-pusher:1.0.1`.
6. When App Platform asks for the component type, choose `Worker`.

### Configure the worker

Use these settings:

- Component type: `Worker`
- Source: your DOCR image
- HTTP port: none
- Instance count: `1`

Set these environment variables in the app:

- `DB_URL`
- `DB_USERNAME`
- `DB_PASSWORD`

You can also set:

- `JAVA_OPTS`
- `DOTENV_PATH` only if you intentionally mount or provide a dotenv file elsewhere

For App Platform, prefer plain environment variables instead of `.env`.

### Start command

In most cases, leave the command empty so DigitalOcean uses the image `ENTRYPOINT` from the Dockerfile:

```dockerfile
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /app/water-station-pusher.jar"]
```

If you want one-shot console mode instead of the normal worker loop, override the run command to:

```sh
java $JAVA_OPTS -jar /app/water-station-pusher.jar --console
```

If you want one station only:

```sh
java $JAVA_OPTS -jar /app/water-station-pusher.jar --console --station=02JE025
```

### Deploy

1. Review the app configuration.
2. Click `Create Resources`.
3. Wait for the deployment to finish.
4. Open `Runtime Logs` to verify startup.

Expected behavior:

- the worker starts
- it connects to SQL Server
- it begins processing stations
- no public URL is created, because this is not a web app

## 3. Database connectivity notes

This service needs outbound access from DigitalOcean to your SQL Server instance.

Check:

- the hostname in `DB_URL`
- firewall rules
- SQL Server port availability
- whether the database accepts connections from App Platform egress IPs or from your Droplet

If your SQL Server is running on your local machine, App Platform cannot reach `localhost` on your laptop. You need a publicly reachable database host, a VPN/private network design, or a Droplet that can reach the database.

## 4. Alternative: run the image on a Droplet

If you do not want App Platform, you can run the same image on a Debian Droplet.

Install Docker on the Droplet, log in to DOCR, then pull and run.

### Prepare the dotenv file on the Droplet

Create a directory on the Droplet host and copy your local `.env` values into a host file:

```bash
sudo mkdir -p /opt/waterservice
sudo nano /opt/waterservice/waterservice.env
```

Example content:

```env
DB_URL=jdbc:sqlserver://your-host:1433;databaseName=your_database;encrypt=true;trustServerCertificate=true
DB_USERNAME=your_username
DB_PASSWORD=your_password
```

This service reads credentials from:

- real environment variables first
- `DOTENV_PATH` second
- a `.env` file in the container working directory last

For a Droplet deployment, the most reliable option is to mount the host file and set `DOTENV_PATH` explicitly.

### Install Docker on the Droplet

Fresh Debian Droplets do not always have Docker installed. If `docker` is missing, install it first:

```bash
apt update
apt install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker --version
```

### Install doctl on the Droplet

Do not assume `snap` is available. On Debian, install `doctl` from the release tarball:

```bash
cd /tmp
curl -LO https://github.com/digitalocean/doctl/releases/download/v1.146.0/doctl-1.146.0-linux-amd64.tar.gz
tar xf doctl-1.146.0-linux-amd64.tar.gz
install -m 0755 doctl /usr/local/bin/doctl
doctl version
```

If `curl` is missing:

```bash
apt update
apt install -y curl
```

### Authenticate doctl

Interactive `doctl auth init` can fail on minimal server shells because clipboard helpers are not installed. Use the token flag instead:

```bash
doctl auth init -t "your_digitalocean_token"
```

If you do not want the token to remain visible in shell history:

```bash
read -s DIGITALOCEAN_ACCESS_TOKEN
doctl auth init -t "$DIGITALOCEAN_ACCESS_TOKEN"
unset DIGITALOCEAN_ACCESS_TOKEN
```

### Pull the image from DOCR

Check that the tag exists:

```bash
doctl registries repository list-tags envfish waterservice/water-station-pusher
```

Then authenticate Docker and pull the image:

```bash
doctl registries login <registry-name>
docker pull registry.digitalocean.com/<registry-name>/waterservice/water-station-pusher:1.0.1
```

For your current registry, that is:

```bash
doctl registries login envfish
docker pull registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.1
```

### Run the container with the mounted dotenv file

Mount the host file read-only and point `DOTENV_PATH` at the mounted location:

```bash
docker run -d \
  --name water-station-pusher \
  --restart unless-stopped \
  -v /opt/waterservice/waterservice.env:/run/secrets/waterservice.env:ro \
  -e DOTENV_PATH="/run/secrets/waterservice.env" \
  registry.digitalocean.com/<registry-name>/waterservice/water-station-pusher:1.0.1
```

For your current registry, that is:

```bash
docker run -d \
  --name water-station-pusher \
  --restart unless-stopped \
  -v /opt/waterservice/waterservice.env:/run/secrets/waterservice.env:ro \
  -e DOTENV_PATH="/run/secrets/waterservice.env" \
  registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.1
```

Do not pass `DB_URL`, `DB_USERNAME`, or `DB_PASSWORD` with `-e` when you want the container to use the mounted dotenv file, because process environment variables take precedence over dotenv values.

View logs:

```bash
docker logs -f water-station-pusher
```

This approach gives you more control, but you manage OS updates, restarts, logging, and Docker lifecycle yourself.

### Windows versus Droplet path note

Use Linux host paths like `/opt/waterservice/waterservice.env` only when you are logged into the Droplet shell over SSH.

If you run `docker run` from Windows PowerShell instead, the left side of `-v` must be a Windows path, for example:

```powershell
docker run -d --name water-station-pusher --restart unless-stopped -v C:\envoinx\fishfind\fishfind-backend\service\waterservice\.env:/run/secrets/waterservice.env:ro -e DOTENV_PATH=/run/secrets/waterservice.env registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.1
```

If you use a Linux path from Windows, Docker can create the mount target incorrectly and the application may fail with `java.io.IOException: Is a directory` while loading the dotenv file.

## 5. Recommended setup for this service

Use this unless you have a reason not to:

1. Push the image to `DigitalOcean Container Registry`.
2. Deploy it to `App Platform` as a `Worker`.
3. Set `DB_URL`, `DB_USERNAME`, and `DB_PASSWORD` as app environment variables.
4. Leave the Docker `ENTRYPOINT` in place.
5. Verify execution in `Runtime Logs`.

## References

- https://docs.digitalocean.com/products/container-registry/how-to/create-registry/
- https://docs.digitalocean.com/products/container-registry/
- https://docs.digitalocean.com/products/app-platform/how-to/deploy-from-container-images/
- https://docs.digitalocean.com/products/app-platform/getting-started/quickstart/
