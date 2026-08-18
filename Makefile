# icinga2-incident-io

NAME        := icinga2-incident-io
VERSION     := $(shell cat VERSION)
DESTDIR     ?=
PREFIX      ?= /usr
ICINGA_CONF ?= /etc/icinga2

.PHONY: all test lint install uninstall deb rpm packages basket clean help

all: help

help:
	@echo "$(NAME) $(VERSION)"
	@echo
	@echo "  make test        run the test suite (sh, dash, bash)"
	@echo "  make lint        shellcheck the handler and test suite"
	@echo "  make install     install handler + config on this master"
	@echo "  make uninstall   remove them again"
	@echo "  make deb         build a .deb  (needs fpm)"
	@echo "  make rpm         build an .rpm (needs fpm)"
	@echo "  make packages    build both, in Docker (needs docker)"
	@echo "  make basket      generate an Icinga Director basket JSON"

test:
	SHELLS="sh dash bash" ./test/run-tests.sh

lint:
	shellcheck -s sh bin/incident-io-icinga test/run-tests.sh contrib/director-basket/generate-basket.sh

# Installs into the master zone so Icinga's config sync distributes the .conf
# files to the other masters. The handler itself must be installed on each
# master separately - zone sync moves .conf files only.
install:
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 bin/incident-io-icinga $(DESTDIR)$(PREFIX)/bin/incident-io-icinga
	install -d $(DESTDIR)$(ICINGA_CONF)/zones.d/master
	install -m 0644 conf.d/incident-io-command.conf       $(DESTDIR)$(ICINGA_CONF)/zones.d/master/
	install -m 0644 conf.d/incident-io-notifications.conf $(DESTDIR)$(ICINGA_CONF)/zones.d/master/
	install -d $(DESTDIR)$(ICINGA_CONF)/conf.d
	install -m 0640 conf.d/incident-io-secrets.conf.example $(DESTDIR)$(ICINGA_CONF)/conf.d/
	@echo
	@echo "Installed. Now, on each master:"
	@echo "  1. cp $(ICINGA_CONF)/conf.d/incident-io-secrets.conf.example \\"
	@echo "        $(ICINGA_CONF)/conf.d/incident-io-secrets.conf"
	@echo "  2. edit it with your alert source URL and token"
	@echo "  3. chown root:icinga $(ICINGA_CONF)/conf.d/incident-io-secrets.conf && chmod 0640 it"
	@echo "  4. icinga2 daemon -C && systemctl reload icinga2"

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/incident-io-icinga
	rm -f $(DESTDIR)$(ICINGA_CONF)/zones.d/master/incident-io-command.conf
	rm -f $(DESTDIR)$(ICINGA_CONF)/zones.d/master/incident-io-notifications.conf
	rm -f $(DESTDIR)$(ICINGA_CONF)/conf.d/incident-io-secrets.conf.example
	@echo "Left $(ICINGA_CONF)/conf.d/incident-io-secrets.conf in place - remove it by hand."

deb:
	./build-linux/make_package.sh deb

rpm:
	./build-linux/make_package.sh rpm

packages:
	./build-linux/build-in-docker.sh

basket:
	./contrib/director-basket/generate-basket.sh > dist/director-basket.json
	@echo "wrote dist/director-basket.json"

clean:
	rm -rf dist build
