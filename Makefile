PROJECT = concourse-helm3
ID = YOUR_DOCKER_HOST_HERE/${PROJECT}
VERSION = $(shell cat VERSION)


all: build push

.PHONY: build push test-integration run

build:
	docker build --tag ${ID}:$(VERSION) .

push:
	docker push ${ID}:$(VERSION)

test-integration:
	test/integration/run.sh

run:
	docker run \
		--volume $(shell pwd):/opt/helm-3 \
		--workdir /opt/helm-3 \
		--interactive \
		--tty \
		${ID}:latest \
		bash
