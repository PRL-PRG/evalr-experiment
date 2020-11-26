IMAGE_NAME := prlprg/project-evalr
.PHONY: image upload

all: image

image:
	docker build \
    --rm \
    -t $(IMAGE_NAME) \
    .

upload: image
	docker push $(IMAGE_NAME)
