all: build

build:
	@docker compose build --progress=plain --pull

up:
	@docker compose up -d

down:
	@docker compose down --volumes
