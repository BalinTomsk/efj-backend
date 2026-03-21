# Update Deployed Image

Use this when you changed the code and need to publish a new Docker image, push it to DigitalOcean Container Registry, and replace the running container on the Droplet.

This runbook assumes:

- the registry name is `envfish`
- the repository path is `waterservice/water-station-pusher`
- the Droplet already has Docker installed
- the Droplet already has `/opt/waterservice/waterservice.env`

## 1. Choose a new version tag

Do not reuse the previous tag. Pick a new one, for example `1.0.2`.

Examples in this document use:

```text
1.0.2
```

## 2. Build the new image locally

From the project root:

```powershell
docker build -t water-station-pusher:1.0.2 .
```

Optional verification:

```powershell
docker images
```

## 3. Log in to DOCR locally

```powershell
doctl auth init
doctl registries login envfish
```

If you already authenticated `doctl`, only the registry login is usually needed.

## 4. Tag the image for DigitalOcean Container Registry

```powershell
docker tag water-station-pusher:1.0.2 registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
```

## 5. Push the new image

```powershell
docker push registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
```

Optional verification:

```powershell
doctl registries repository list-tags envfish waterservice/water-station-pusher
```

## 6. Connect to the Droplet

Use SSH to open a shell on the Droplet:

```bash
ssh root@your_droplet_ip
```

## 7. Log in to DOCR on the Droplet

If `doctl` is already installed and authenticated on the Droplet:

```bash
doctl registries login envfish
```

If `doctl` is installed but not authenticated:

```bash
doctl auth init -t "your_digitalocean_token"
doctl registries login envfish
```

## 8. Pull the new image on the Droplet

```bash
docker pull registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
```

## 9. Stop and remove the old container

```bash
docker rm -f water-station-pusher
```

## 10. Start the replacement container

This keeps the existing mounted dotenv file and restart policy:

```bash
docker run -d \
  --name water-station-pusher \
  --restart unless-stopped \
  -v /opt/waterservice/waterservice.env:/run/secrets/waterservice.env:ro \
  -e DOTENV_PATH=/run/secrets/waterservice.env \
  registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
```

## 11. Verify the new container

Check that Docker started the new image:

```bash
docker ps
docker logs --tail 100 water-station-pusher
```

If the service is healthy, follow logs live:

```bash
docker logs -f water-station-pusher
```

## 12. Optional cleanup

If you want to remove old local images from the Droplet after the new one is confirmed:

```bash
docker images
docker image prune -f
```

Be careful with broader image cleanup if the Droplet runs anything else.

## Quick command summary

Local machine:

```powershell
docker build -t water-station-pusher:1.0.2 .
doctl registries login envfish
docker tag water-station-pusher:1.0.2 registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
docker push registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
```

Droplet:

```bash
doctl registries login envfish
docker pull registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
docker rm -f water-station-pusher
docker run -d \
  --name water-station-pusher \
  --restart unless-stopped \
  -v /opt/waterservice/waterservice.env:/run/secrets/waterservice.env:ro \
  -e DOTENV_PATH=/run/secrets/waterservice.env \
  registry.digitalocean.com/envfish/waterservice/water-station-pusher:1.0.2
docker logs -f water-station-pusher
```
