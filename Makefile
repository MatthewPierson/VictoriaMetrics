PKG_PREFIX := github.com/VictoriaMetrics/VictoriaMetrics

MAKE_CONCURRENCY ?= $(shell getconf _NPROCESSORS_ONLN)
MAKE_PARALLEL := $(MAKE) -j $(MAKE_CONCURRENCY)
DATEINFO_TAG ?= $(shell date -u +'%Y%m%d-%H%M%S')
BUILDINFO_TAG ?= $(shell echo $$(git describe --long --all | tr '/' '-')$$( \
	      git diff-index --quiet HEAD -- || echo '-dirty-'$$(git diff-index -u HEAD | openssl sha1 | cut -d' ' -f2 | cut -c 1-8)))
LATEST_TAG ?= latest

PKG_TAG ?= $(shell git tag -l --points-at HEAD)
ifeq ($(PKG_TAG),)
PKG_TAG := $(BUILDINFO_TAG)
endif

GO_BUILDINFO = -X '$(PKG_PREFIX)/lib/buildinfo.Version=$(APP_NAME)-$(DATEINFO_TAG)-$(BUILDINFO_TAG)'

VICTORIA_LOGS_COMPONENTS = victoria-logs
VICTORIA_METRICS_COMPONENTS = victoria-metrics
VICTORIA_METRICS_UTILS_COMPONENTS = vmagent vmalert vmalert-tool vmauth vmbackup vmrestore vmctl

.PHONY: $(MAKECMDGOALS)

include app/*/Makefile
include cspell/Makefile
include docs/Makefile
include deployment/*/Makefile
include dashboards/Makefile
include package/release/Makefile

define RELEASE_GOOS_GOARCH
	$(eval PKG_NAME := $(1))
	$(eval PKG_COMPONENTS := $(2))

	# Build
	$(foreach pkg_component, $(PKG_COMPONENTS), $(MAKE) $(pkg_component)-$(GOOS)-$(GOARCH)-prod)

	# Generate SBOM
	mkdir -p "bin/$(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom"
	$(foreach pkg_component, $(PKG_COMPONENTS),
		cyclonedx-gomod app -assert-licenses -json -licenses -packages \
			-main app/$(pkg_component) \
			-output bin/$(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom/$(pkg_component)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom.json)
	
	# Pack and compress
	$(foreach pkg_component, $(PKG_COMPONENTS),
		cd bin && tar --transform="flags=r;s|-$(GOOS)-$(GOARCH)||" -rf $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG).tar \
			$(pkg_component)-$(GOOS)-$(GOARCH)-prod)
	cd bin && gzip $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG).tar
	cd bin && tar -czf $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom.tar.gz $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom

	# Generate checksums
	cd bin && \
		sha256sum $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG).tar.gz > $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_checksums.txt && \
		sha256sum $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom.tar.gz >> $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_checksums.txt
	$(foreach pkg_component, $(PKG_COMPONENTS),
		cd bin && sha256sum $(pkg_component)-$(GOOS)-$(GOARCH)-prod | sed s/-$(GOOS)-$(GOARCH)-prod/-prod/ >> \
			$(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_checksums.txt)

	# Clean up
	cd bin && rm -rf $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom
	$(foreach pkg_component, $(PKG_COMPONENTS), cd bin && rm -f $(pkg_component)-$(GOOS)-$(GOARCH)-prod)
endef

define RELEASE_WINDOWS_GOARCH
	$(eval PKG_NAME := $(1))
	$(eval PKG_COMPONENTS := $(2))

	# Build
	$(foreach pkg_component, $(PKG_COMPONENTS), $(MAKE) $(pkg_component)-$(GOOS)-$(GOARCH)-prod)

	# Generate SBOM
	mkdir -p "bin/$(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom"
	$(foreach pkg_component, $(PKG_COMPONENTS),
		cyclonedx-gomod app -assert-licenses -json -licenses -packages \
			-main app/$(pkg_component) \
			-output bin/$(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom/$(pkg_component)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom.json)
	
	# Pack and compress
	$(foreach pkg_component, $(PKG_COMPONENTS),
		cd bin && zip -u $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG).zip \
			$(pkg_component)-$(GOOS)-$(GOARCH)-prod.exe)
	cd bin && zip $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom.zip -r $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom

	# Generate checksums
	cd bin && \
		sha256sum $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG).zip > $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_checksums.txt && \
		sha256sum $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom.zip >> $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_checksums.txt
	$(foreach pkg_component, $(PKG_COMPONENTS),
		cd bin && sha256sum $(pkg_component)-$(GOOS)-$(GOARCH)-prod.exe >> $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_checksums.txt)

	# Clean up
	cd bin && rm -rf $(PKG_NAME)-$(GOOS)-$(GOARCH)-$(PKG_TAG)_bom
	$(foreach pkg_component, $(PKG_COMPONENTS), cd bin && rm -f $(pkg_component)-$(GOOS)-$(GOARCH)-prod.exe)
