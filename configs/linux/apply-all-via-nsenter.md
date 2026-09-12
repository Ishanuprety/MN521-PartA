# Apply docker host networking via nsenter / docker exec

On the GNS3 VM (or Mac docker for local images):

```bash
# Example: find container and run setup
CID=$(docker ps -q --filter name=DNS)
docker cp configs/linux/dns-setup.sh $CID:/tmp/setup.sh
docker exec -u root $CID bash /tmp/setup.sh
```

Or with PID nsenter if using GNS3 docker nodes:

```bash
PID=$(docker inspect -f '{{.State.Pid}}' <container>)
sudo nsenter -t $PID -n -m -u -i -p bash /path/to/dns-setup.sh
```

Order: DNS → NTP → Syslog → FILE/MON → WEB/APP → JUMP/AUTO.
