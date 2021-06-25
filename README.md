## Introduction

This repository contains a data analysis pipeline for analyzing the use of
`eval` function in R in the wild. The reason is that using `eval` hinders
static analysis and prevents compilers from performing optimizations. Why try
to provide a better sense of how much and why programmers use `eval` in R.
Understanding why `eval` is used in practice is key to finding ways to mitigate
its negative impact.

## Usage

There is a step-by-step guide in `TUTORIAL.md`.

## Preparing the experimental environment

There are three mode operandi:

1. *docker-local* - running the analysis locally inside a docker container (preferred)
1. *local* - running the analysis locally (useful for debugging)
1. *docker-cluster* - running the analysis in a cluster composed of docker-local containers

All options require that you have cloned the repository.
All further commands should be run inside the repository.

### docker-local

For this one only need GNU make, docker and git (to clone this repository).

1. Get the docker image

    Either pull it from docker hub:

    ```sh
    docker pull prlprg/project-evalr
    ```

    or build locally

    ```sh
    make docker-image
    ```

1. If you plan to hack the tracer, you need to install a local copy

    By default, the docker image contains the tracer already installed in
    `/R/R-dyntrace/library/evil`. If you want to modify it, create a local
    copy.

    Start the docker container

    ```sh
    make shell
    ```

    Install local version of the eval tracer

    ```sh
    make evil
    ```

    or if you plan to hack on other components, you can get local version of all components

    ```sh
    make libs
    ```

### local

If you know what are you doing, you could also develop locally.
For this we need to setup the environment:

1. Install [R-dyntrace](https://github.com/PRL-PRG/R-dyntrace/tree/r-4.0.2),
   a modified GNU R 4.0.2 VM that exposes low-level callbacks for a variety of
   runtime events.

    ```sh
    git clone -b r-4.0.2 https://github.com/PRL-PRG/R-dyntrace/tree/r-4.0.2
    cd R-dyntrace
    ./build
    ```

1. Set the local environment

    ```sh
    source environment.sh
    ```

1. Install tracer dependencies

    ```sh
    make libs-dependencies
    ```

1. Install tracer and other pipeline components

    ```sh
    make libs
    ```

### docker-cluster

1. Add hostnames into `Makefile.cluster`

1. Setup nodes

    ```sh
    make -f Makefile.cluster node-setup
    ```

    ---

    **NOTE**

    - This requires that all the nodes can fetch the docker image.
    - Run the `node-setup` target in tmux - it creates a new window split pane, one per node

    ---

1. Run any target with `CLUSTER=1`

    For example:

    ```sh
    make package-trace-eval CLUSTER=1
    ```