endef


all: \
	victoria-metrics-prod \
	victoria-logs-prod \
	vmagent-prod \
	vmalert-prod \
	vmalert-tool-prod \
	vmauth-prod \
	vmbackup-prod \
	vmrestore-prod \
	vmctl-prod

clean:
	rm -rf bin/*

publish: \
	publish-victoria-metrics \
	publish-vmagent \
	publish-vmalert \
	publish-vmalert-tool \
	publish-vmauth \
	publish-vmbackup \
	publish-vmrestore \
	publish-vmctl

package: \
	package-victoria-metrics \
	package-victoria-logs \
	package-vmagent \
	package-vmalert \
	package-vmalert-tool \
	package-vmauth \
	package-vmbackup \
	package-vmrestore \
	package-vmctl

vmutils: \
	vmagent \
	vmalert \
	vmalert-tool \
	vmauth \
	vmbackup \
	vmrestore \
	vmctl

vmutils-pure: \
	vmagent-pure \
	vmalert-pure \
	vmalert-tool-pure \
	vmauth-pure \
	vmbackup-pure \
	vmrestore-pure \
	vmctl-pure

vmutils-linux-amd64: \
	vmagent-linux-amd64 \
	vmalert-linux-amd64 \
	vmalert-tool-linux-amd64 \
	vmauth-linux-amd64 \
	vmbackup-linux-amd64 \
	vmrestore-linux-amd64 \
	vmctl-linux-amd64

vmutils-linux-arm64: \
	vmagent-linux-arm64 \
	vmalert-linux-arm64 \
	vmalert-tool-linux-arm64 \
	vmauth-linux-arm64 \
	vmbackup-linux-arm64 \
	vmrestore-linux-arm64 \
	vmctl-linux-arm64

vmutils-linux-arm: \
	vmagent-linux-arm \
	vmalert-linux-arm \
	vmalert-tool-linux-arm \
	vmauth-linux-arm \
	vmbackup-linux-arm \
	vmrestore-linux-arm \
	vmctl-linux-arm

vmutils-linux-386: \
	vmagent-linux-386 \
	vmalert-linux-386 \
	vmalert-tool-linux-386 \
	vmauth-linux-386 \
	vmbackup-linux-386 \
	vmrestore-linux-386 \
	vmctl-linux-386

vmutils-linux-ppc64le: \
	vmagent-linux-ppc64le \
	vmalert-linux-ppc64le \
	vmalert-tool-linux-ppc64le \
	vmauth-linux-ppc64le \
	vmbackup-linux-ppc64le \
	vmrestore-linux-ppc64le \
	vmctl-linux-ppc64le

vmutils-darwin-amd64: \
	vmagent-darwin-amd64 \
	vmalert-darwin-amd64 \
	vmalert-tool-darwin-amd64 \
	vmauth-darwin-amd64 \
	vmbackup-darwin-amd64 \
	vmrestore-darwin-amd64 \
	vmctl-darwin-amd64

vmutils-darwin-arm64: \
	vmagent-darwin-arm64 \
	vmalert-darwin-arm64 \
	vmalert-tool-darwin-arm64 \
	vmauth-darwin-arm64 \
	vmbackup-darwin-arm64 \
	vmrestore-darwin-arm64 \
	vmctl-darwin-arm64

vmutils-freebsd-amd64: \
	vmagent-freebsd-amd64 \
	vmalert-freebsd-amd64 \
	vmalert-tool-freebsd-amd64 \
	vmauth-freebsd-amd64 \
	vmbackup-freebsd-amd64 \
	vmrestore-freebsd-amd64 \
	vmctl-freebsd-amd64

vmutils-openbsd-amd64: \
	vmagent-openbsd-amd64 \
	vmalert-openbsd-amd64 \
	vmalert-tool-openbsd-amd64 \
	vmauth-openbsd-amd64 \
	vmbackup-openbsd-amd64 \
	vmrestore-openbsd-amd64 \
	vmctl-openbsd-amd64

vmutils-windows-amd64: \
	vmagent-windows-amd64 \
	vmalert-windows-amd64 \
	vmalert-tool-windows-amd64 \
	vmauth-windows-amd64 \
	vmbackup-windows-amd64 \
	vmrestore-windows-amd64 \
	vmctl-windows-amd64

crossbuild:
	$(MAKE_PARALLEL) victoria-metrics-crossbuild vmutils-crossbuild

victoria-metrics-crossbuild: \
	victoria-metrics-linux-386 \
	victoria-metrics-linux-amd64 \
	victoria-metrics-linux-arm64 \
	victoria-metrics-linux-arm \
	victoria-metrics-linux-ppc64le \
	victoria-metrics-darwin-amd64 \
	victoria-metrics-darwin-arm64 \
	victoria-metrics-freebsd-amd64 \
	victoria-metrics-openbsd-amd64 \
	victoria-metrics-windows-amd64

vmutils-crossbuild: \
	vmutils-linux-386 \
	vmutils-linux-amd64 \
	vmutils-linux-arm64 \
	vmutils-linux-arm \
	vmutils-linux-ppc64le \
	vmutils-darwin-amd64 \
	vmutils-darwin-arm64 \
	vmutils-freebsd-amd64 \
	vmutils-openbsd-amd64 \
	vmutils-windows-amd64

publish-release:
	rm -rf bin/*
	git checkout $(TAG) && $(MAKE) release && LATEST_TAG=stable $(MAKE) publish && \
		git checkout $(TAG)-cluster && $(MAKE) release && LATEST_TAG=cluster-stable $(MAKE) publish && \
		git checkout $(TAG)-enterprise && $(MAKE) release && LATEST_TAG=enterprise-stable $(MAKE) publish && \
		git checkout $(TAG)-enterprise-cluster && $(MAKE) release && LATEST_TAG=enterprise-cluster-stable $(MAKE) publish

release:
	$(MAKE_PARALLEL) \
		release-victoria-metrics \
		release-vmutils

release-victoria-metrics: \
	release-victoria-metrics-linux-386 \
	release-victoria-metrics-linux-amd64 \
	release-victoria-metrics-linux-arm \
	release-victoria-metrics-linux-arm64 \
	release-victoria-metrics-darwin-amd64 \
	release-victoria-metrics-darwin-arm64 \
	release-victoria-metrics-freebsd-amd64 \
	release-victoria-metrics-openbsd-amd64 \
	release-victoria-metrics-windows-amd64

release-victoria-metrics-linux-386:
	GOOS=linux GOARCH=386 $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-linux-amd64:
	GOOS=linux GOARCH=amd64 $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-linux-arm:
	GOOS=linux GOARCH=arm $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-linux-arm64:
	GOOS=linux GOARCH=arm64 $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-darwin-amd64:
	GOOS=darwin GOARCH=amd64 $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-darwin-arm64:
	GOOS=darwin GOARCH=arm64 $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-freebsd-amd64:
	GOOS=freebsd GOARCH=amd64 $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-openbsd-amd64:
	GOOS=openbsd GOARCH=amd64 $(MAKE) release-victoria-metrics-goos-goarch

release-victoria-metrics-windows-amd64:
	GOOS=windows GOARCH=amd64 $(MAKE) release-victoria-metrics-windows-goarch

release-victoria-metrics-goos-goarch:
	$(call RELEASE_GOOS_GOARCH,victoria-metrics,$(VICTORIA_METRICS_COMPONENTS))

release-victoria-metrics-windows-goarch:
	$(call RELEASE_WINDOWS_GOARCH,victoria-metrics,$(VICTORIA_METRICS_COMPONENTS))

release-victoria-logs:
	$(MAKE_PARALLEL) release-victoria-logs-linux-386 \
		release-victoria-logs-linux-amd64 \
		release-victoria-logs-linux-arm \
		release-victoria-logs-linux-arm64 \
		release-victoria-logs-darwin-amd64 \
		release-victoria-logs-darwin-arm64 \
		release-victoria-logs-freebsd-amd64 \
		release-victoria-logs-openbsd-amd64 \
		release-victoria-logs-windows-amd64

release-victoria-logs-linux-386:
	GOOS=linux GOARCH=386 $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-linux-amd64:
	GOOS=linux GOARCH=amd64 $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-linux-arm:
	GOOS=linux GOARCH=arm $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-linux-arm64:
	GOOS=linux GOARCH=arm64 $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-darwin-amd64:
	GOOS=darwin GOARCH=amd64 $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-darwin-arm64:
	GOOS=darwin GOARCH=arm64 $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-freebsd-amd64:
	GOOS=freebsd GOARCH=amd64 $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-openbsd-amd64:
	GOOS=openbsd GOARCH=amd64 $(MAKE) release-victoria-logs-goos-goarch

release-victoria-logs-windows-amd64:
	GOARCH=amd64 $(MAKE) release-victoria-logs-windows-goarch

release-victoria-logs-goos-goarch: victoria-logs-$(GOOS)-$(GOARCH)-prod
	cd bin && \
		tar --transform="flags=r;s|-$(GOOS)-$(GOARCH)||" -czf victoria-logs-$(GOOS)-$(GOARCH)-$(PKG_TAG).tar.gz \
			victoria-logs-$(GOOS)-$(GOARCH)-prod \
		&& sha256sum victoria-logs-$(GOOS)-$(GOARCH)-$(PKG_TAG).tar.gz \
			victoria-logs-$(GOOS)-$(GOARCH)-prod \
			| sed s/-$(GOOS)-$(GOARCH)-prod/-prod/ > victoria-logs-$(GOOS)-$(GOARCH)-$(PKG_TAG)_checksums.txt
	cd bin && rm -rf victoria-logs-$(GOOS)-$(GOARCH)-prod

release-victoria-logs-windows-goarch: victoria-logs-windows-$(GOARCH)-prod
	cd bin && \
		zip victoria-logs-windows-$(GOARCH)-$(PKG_TAG).zip \
			victoria-logs-windows-$(GOARCH)-prod.exe \
		&& sha256sum victoria-logs-windows-$(GOARCH)-$(PKG_TAG).zip \
			victoria-logs-windows-$(GOARCH)-prod.exe \
			> victoria-logs-windows-$(GOARCH)-$(PKG_TAG)_checksums.txt
	cd bin && rm -rf \
		victoria-logs-windows-$(GOARCH)-prod.exe

release-vmutils: \
	release-vmutils-linux-386 \
	release-vmutils-linux-amd64 \
	release-vmutils-linux-arm64 \
	release-vmutils-linux-arm \
	release-vmutils-darwin-amd64 \
	release-vmutils-darwin-arm64 \
	release-vmutils-freebsd-amd64 \
	release-vmutils-openbsd-amd64 \
	release-vmutils-windows-amd64

release-vmutils-linux-386:
	GOOS=linux GOARCH=386 $(MAKE) release-vmutils-goos-goarch
	
release-vmutils-linux-amd64:
	GOOS=linux GOARCH=amd64 $(MAKE) release-vmutils-goos-goarch

release-vmutils-linux-arm64:
	GOOS=linux GOARCH=arm64 $(MAKE) release-vmutils-goos-goarch

release-vmutils-linux-arm:
	GOOS=linux GOARCH=arm $(MAKE) release-vmutils-goos-goarch

release-vmutils-darwin-amd64:
	GOOS=darwin GOARCH=amd64 $(MAKE) release-vmutils-goos-goarch

release-vmutils-darwin-arm64:
	GOOS=darwin GOARCH=arm64 $(MAKE) release-vmutils-goos-goarch

release-vmutils-freebsd-amd64:
	GOOS=freebsd GOARCH=amd64 $(MAKE) release-vmutils-goos-goarch

release-vmutils-openbsd-amd64:
	GOOS=openbsd GOARCH=amd64 $(MAKE) release-vmutils-goos-goarch

release-vmutils-windows-amd64:
	GOOS=windows GOARCH=amd64 $(MAKE) release-vmutils-windows-goarch

release-vmutils-goos-goarch:
	$(call RELEASE_GOOS_GOARCH, vmutils, $(VICTORIA_METRICS_UTILS_COMPONENTS))

release-vmutils-windows-goarch:
	$(call RELEASE_WINDOWS_GOARCH, vmutils, $(VICTORIA_METRICS_UTILS_COMPONENTS))

pprof-cpu:
	go tool pprof -trim_path=github.com/VictoriaMetrics/VictoriaMetrics@ $(PPROF_FILE)

fmt:
	gofmt -l -w -s ./lib
	gofmt -l -w -s ./app

vet:
	go vet ./lib/...
	go vet ./app/...

check-all: fmt vet golangci-lint govulncheck

clean-checkers: remove-golangci-lint remove-govulncheck

test:
	go test ./lib/... ./app/...

test-race:
	go test -race ./lib/... ./app/...

test-pure:
	CGO_ENABLED=0 go test ./lib/... ./app/...

test-full:
	go test -coverprofile=coverage.txt -covermode=atomic ./lib/... ./app/...

test-full-386:
	GOARCH=386 go test -coverprofile=coverage.txt -covermode=atomic ./lib/... ./app/...

benchmark:
	go test -bench=. ./lib/...
	go test -bench=. ./app/...

benchmark-pure:
	CGO_ENABLED=0 go test -bench=. ./lib/...
	CGO_ENABLED=0 go test -bench=. ./app/...

vendor-update:
	go get -u -d ./lib/...
	go get -u -d ./app/...
	go mod tidy -compat=1.22
	go mod vendor

app-local:
	CGO_ENABLED=1 go build $(RACE) -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)$(RACE) $(PKG_PREFIX)/app/$(APP_NAME)

app-local-pure:
	CGO_ENABLED=0 go build $(RACE) -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)-pure$(RACE) $(PKG_PREFIX)/app/$(APP_NAME)

app-local-goos-goarch:
	CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) go build $(RACE) -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)-$(GOOS)-$(GOARCH)$(RACE) $(PKG_PREFIX)/app/$(APP_NAME)

app-local-windows-goarch:
	CGO_ENABLED=0 GOOS=windows GOARCH=$(GOARCH) go build $(RACE) -ldflags "$(GO_BUILDINFO)" -o bin/$(APP_NAME)-windows-$(GOARCH)$(RACE).exe $(PKG_PREFIX)/app/$(APP_NAME)

quicktemplate-gen: install-qtc
	qtc

install-qtc:
	which qtc || go install github.com/valyala/quicktemplate/qtc@latest


golangci-lint: install-golangci-lint
	golangci-lint run

install-golangci-lint:
	which golangci-lint || curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell go env GOPATH)/bin v1.59.1

remove-golangci-lint:
	rm -rf `which golangci-lint`

govulncheck: install-govulncheck
	govulncheck ./...

install-govulncheck:
	which govulncheck || go install golang.org/x/vuln/cmd/govulncheck@latest

remove-govulncheck:
	rm -rf `which govulncheck`

install-wwhrd:
	which wwhrd || go install github.com/frapposelli/wwhrd@latest

check-licenses: install-wwhrd
	wwhrd check -f .wwhrd.yml

cyclonedx-gomod-install:
	which cyclonedx-gomod || go install github.com/CycloneDX/cyclonedx-gomod/cmd/cyclonedx-gomod@latest

copy-docs:
# The 'printf' function is used instead of 'echo' or 'echo -e' to handle line breaks (e.g. '\n') in the same way on different operating systems (MacOS/Ubuntu Linux/Arch Linux) and their shells (bash/sh/zsh/fish).
# For details, see https://github.com/VictoriaMetrics/VictoriaMetrics/pull/4548#issue-1782796419 and https://stackoverflow.com/questions/8467424/echo-newline-in-bash-prints-literal-n
	echo "---" > ${DST}
	@if [ ${ORDER} -ne 0 ]; then \
		echo "sort: ${ORDER}" >> ${DST}; \
		echo "weight: ${ORDER}" >> ${DST}; \
		printf "menu:\n  docs:\n    parent: 'victoriametrics'\n    weight: ${ORDER}\n" >> ${DST}; \
	fi

	echo "title: ${TITLE}" >> ${DST}
	@if [ ${OLD_URL} ]; then \
		printf "aliases:\n  - ${OLD_URL}\n" >> ${DST}; \
	fi
	echo "---" >> ${DST}
	cat ${SRC} >> ${DST}
	sed -i='.tmp' 's/<img src=\"docs\//<img src=\"/' ${DST}
	sed -i='.tmp' 's/<source srcset=\"docs\//<source srcset=\"/' ${DST}
	rm -rf docs/*.tmp

# Copies docs for all components and adds the order/weight tag, title, menu position and alias with the backward compatible link for the old site.
# For ORDER=0 it adds no order tag/weight tag.
# FOR OLD_URL - relative link, used for backward compatibility with the link from documentation based on GitHub pages (old one)
# FOR OLD_URL='' it adds no alias, it should be empty for every new page, don't change it for already existing links.
# Images starting with <img src="docs/ are replaced with <img src="
# Cluster docs are supposed to be ordered as 2nd.
# The rest of docs is ordered manually.
docs-sync:
	SRC=README.md DST=docs/README.md OLD_URL='' ORDER=0 TITLE=VictoriaMetrics $(MAKE) copy-docs
	SRC=README.md DST=docs/Single-server-VictoriaMetrics.md OLD_URL='/Single-server-VictoriaMetrics.html' TITLE=VictoriaMetrics ORDER=1 $(MAKE) copy-docs
