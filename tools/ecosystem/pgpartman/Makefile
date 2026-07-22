PYTHON ?= python3
COMPOSE ?= docker compose
HARNESS := $(PYTHON) partition_harness.py

.PHONY: build config preflight plan up install workload maintenance inventory audit verify logs down clean test

build:
	$(COMPOSE) build

config:
	$(COMPOSE) config --quiet

preflight:
	$(HARNESS) preflight

plan:
	$(HARNESS) plan

up:
	$(COMPOSE) up --detach --build database

install:
	$(COMPOSE) exec database $(HARNESS) install

workload:
	$(COMPOSE) exec database $(HARNESS) workload --rows 100000

maintenance:
	$(COMPOSE) exec database $(HARNESS) maintenance

inventory:
	$(COMPOSE) exec database $(HARNESS) inventory

audit:
	$(COMPOSE) exec database $(HARNESS) audit

verify:
	$(COMPOSE) --profile verify run --rm verifier

logs:
	$(COMPOSE) logs --follow --tail 100

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --volumes --remove-orphans

test:
	$(PYTHON) -m unittest discover -s tests -v
