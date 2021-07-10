---
title: "Why We Eval in the Shadown"
subtitle: "OOPSLA21 Artifact"
author:
  - Aviral Goel
  - Pierre Donat-Bouillud
  - Filip Krikava
  - Christoph Kirsch
  - Jan Vitek
output:
  html_document:
    gallery: false
    toc: true
    toc_depth: 3
    toc_float: true
  pdf_document:
    toc: true
    toc_depth: 3
    latex_engine: xelatex
date: "9.7.2021"
---

## Introduction

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
1. *Detailed instructions* which will guide you through the process of
   reproducing the data presented in the paper.

Reported times were measured on Linux 5.12 laptop with Intel i7-7560U @ 2.40GHz and
16GB RAM.

It is good to get familiar with the methodology that is presented in Section 3
of the paper.

## Not in the artifact

In the paper, we provide results by analyzing three corpora: R base libraries
(*base*), CRAN packages (*CRAN*) and Kaggle kernels (*kaggle*), cf. Section 3.1
Corpus. Because of the licensing issues, we cannot redistribute neither the
code nor the data from the Kaggle website. The rest of this document will
therefore only focus only on base and CRAN.

## Getting started guide

In this section we will go through the steps of getting the artifact up and running.
Before you begin, make sure you have a functional docker on your system by running:

```sh
docker run --rm hello-world
```

It should eventually print `Hello from Docker!`. If it does not, your docker
environment is not properly configured and the following instructions will not
work.

A common problem with a newly installed docker is a missing permission. If you
got the following error:

```
Got permission denied while trying to connect to the Docker daemon socket at
unix:///var/run/docker.sock: Get http://%2Fvar%2Frun%2Fdocker.sock/v1.24/containers/json:
dial unix /var/run/docker.sock: connect: permission denied
```

Simply add your username into the `docker` group (e.g. `sudo usermod -a -G docker <username>`)


### 1. Get a copy of the repository

``` sh
git clone -b oopsla21 ssh://git@github.com/PRL-PRG/evalr-experiment
cd evalr-experiment
```

---

**IMPORTANT**

- **Please make sure you use the `oopsla21` branch.**
- **From now on, all of the commands should be run inside the cloned
  repository.**

---

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

### 2. Get the docker image

For the ease of use we pack all the dependencies in a docker image. We also use
the very same image to run the experiment in a cluster to make sure each node
has the same environment.

There are two options to get the image: pull it from the docker hub or build it
locally.

1. Pulling from docker hub:

    ```sh
    docker pull prlprg/project-evalr:oopsla21
    ```

    This might take a few minutes, the image has ~4GB.

1. Building the image locally:

    ```sh
    make docker-image
    ```

    It takes about an hour as it needs to install a number of R packages.

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

---

**IMPORTANT**

**From now on, all of the commands should be run inside this docker container!**

---

Issuing `ls` should show the same structure as above with two additional directories:

```sh
...
├── CRAN                 # directory with R package sources
├── library              # directory will installed R packages
...
```

Right now they are empty. They will be filled as we install packages for the
experiment.

---

**NOTE**

- The container comes with a very limited set of tools, if you find you are
  missing something, you can install anything from Ubuntu repository using the
  usual: `sudo apt install <package>`. However, keep in mind that the container
  will be removed the moment you exit from the shell prompt.

---

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

---

**NOTE**

- The `packages.txt` can be edited in both the container (using `vim`) or any
  editor on your local machine as the repository is mounted inside the
  container.

---

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
an estimate remaining time. Allow at least 15 minutes. By the end it should
finish with something like:

```
...
----------------------------------------------------------------------
=> MERGING provenances.fst
----------------------------------------------------------------------
...
make[1]: Leaving directory '/home/krikava/Research/Projects/evalR/artifact'
```

After it finishes, there should a new `run` directory with the following content:

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

---

**NOTE**

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

