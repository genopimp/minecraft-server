#!/bin/bash
# Unraid User Scripts: restart so the container re-fetches Mojang latest.release.
# Schedule: daily ~05:00 (before people are on).
# Docker tab name is "minecraft" when using the compose/XML in this repo.

docker restart minecraft
