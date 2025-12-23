#!/bin/bash
# Fly.io Initial Setup Script for Bezgelor
# Run this once to set up the app, database, and secrets

set -e

APP_NAME="bezgelor"
DB_NAME="bezgelor-db"
REGION="lax"
PHX_HOST="bezgelor.com"

echo "=== Bezgelor Fly.io Initial Setup ==="
echo ""

# Check flyctl is installed
if ! command -v fly &> /dev/null; then
    echo "Error: flyctl not installed. Install with: brew install flyctl"
    exit 1
fi

# Check authentication
echo "Checking Fly.io authentication..."
if ! fly auth whoami &> /dev/null; then
    echo "Not logged in. Running fly auth login..."
    fly auth login
fi
echo "Authenticated as: $(fly auth whoami)"
echo ""

# Step 1: Create the app
echo "=== Step 1: Creating app '$APP_NAME' ==="
if fly apps list | grep -q "^$APP_NAME "; then
    echo "App '$APP_NAME' already exists, skipping..."
else
    fly apps create "$APP_NAME" --org personal
    echo "App created."
fi
echo ""

# Step 2: Create Postgres database
echo "=== Step 2: Creating Postgres database '$DB_NAME' ==="
if fly apps list | grep -q "^$DB_NAME "; then
    echo "Database '$DB_NAME' already exists, skipping creation..."
else
    fly postgres create \
        --name "$DB_NAME" \
        --region "$REGION" \
        --initial-cluster-size 1 \
        --vm-size shared-cpu-1x \
        --volume-size 10
    echo "Database created."
fi

# Attach database (sets DATABASE_URL automatically)
echo "Attaching database to app..."
fly postgres attach "$DB_NAME" --app "$APP_NAME" 2>/dev/null || echo "Database may already be attached."
echo ""

# Step 3: Allocate IPv4 address
echo "=== Step 3: Allocating public IPv4 address ==="
if fly ips list --app "$APP_NAME" | grep -q "v4"; then
    echo "IPv4 already allocated:"
else
    fly ips allocate-v4 --app "$APP_NAME"
    echo "IPv4 allocated:"
fi
FLY_IP=$(fly ips list --app "$APP_NAME" | grep v4 | awk '{print $2}')
echo "  IP: $FLY_IP"
echo ""

# Step 4: Generate and set secrets
echo "=== Step 4: Setting secrets ==="

# Check if secrets already exist
EXISTING_SECRETS=$(fly secrets list --app "$APP_NAME" 2>/dev/null || echo "")

if echo "$EXISTING_SECRETS" | grep -q "SECRET_KEY_BASE"; then
    echo "Secrets already configured. To reset, run:"
    echo "  fly secrets unset SECRET_KEY_BASE CLOAK_KEY --app $APP_NAME"
    echo ""
else
    echo "Generating secrets..."
    SECRET_KEY_BASE=$(mix phx.gen.secret)
    CLOAK_KEY=$(elixir -e ':crypto.strong_rand_bytes(32) |> Base.encode64() |> IO.puts()' | tr -d '\n')

    echo "Setting secrets..."
    fly secrets set \
        SECRET_KEY_BASE="$SECRET_KEY_BASE" \
        CLOAK_KEY="$CLOAK_KEY" \
        WORLD_PUBLIC_ADDRESS="$FLY_IP" \
        PHX_HOST="$PHX_HOST" \
        --app "$APP_NAME"

    echo "Secrets configured."
fi
echo ""

# Step 5: Show summary
echo "=== Setup Complete ==="
echo ""
echo "App:      $APP_NAME"
echo "Database: $DB_NAME"
echo "Region:   $REGION"
echo "IPv4:     $FLY_IP"
echo "Host:     $PHX_HOST"
echo ""
echo "Configured secrets:"
fly secrets list --app "$APP_NAME"
echo ""
echo "Next steps:"
echo "  1. (Optional) Set email secrets:"
echo "     fly secrets set RESEND_API_KEY=\"re_xxx\" MAIL_FROM=\"noreply@bezgelor.com\" --app $APP_NAME"
echo ""
echo "  2. Deploy the application:"
echo "     ./scripts/fly/deploy.sh"
echo ""
echo "  3. Configure DNS for bezgelor.com to point to: $FLY_IP"
echo ""
