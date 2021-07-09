# Introduction

This is the artifact for the paper *Why We Eval in the Shadows* by Aviral Goel,
Pierre Donat-Bouillud, Filip Krikava, Christoph Kirsch and Jan Vitek submitted
to OOPSLA 2021.

## Prerequisites

The artifact is packed in a docker image with a makefile that orchestrates
various tasks. The following are the requirements for getting the image ready
(the versions are just indicative - these are the ones that we worked with):

- GNU bash (5.0.17)
- Docker (20.10.2)
- git (2.24.1)
- GNU Make (4.2.1)

These instructions were tested on a fresh minimal installation of Ubuntu 20.04
LTS and on OSX (*TODO: version*).

For the fresh Ubuntu installation we installed the requirements using the following:

```sh
sudo apt install git make docker.io
sudo usermod -a -G docker <username>
```

## Organization

This document consists of two major sections:

1. *Getting started guide* which will guide you through the process of setting
   the environment and making sure the artifact is functional, and
2. *Detailed instructions* which will guide you through the process of
   reproducing the data presented in the paper.

## Not in the artifact

TODO: kaggle

## Getting started guide

In this section we will go through the steps of getting the artifact up and running.
Before you begin, make sure you have a functional docker on your system by running:

```sh
docker run --rm hello-world
```

It should eventually print `Hello from Docker!`. If it does not, your docker
environment is not properly configured and the following instructions will not
work.

A common problem with a newly installed docker are missing permissions. If you
got the following error:

```
Got permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: Get http://%2Fvar%2Frun%2Fdocker.sock/v1.24/containers/json: dial unix /var/run/docker.sock: connect: permission denied
```

Simply add your username into the `docker` group (e.g. `sudo usermod -a -G docker <username>`)


### 1. Get a copy of the repository

``` sh
git clone -b oopsla21 ssh://git@github.com/PRL-PRG/evalr-experiment
cd evalr-experiment
```

**Important: please make sure you use the `oopsla21` branch**

**Important: from now on, all of the commands should be run inside the cloned
repository!**

The artifact repository should look like this

```sh
.
├── docker-image        # docker image source code
├── Makefile            # data analysis pipeline
├── Makevars            # basic pipeline configuration
├── packages-core.txt   # list of R core packages (used only internally)
├── README.md           # this readme
└── scripts             # utility scripts for the pipeline
```

### 2. Pull the docker image that contains all the necessary dependencies

```sh
docker pull prlprg/project-evalr:oopsla21
```

This might take a few minutes, the image has ~4GB. Alternatively, you could
also build the image yourself by issuing

```sh
make docker-image
```

Note: building the image takes about an hour as it needs to install a number of
R packages.

### 3. Run the docker container

The pipeline will run inside the docker container.
The following will spawn a new docker container giving you a bash prompt in the directory that contains the repository:

``` sh
make shell
```

A few details about how the container is run:

- It sets the internal docker container user (called `r`) to have the same UID
  and GID as your username. This is to prevent any permission problems.
- It mount the artifact repository folder to the very same path as it is on your
  machine (i.e. if you cloned the repository to
  `/home/alicia/Temp/evalr-experiment`, the current working directory in the
  container will be the same).

**Important: from now on, all of the commands should be run inside this docker container!**

Issuing `ls` should show the same structure as above with two additional directories:

```sh
...
├── CRAN                 # directory with R package sources
├── library              # directory will installed R packages
...
```

Right now they are empty. They will be filled as we install packages for the
experiment.

Note: the container comes with a very limited set of tools, if you find you are
missing something, you can install anything from Ubuntu repository using the
usual: `sudo apt install <package>`. However, keep in mind that the container
will be removed the moment you exit from the shell prompt.

### 4. Create a sample corpus

The pipeline works with a corpus of R packages. This corpus is defined in a
file `packages.txt` with one package name per line. To run the pipeline, we
first need to create such file. You could try any R packages that are
compatible with R 4.0.2 and are available in CRAN. The more packages, the
longer will it take.

We recommend to start with the following package:

```sh
echo withr > packages.txt
```

Next we need to install the packages:

```sh
make package-install
```

This will install the package including all of their dependencies. By the end
you should see something like (the versions might possibly differ if a package
has been updated in the meantime):

```
...
----------------------------------------------------------------------
=> Extracting package source
----------------------------------------------------------------------
- withr_2.4.2.tar.gz
```

The installed packages will be placed in `library` and their sources under
`CRAN/extracted`.

Note: you can edit the `packages.txt` in both the container (using `vim`) or
any editor on your local machine as the repository is mounted inside the
container.

### 5. Run the eval tracer

The dynamic analysis that traces the eval calls is run using:

```sh
make package-trace-eval
```

In turn, it will do the following:

1. Getting package metadata

    - `run/package-metadata/functions.csv`
    - `run/package-metadata/metadata.csv`
    - `run/package-metadata/revdeps.csv`
    - `run/package-metadata/sloc.csv`

1. Extracting runnable code from packages

    - `run/package-runnable-code-eval/runnable-code.csv`

1. Getting the list of all eval call sites from package source code

    - `run/package-evals-static/package-evals-static.csv`

1. Creating the final corpus

    - `run/corpus.txt`
    - `run/corpus.fst`

1. Listing the eval call sites to be traced

    - `run/package-evals-to-trace.txt`

1. Listing the scripts to be run

    - `run/package-scripts-to-run.txt`

1. Running the package code while tracing the calls to eval

    - `run/package-trace-eval/calls.fst`
    - `run/package-trace-eval/provenances.fst`
    - `run/package-trace-eval/resolved-expressions.fst`
    - `run/package-trace-eval/writes.fst`

For each of the longer running task, there should be a progress bar which shows
an estimate remaining time. Allow at least 20 minutes.

### 6. Run the analysis

TODO: description

```sh
make package-analysis
```

TODO: results

This concludes the first part.

## Detailed instructions

TODO: which parts of the paper should be reproduced?
TODO: where to store the data?
