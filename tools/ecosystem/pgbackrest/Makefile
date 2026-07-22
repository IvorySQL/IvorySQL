PYTHON ?= python3
COMPOSE ?= docker compose
HARNESS := $(PYTHON) backup_harness.py

.PHONY: build config preflight up stanza check full diff incr info audit verify restore-verify logs down clean test

build:
	$(COMPOSE) build

config:
	$(COMPOSE) config --quiet

preflight:
	$(HARNESS) preflight

up:
	$(COMPOSE) up --detach --build database

stanza:
	$(COMPOSE) exec database $(HARNESS) stanza-create

check:
	$(COMPOSE) exec database $(HARNESS) check

full:
	$(COMPOSE) exec database $(HARNESS) backup --type full --expire

diff:
	$(COMPOSE) exec database $(HARNESS) backup --type diff --expire

incr:
	$(COMPOSE) exec database $(HARNESS) backup --type incr --expire

info:
	$(COMPOSE) exec database $(HARNESS) info

audit:
	$(COMPOSE) exec database $(HARNESS) audit

verify:
	$(COMPOSE) exec --user ivorysql database /usr/local/bin/verify-backup

restore-verify:
	$(COMPOSE) --profile restore run --rm restore-verifier

logs:
	$(COMPOSE) logs --follow --tail 100

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down --volumes --remove-orphans

test:
	$(PYTHON) -m unittest discover -s tests -v
