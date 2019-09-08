PHP := /home/isucon/local/php/bin/php

.PHONY: deps
deps: composer.phar
	$(PHP) composer.phar install
composer.phar:
	curl -sf 'https://getcomposer.org/download/1.9.0/composer.phar' -o $@
