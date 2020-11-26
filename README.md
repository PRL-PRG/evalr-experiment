# signatr-experiment

This is a skeleton project for running signatr experiments.
The idea is to have an isolated environment in which one can run the fuzzer.

## Getting started guide

``` sh
git clone ssh://git@github.com/PRL-PRG/signatr-experiment
cd signatr-experiment
```
**Important: all of the following commands should be run inside the cloned repository!**

If the docker image has not yet been created, run

```sh
make -C docker-image
```

Get the dependencies. The reason why we do not put them yet in the image is that
we might want to have some local changes to them.

```sh
git clone ssh://git@github.com/PRL-PRG/injectr
git clone ssh://git@github.com/PRL-PRG/instrumentr
git clone ssh://git@github.com/PRL-PRG/runr
git clone ssh://git@github.com/PRL-PRG/signatr
```

Install the dependencies, using the docker image!

``` sh
./in-docker.sh make libs
```

This should create a `library` directory with the following:

``` sh
drwxr-xr-x 7 krikava krikava 4096 Nov  8 21:41 injectr
drwxr-xr-x 8 krikava krikava 4096 Nov  8 21:42 instrumentr
drwxr-xr-x 7 krikava krikava 4096 Nov  8 21:42 runr
drwxr-xr-x 6 krikava krikava 4096 Nov  8 21:42 signatr
```

**Important: double check that you see your username!**

Now you can run the experiments. For example

``` sh
$ echo "stringr" > packages-1.txt
$ ./in-docker.sh make signatr-gbov PACKAGES_FILE=packages-1.txt
...
$ cat run/signatr-gbov/task-stats.csv # you should see the first zero indicating a success
package,exitval,hostname,start_time,end_time,command
/home/r/work/run/signatr-gbov/stringr,0,cb27c60eb1cb,1604875468,1604875492,/home/r/work/runr/inst/tasks/run-extracted-code.R /R/CRAN/extracted/stringr /home/r/work/run/package-code-signatr//stringr
```

