# saner makefile
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

.PHONY: all
all: image

include ../Makevars

.PHONY: image
image: $(DEPENDENCIES_TXT)
	docker build \
		--build-arg CRAN_MIRROR=$(CRAN_MIRROR) \
		--build-arg DEPENDENCIES_TXT=$(DEPENDENCIES_TXT) \
    --rm \
    -t $(DOCKER_IMAGE_NAME) \
    .

.PHONY: upload
upload: image
	docker push $(DOCKER_IMAGE_NAME)
