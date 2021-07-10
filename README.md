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

Reported times were measured on Linux 5.12 laptop with Intel i7-7560U @ 2.40GHz and
16GB RAM.

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

Among others, it will do the following:

- Extracts package metadata (*package-metadata*)
- Extracts and instruments runnable code from packages (*package-runnable-code-eval*)
- Finds `eval` call sites from package source code (*package-evals-static*)
- Runs the package code while tracing the calls to `eval` (*package-trace-eval*)

For each of the longer running task, there should be a progress bar which shows
an estimate remaining time. Allow at least 15 minutes.

After make finishes, there should a new `run` directory with the following content:

```
run
├── package-evals-static
├── package-metadata
├── package-runnable-code-eval
├── package-trace-eval
├── corpus.fst
├── corpus.txt
├── package-evals-to-trace.txt
└── package-scripts-to-run.txt
```

Each directory contains results for each of the task that was run.
To quickly check the results of the tracer, you can run:

```sh
./scripts/parallel-log.R run/package-trace-eval
```

which should print out something like:

```
Duration: 183.94 (sec)
Average job time: 18.15 (sec)
Number of hosts: 1
Number of jobs: 39
Number of success jobs: 39 (100.00%)
Number of failed jobs: 0 (0.00%)

Exit codes:
  0:    39 (100.00%)
```

This says that it successfully ran all 39 extracted R programs in about
3 minutes (18 seconds average is OK as jobs run in parallel, cf. bellow). We
will go over the details in the next section.

Notes:

- We use [GNU parallel](https://www.gnu.org/software/parallel/) to run certain
  tasks in parallel. By default, the number of jobs will equal to the number of
  available cores. If you want to throttle it down, set the `JOBS` variable to
  lower number (e.g. `make package-trace-eval JOBS=2`). You can see the current
  value by running `make info`.

- Next time you run `make package-trace-eval` it will only run the tracer
  unless `packages.txt` was changed in the meantime which will trigger
  regeneration of the auxiliary data.

- If anything goes wrong, you can always start from scratch by removing the
  `run` folder.

### 6. Run the analysis

Right now you should have the raw data. Next, we need to preprocess them
(mostly a data cleanup) and run the actual analysis. The analysis is done in R,
concretely in a number of [R markdown](https://rmarkdown.rstudio.com/)
notebooks.

As usual, this is done by make:

```sh
make package-analysis
```

First, it will re-extract runnable code from packages (*package-runnable-code*), this time without any instrumentation and run it (*package-run*) so it can compute the tracer failure rate.
Next, it will run the analysis, knitting four notebooks.
It should take about 3 minutes and the results will be in `run/analysis`:

```
run/analysis/
├── paper
│   ├── img
│   │   ├── package_calls_per_run_per_call_site.pdf  # Figure 7b
│   │   ├── package_combination_minimized.pdf
│   │   ├── package_eval_calls_per_packages.pdf
│   │   ├── package_events_per_pack_large.pdf        # Figure 9b
│   │   ├── package_events_per_pack_small.pdf        # Figure 9a
│   │   ├── package_size_loaded_distribution.pdf     # Figure 8
│   │   ├── pkgs-eval-callsites-hist.pdf             # Figure 3
│   │   ├── se-types.pdf
│   │   └── traced-eval-callsites.pdf                # Figure 6
│   └── tag
│       ├── corpus.tex
│       ├── package_normalized_expr.tex
│       ├── package_usage_metrics.tex
│       ├── side-effects.tex
│       ├── table-se-target-envs.tex                 # Table 7
│       └── table-se-types.tex                       # Table 8
├── corpus.html
├── normalized.html
├── package-usage.html
└── side-effects.html
```

There are two results:

1. The HTML files that contain the actual analysis

    - `corpus.html` is mostly used for Section 3.1.
    - `normalized.html` is used for Section 5.1.
    - `package-usage.html` contains data for the CRAN dataset and is used for
      Section 4, 5.1, 5.2 and 5.3.
    - `side-effects.html` provides data for Section 5.4.

2. The files generated in the `paper` directory are used for typesetting the
   paper. The `img` sub-directory contains all the plots included in the paper.
   The `tag` sub-directory contains latex tables and *tag* files - latex macros
   for each of the number that is used in the paper.

You can view the files from your machine. Please note that all the data are
base on just a single-package corpus and thus some metric are not relevant.

If you managed to get this far, you essentially reproduced the findings for
a single CRAN package. In the next section we will describe the details about
how does the tracing work, about the infrastructure and finally run a larger
experiment.

## Detailed instructions

TODO: which parts of the paper should be reproduced?
TODO: where to store the data?
    - `run/package-metadata/functions.csv`
    - `run/package-metadata/metadata.csv`
    - `run/package-metadata/revdeps.csv`
    - `run/package-metadata/sloc.csv`
    - `run/package-runnable-code-eval/runnable-code.csv`
    - `run/package-evals-static/package-evals-static.csv`
    - `run/corpus.txt`
    - `run/corpus.fst`
    - `run/package-evals-to-trace.txt`
    - `run/package-scripts-to-run.txt`
    - `run/package-trace-eval/calls.fst`
    - `run/package-trace-eval/provenances.fst`
    - `run/package-trace-eval/resolved-expressions.fst`
    - `run/package-trace-eval/writes.fst`
