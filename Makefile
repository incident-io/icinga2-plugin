# icinga2-incident-io

NAME        := icinga2-incident-io
VERSION     := $(shell cat VERSION)
DESTDIR     ?=
PREFIX      ?= /usr
ICINGA_CONF ?= /etc/icinga2

.PHONY: all test test-posix lint lint-docker install uninstall deb rpm basket clean help

all: help

help:
	@echo "$(NAME) $(VERSION)"
	@echo
	@echo "  make test        run the test suite (sh, dash, bash)"
	@echo "  make test-posix  same, with GNU sed forced into POSIX mode"
	@echo "  make lint        shellcheck the handler and test suite"
	@echo "  make lint-docker same, in a container (no local shellcheck)"
	@echo "  make install     install handler + config on this master"
	@echo "  make uninstall   remove them again"
	@echo "  make deb         build a .deb  (needs fpm)"
	@echo "  make rpm         build an .rpm (needs fpm)"
	@echo "  make basket      generate an Icinga Director basket JSON"

test:
	SHELLS="sh dash bash" sh ./test/run-tests.sh

# Approximates BSD/macOS userland on a GNU box. Only meaningful where sed is
# GNU sed; on macOS `make test` already exercises the real thing.
test-posix:
	@sed --version >/dev/null 2>&1 || { echo "not GNU sed; plain 'make test' already covers this"; exit 0; }
	PATH="$(CURDIR)/test/shims:$$PATH" SHELLS="sh dash bash" sh ./test/run-tests.sh

SHELL_SOURCES := bin/incident-io-icinga test/run-tests.sh \
                 contrib/director-basket/generate-basket.sh \
                 build-linux/make_package.sh

lint:
	shellcheck -s sh $(SHELL_SOURCES)

lint-docker:
	docker run --rm -v "$(CURDIR):/mnt" -w /mnt koalaman/shellcheck:stable \
	  -s sh $(SHELL_SOURCES)

# Installs into conf.d on this master. Deliberately not zones.d: constants
# defined in conf.d are not visible to config synced from zones.d, and the
# handler has to be installed per-master regardless, so zone sync buys nothing.
install:
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 bin/incident-io-icinga $(DESTDIR)$(PREFIX)/bin/incident-io-icinga
	install -d $(DESTDIR)$(ICINGA_CONF)/conf.d
	install -m 0644 conf.d/incident-io-command.conf       $(DESTDIR)$(ICINGA_CONF)/conf.d/
	install -m 0644 conf.d/incident-io-notifications.conf $(DESTDIR)$(ICINGA_CONF)/conf.d/
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
	rm -f $(DESTDIR)$(ICINGA_CONF)/conf.d/incident-io-command.conf
	rm -f $(DESTDIR)$(ICINGA_CONF)/conf.d/incident-io-notifications.conf
	rm -f $(DESTDIR)$(ICINGA_CONF)/conf.d/incident-io-secrets.conf.example
	@echo "Left $(ICINGA_CONF)/conf.d/incident-io-secrets.conf in place - remove it by hand."

deb:
	sh ./build-linux/make_package.sh deb

rpm:
	sh ./build-linux/make_package.sh rpm

basket:
	@mkdir -p dist
	sh ./contrib/director-basket/generate-basket.sh > dist/director-basket.json
	@echo "wrote dist/director-basket.json"

clean:
	rm -rf dist build
