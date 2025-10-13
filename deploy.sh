#!/bin/bash
# a script to start mastodon via compose
# Minimal files needed to start this up:
# deploy.sh (this file)
# docker-compose.yml (or docker-compose.prod.yml)
# .env (with all the env vars needed to run mastodon)
# .env.secrets (will be generated if not present)

# fail on error
set -e

# Check if domain argument is provided
if [ -z "$1" ]; then
  echo "Error: DNS name is required"
  echo "Usage: $0 <domain-name>"
  echo "Example: $0 www.bret.lol"
  exit 1
fi

# Assign the first argument to LOCAL_DOMAIN
LOCAL_DOMAIN="$1"
echo "Using LOCAL_DOMAIN: $LOCAL_DOMAIN"

##################################################
# create .env file from sample and set values
##################################################
if [ ! -f .env ]; then
  cp .env.production.sample .env

  # Update LOCAL_DOMAIN to the provided domain
  sed -i.bak "s/^LOCAL_DOMAIN=.*/LOCAL_DOMAIN=$LOCAL_DOMAIN/" .env

  # Generate random 20 character password
  DB_PASSWORD=$(openssl rand -base64 20 | tr -d "=+/" | cut -c1-20)

  # Replace the value of DB_PASS with generated password
  sed -i.bak "s/^# DB_PASS=.*/DB_PASS=$DB_PASSWORD/" .env

  echo ".env file created and configured with LOCAL_DOMAIN=$LOCAL_DOMAIN and random DB password"
fi


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

echo "Mastodon should be up and running on https://$LOCAL_DOMAIN"

