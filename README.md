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

You will need the following tools installed:

- GNU bash 5.0+
- Docker 20.0+
- git 2.24+
- GNU Make 4.2+

(Versions are indicative, just the one we use).

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
Next to the *docker-local* dependencies you will additionally need:

- [fd](https://github.com/sharkdp/fd) version 8.0+ (the merge scripts calls `fd` binary)

First you need to setup the environment:

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

Next to the docker-local dependencies you will also need:

- [tmux](https://github.com/tmux/tmux) version 2.6+
- [GNU parallel](https://www.gnu.org/software/parallel/) version 20200322+

    Installable using

    ```sh
    sh -c "$(curl -sSL 'https://bit.ly/install-gnu-parallel-2')"
    ```

The cluster is setup in the following way:

- in each of the hosts mentioned in

1. Check the cluster configuration in `Makevars.cluster`

   The only thing that should be adjusted are `HOSTS` and `SSH_NUM_SLOTS`.

1. Make sure you can connect with no password to each of the host from the host
   from which you will run the following commands.

1. Setup nodes

    ```sh
    make -f Makefile.cluster node-setup
    ```

    This will connect to each of the hosts using ssh. Pull docker image and run
    it as a new container with sshd in the foreground. It will connect to that
    that sshd instance using a connection multiplexing (ssh control file) to
    speed up the consequent connections from GNU parallel.

    ---

    **NOTE**

    - This requires that all the nodes can fetch the docker image.
    - Run the `node-setup` target in tmux - it creates a new window split pane, one per node

    ---

1. Generate the cluster description file for parallel

    ```sh
    make -f Makefile.cluster ssh-login-file
    ```

1. Run any target with `CLUSTER=1`

    For example:

    ```sh
    make package-trace-eval CLUSTER=1
    ```
