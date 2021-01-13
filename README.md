# evalr-experiment

This is a skeleton project for running evalr experiments.

## Getting started guide

``` sh
$ git clone ssh://git@github.com/PRL-PRG/evalr-experiment
$ cd evalr-experiment
```
**Important: all of the following commands should be run inside the cloned repository!**

If the docker image has not yet been created, run

```sh
$ make -C docker-image
```

Get into docker

``` sh
$ make shell
```

Get the dependencies. The reason why we do not put them yet in the image is that
we might want to have some local changes to them.

```sh
docker% make libs-dependencies
```

Install libraries

``` sh
docker% make libs
```

Install packages

``` sh
docker% make install-packages
```

