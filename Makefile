.PHONY: all build up down remove

all: build

build:
	@docker compose build --progress=plain --pull

up:
	@docker compose up -d

down:
	@docker compose down --volumes

remove: down
	@rm -rf /data/apt-cacher-ng/var/cache/*