- The results are either plain text files, CSV files or, for the larger output
  we use [fst](https://www.fstpackage.org/) format which provides a fast data
  frame compression based on the Facebook's
  [zstd](https://github.com/facebook/zstd) library. To view the content of an
  fst file, you could use the `scripts/cat.R` utility (e.g. `./scripts/cat.R
  run/package-trace-eval/writes.fst`)

---

### 6. Run the analysis

Right now you should have the raw data. Next, we need to preprocess them
(mostly a data cleanup) and run the actual analysis. The analysis is done in R,
concretely in a number of [R markdown](https://rmarkdown.rstudio.com/)
notebooks.

First, we run the data preprocessing

```sh
make package-preprocess
```

This will re-extract runnable code from packages (*package-runnable-code*), this time without any instrumentation and run it (*package-run*) so it can compute the tracer failure rate.

It should take about 2 minutes and the results will be in `run/preprocess/package`.
The content should like like this:

```
run/preprocess/package
├── corpus.fst
├── corpus.txt
├── evals-static.csv
├── normalized-expressions.csv
├── run-log.csv
├── runnable-code.csv
├── side-effects.fst
├── summarized-externals.fst
├── summarized.fst
├── trace-log.csv
└── undefined.fst
```

This is the source for the next step, the analysis.
We will run (*knit*) four analysis notebooks (from `analysis` folder):

```sh
make package-analysis
```

It should take about a minutes and the results will be in `run/analysis`:

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

    - [`corpus.html`](run/analysis/corpus.html) is mostly used for Section
      3.1.
    - [`normalized.html`](run/analysis/normalized.html) is used for Section
      5.1.
    - [`package-usage.html`](run/analysis/package-usage.html) contains data for
      the CRAN dataset and is used for Section 4, 5.1, 5.2 and 5.3.
    - [`side-effects.html`](run/analysis/side-effects.html) provides data for
      Section 5.4.

2. The files generated in the `paper` directory are used for typesetting the
   paper.

   - The `img` sub-directory contains all the plots included in the paper.
   - The `tag` sub-directory contains latex tables and *tag* files - latex
     macros for each of the number that is used in the paper.

You can view the files from your machine. Please note that all the data are
base on just a single-package corpus and thus some metric are not relevant.

The following is the list of the results that we include in the paper (the
figure/table headings should be click-able links):

---

**FIGURES**

- [Figure 3](run/analysis/paper/img/pkgs-eval-callsites-hist.pdf): CRAN `eval` call sites
- [Figure 4]
- [Figure 5]
- [Figure 6](run/analysis/paper/img/traced-eval-callsites.pdf): `eval` call sites coverage
- [Figure 7a]: Normalized calls - all
- [Figure 7b](run/analysis/paper/img/package_calls_per_run_per_call_site.pdf): Normalized calls - small
- [Figure 8](run/analysis/paper/img/package_size_loaded_distribution.pdf): Loaded code
- [Figure 9a](run/analysis/paper/img/package_events_per_pack_small.pdf): Instructions per call - small
- [Figure 9b](run/analysis/paper/img/package_events_per_pack_large.pdf): Instructions per call - large

---

**TABLES**

- [Table 1]():
- [Table 2]():
- [Table 3]():
- [Table 4]():
- [Table 5]():
- [Table 6]():
- [Table 7](run/analysis/side-effects.html#table_se_target_envs): Target environments for side-effects
- [Table 8](run/analysis/side-effects.html#table_se_types): Types of `eval` side-effects

---

**Congratulations!** If you managed to get this far, you essentially analyzed
the use of `eval` for a single CRAN package.

## Detailed instructions

In this section we provide additional details about how to trace eval calls for
the R base libraries and how to reproduce the findings presented in the paper.

For the steps in this section, we assume that you have successfully completed
all the steps from the getting started guide and are in the bash prompt in the
docker images (i.e. executed `make shell`).

### Tracing eval calls in base

Next to CRAN, we also report on the use of `eval` in the core packages that are
part of the R language. The reason why we treat them separately is that they
are relatively stable, part of the language itself, written by R core
maintainers and finally, there are relatively few `eval` call sites.
Nevertheless they are also heavily exercised as there is hardly any R code that
would execute without calling `eval` from core libraries.

To collect information about the base usage of `eval` we do a isolated run of a
subset of the extracted programs from CRAN packages while tracing only the
`eval` call sites presented in core packages.

Reusing the extracted programs from the getting started guide, we can trace
base using the following:

1. Run the tracer with base evals only

    ```sh
    make base-trace-eval
    ```

1. Preprocess base

    ```sh
    make base-preprocess
    ```

1. Run the analysis

    ```sh
    make base-analysis
    ```

The results is in [`base-usage.html`](run/analysis/base-usage.html).

---

**NOTE**

- The number of programs it will run is controlled by the
  `BASE_SCRIPTS_TO_RUN_SIZE` environment variable, which is by default 25K. It
  will therefore run up to that number of programs.

---

### Reproducing paper findings

To redo the same experiment as we report in the submitted paper, one only needs
to get all CRAN packages and put them in the `packages.txt` file.

```sh
R -q --slave -e \
  'cat(available.packages(repos="https://cloud.r-project.org")[, 1], sep="\n")'
```

However, the experiment is rather lengthy, in our cluster of three servers,
each with 2.3GHz Intel Xeon 6140 processor with 72 cores and 256GB of RAM, it
took over 60 hours. You can also rerun the experiment on a subset of CRAN.
For example:

1. Clean the run folder

    ```sh
    rm -fr run
    ```

1. Create a corpus of 10 randomly selected CRAN packages

    ```sh
    R -q --slave -e \
      'cat(available.packages(repos="https://cloud.r-project.org")[, 1], sep="\n")' | \
      shuf -n 10 > packages.txt
    ```

1. Install the packages

    ```sh
    make package-install
    ```

1. Run the tracer

    ```sh
    make package-trace-eval base-trace-eval
    ```

1. Run the preprocessing

    ```sh
    make package-preprocess base-preprocess
    ```

1. Run the analysis

    ```sh
    make package-analysis base-analysis
    ```

The results will be in the same files as indicated above.

---

**NOTE**

- It might take up to a few hours depending on the selected packages.
- The final package count might be smaller as not all packages use evals. Some
  packages could also be filtered out because they cannot be installed (missing
  some native dependencies) or they do not contain R code.
- By default, there is 35 minutes timeout for all the tasks that run in
  parallel (e.g., extracting package metadata, running R programs). It can be
  adjusted by the `TIMEOUT` environment variable.
- R does not provide any mechanism for pinning package versions. This means
  that even if you try all the CRAN packages, the results could be slightly
  different from ours as the package evolves. However the general shape should
  be the same.
- Clean the `run` folder every time you experiment with a new corpus.

---

As an alternative, we provide the preprocessed data on which you can run the
analysis.

1. Download the data (~180MB)

    ```sh
    wget -O run-submission.tar.xz https://owncloud.cesnet.cz/index.php/s/O2ntsqPufhKRObv/download
    ```

1. Extract the archive (~1.5GB)

    ```sh
    tar xfvJ run-submission.tar.xz
    ```

1. Run the analysis using the new full corpus

    This is again done by make. The only thing that we need to change is say
    that the data are no longer in the `run` directory, but in
    `run-submission`:

    ```sh
    make analysis RUN_DIR=$PWD/run-submission
    ```

The results will be generated in `run-submission/analysis` and they follow the
very same structure as before. The following are links for convenience.

---

**NOTEBOOKS**

  - [`corpus.html`](run-submission/analysis/corpus.html) is mostly used for Section
    3.1.
  - [`normalized.html`](run-submission/analysis/normalized.html) is used for Section
    5.1.
  - [`package-usage.html`](run-submission/analysis/package-usage.html) contains data for
    the CRAN dataset and is used for Section 4, 5.1, 5.2 and 5.3.
  - [`base-usage.html`](run-submission/analysis/package-usage.html) contains data for
    the base dataset and is used primarily for Section 4.
  - [`kaggle-usage.html`](run-submission/analysis/package-usage.html) contains data for
    the Kaggle dataset and is used primarily for Section 4.
  - [`side-effects.html`](run-submission/analysis/side-effects.html) provides data for
    Section 5.4.

**FIGURES**

- [Figure 3](run-submission/analysis/paper/img/pkgs-eval-callsites-hist.pdf): CRAN `eval` call sites
- [Figure 4]():
- [Figure 5]():
- [Figure 6](run-submission/analysis/paper/img/traced-eval-callsites.pdf): `eval` call sites coverage
- [Figure 7a]: Normalized calls - all
- [Figure 7b](run-submission/analysis/paper/img/package_calls_per_run_per_call_site.pdf): Normalized calls - small
- [Figure 8](run-submission/analysis/paper/img/package_size_loaded_distribution.pdf): Loaded code
- [Figure 9a](run-submission/analysis/paper/img/package_events_per_pack_small.pdf): Instructions per call - small
- [Figure 9b](run-submission/analysis/paper/img/package_events_per_pack_large.pdf): Instructions per call - large

---

**TABLES**

- [Table 1]():
- [Table 2]():
- [Table 3]():
- [Table 4]():
- [Table 5]():
- [Table 6]():
- [Table 7](run-submission/analysis/side-effects.html#table_se_target_envs): Target environments for side-effects
- [Table 8](run-submission/analysis/side-effects.html#table_se_types): Types of `eval` side-effects

---

