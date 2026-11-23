COMPOSE ?= docker compose

.PHONY: up down logs restart config reload

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

restart:
	$(COMPOSE) restart web

config:
	$(COMPOSE) config -q

reload:
	$(COMPOSE) exec web nginx -s reload
