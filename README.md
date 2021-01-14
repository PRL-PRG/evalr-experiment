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

Install packages from `packages.txt`. This has to be done every time, this file
changes.

``` sh
docker% make install-packages
```

## The pipeline

### Tracing CRAN packages

To trace packages, run:

``` sh
docker% make package-trace-eval
```

The result should be always in in `run/package-trace-eval`. Older runs will be
renamed to `run/package-trace-eval.<X>`.

To preprocess the data, run:

``` sh
docker% make package-preprocess
```

The result should be always in in `run/preprocess/package`. Older runs will be
renamed to `run/preprocess/package.<X>`. The preprocess will always use the
latest data from the `package-trace-eval` task. It will not trigger a new
tracing.

### Tracing core packages

### Tracing Kaggle

## Debugging when something is wrong
