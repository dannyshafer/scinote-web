APP_HOME="/usr/src/app"

all: docker database

heroku:
	@heroku buildpacks:remove https://github.com/ddollar/heroku-buildpack-multi.git
	@heroku buildpacks:set https://github.com/ddollar/heroku-buildpack-multi.git
	@echo "Set environment variables, DATABASE_URL, RAILS_SERVE_STATIC_FILES, RAKE_ENV, RAILS_ENV, SECRET_KEY_BASE, SKYLIGHT_AUTHENTICATION"

docker:
	@docker-compose build

db-cli:
	@$(MAKE) rails cmd="rails db"

database:
	@$(MAKE) rails cmd="rake db:create db:setup db:migrate"

rails:
	@docker-compose run web $(cmd)

run:
	@docker-compose up

start:
	@docker-compose start

stop:
	@docker-compose stop

cli:
	@$(MAKE) rails cmd="/bin/bash"

tests:
	@$(MAKE) rails cmd="rake test"

console:
	@$(MAKE) rails cmd="rails console"

log:
	@docker-compose web log

status:
	@docker-compose ps

export:
	@git checkout-index -a -f --prefix=scinote/
	@tar -zcvf scinote-$(shell git rev-parse --short HEAD).tar.gz scinote
	@rm -rf scinote

