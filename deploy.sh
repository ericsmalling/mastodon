#!/bin/bash
# a script to start mastodon via compose
# Minimal files needed to start this up:
# deploy.sh (this file)
# docker-compose.yml (or docker-compose.prod.yml)
# .env (with all the env vars needed to run mastodon)
# .env.secrets (will be generated if not present)

# fail on error
set -e

#################################################
# prep the db and create .env.secrets
#################################################

# login to our registries
# docker login ghcr.io -u "$GITHUB_ACTOR" -p "$GITHUB_TOKEN"

# lets check image access first
docker compose pull

# start postgres db first so we can seed it
docker compose up db -d --wait

# if .env.secrets does not exist, generate it
if [ ! -f .env.secrets ]; then
  echo ".env.secrets not found, generating..."

  # Generate secrets using bootstrap service
  echo "Generating SECRET_KEY_BASE..."
  SECRET_KEY_BASE=$(docker compose --profile bootstrap run --rm bootstrap bundle exec rails secret)
  echo "SECRET_KEY_BASE=$SECRET_KEY_BASE" > .env.secrets

  echo "Generating OTP_SECRET..."
  OTP_SECRET=$(docker compose --profile bootstrap run --rm bootstrap bundle exec rails secret)
  echo "OTP_SECRET=$OTP_SECRET" >> .env.secrets

  echo "Generating VAPID keys..."
  docker compose --profile bootstrap run --rm -e OTP_SECRET="$OTP_SECRET" -e SECRET_KEY_BASE="$SECRET_KEY_BASE" bootstrap bundle exec rake mastodon:webpush:generate_vapid_key | grep "^VAPID_" >> .env.secrets

  echo "Generating database encryption key..."
  docker compose --profile bootstrap run --rm bootstrap bundle exec rake db:encryption:init | grep "^ACTIVE_RECORD_ENCRYPTION" >> .env.secrets

  echo ".env.secrets generated successfully!"
fi

# seed the database
docker compose run --rm web bundle exec rails db:prepare


#################################################
# start all remaining services
#################################################
docker compose up -d

echo "Mastodon should be up and running on https://www.bret.lol"
# echo "Traefik Dashboard should be up and running on https://traefik.bret.lol"


