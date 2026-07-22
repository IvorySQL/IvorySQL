PYTHON ?= python3
COMPOSE ?= docker compose
HARNESS := $(PYTHON) pool_harness.py

.PHONY: build config preflight up status audit load verify reload pause resume logs down clean test

build:
	$(COMPOSE) build

config:
	$(COMPOSE) config --quiet

preflight:
	$(HARNESS) preflight

up:
	$(COMPOSE) up --detach --build database pgbouncer

status:
	$(HARNESS) status

audit:
	$(HARNESS) audit

load:
	$(HARNESS) load --clients 200 --concurrency 100

verify:
	$(COMPOSE) --profile verify run --rm verifier

reload:
	$(COMPOSE) exec pgbouncer sh -c 'kill -HUP $$(cat /var/run/pgbouncer/pgbouncer.pid)'

pause:
	$(COMPOSE) exec pgbouncer sh -c 'PGPASSWORD="$$PGBOUNCER_ADMIN_PASSWORD" "$$PGBOUNCER_PSQL" -h 127.0.0.1 -p 6432 -U "$$PGBOUNCER_ADMIN_USER" -d pgbouncer -c "PAUSE"'

resume:
	$(COMPOSE) exec pgbouncer sh -c 'PGPASSWORD="$$PGBOUNCER_ADMIN_PASSWORD" "$$PGBOUNCER_PSQL" -h 127.0.0.1 -p 6432 -U "$$PGBOUNCER_ADMIN_USER" -d pgbouncer -c "RESUME"'

logs:
	$(COMPOSE) logs --follow --tail 100

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --volumes --remove-orphans

test:
	$(PYTHON) -m unittest discover -s tests -v
