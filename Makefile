# Bezgelor Development Makefile
# Run `make help` to see available commands

.PHONY: help setup deps db.setup db.start db.stop db.reset db.migrate test console clean

# Default target
help:
	@echo "Bezgelor Development Commands"
	@echo "=============================="
	@echo ""
	@echo "Setup:"
	@echo "  make setup      - Full project setup (deps + database)"
	@echo "  make deps       - Install Elixir dependencies"
	@echo ""
	@echo "Database:"
	@echo "  make db.start   - Start PostgreSQL container"
	@echo "  make db.stop    - Stop PostgreSQL container"
	@echo "  make db.setup   - Create and migrate database"
	@echo "  make db.reset   - Drop and recreate database"
	@echo "  make db.migrate - Run pending migrations"
	@echo "  make db.logs    - View PostgreSQL logs"
	@echo "  make db.shell   - Open psql shell"
	@echo ""
	@echo "Development:"
	@echo "  make test       - Run all tests"
	@echo "  make console    - Start IEx console"
	@echo "  make clean      - Clean build artifacts"

# Full setup
setup: deps db.start
	@echo "Waiting for PostgreSQL to be ready..."
	@sleep 3
	$(MAKE) db.setup
	@echo ""
	@echo "Setup complete! Run 'make test' to verify."

# Install dependencies
deps:
	mix deps.get

# Database commands
db.start:
	docker compose up -d postgres
	@echo "PostgreSQL starting on localhost:5432"

db.stop:
	docker compose down

db.setup:
	mix ecto.create
	mix ecto.migrate

db.reset:
	mix ecto.drop
	mix ecto.create
	mix ecto.migrate

db.migrate:
	mix ecto.migrate

db.logs:
	docker compose logs -f postgres

db.shell:
	docker compose exec postgres psql -U bezgelor -d bezgelor_dev

# Development commands
test:
	MIX_ENV=test mix test --no-start

test.db:
	MIX_ENV=test mix ecto.create --quiet
	MIX_ENV=test mix ecto.migrate --quiet
	MIX_ENV=test mix test

console:
	iex -S mix

# Cleanup
clean:
	mix clean
	rm -rf _build deps

# Docker cleanup (removes volumes too)
docker.clean:
	docker compose down -v
