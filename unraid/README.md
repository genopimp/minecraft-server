# Unraid Docker template

The file that drives the Unraid **Add Container** form is
[`minecraft-server.xml`](../minecraft-server.xml) at the repo root (copied here as
`minecraft-server.xml`).

## Install into the Unraid UI

On Unraid:

```bash
wget -O /boot/config/plugins/dockerMan/templates-user/my-minecraft-server.xml \
  https://raw.githubusercontent.com/genopimp/minecraft-server/main/minecraft-server.xml
```

Docker → Add Container → Template → **minecraft-server**.

After that, every setting (world folder, allow list, difficulty, ports) is on
that form. Changing a field and clicking Apply recreates the container with the
new env/paths; world data stays on the appdata path.

If you already created this container with Compose Manager, remove that stack
first so you do not run two servers on the same `appdata` folder.

## Admin console

Docker → container → **Console**, then type `mc-console` for the live
Bedrock operator console (logs + commands). Detach with Ctrl-b then d.
One-shot: `mc-cmd say hello`.
