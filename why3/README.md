# Verification of Morpho-AaveV3's core logic using Why3

The formal verification uses [Why3](https://why3.lri.fr/).

## Installation from sources or using opam

You can install Why3 locally from sources or using opam, following the instructions from the project home page, and install the following versions of the provers:
- CVC4 version 1.8
- Alt-Ergo version 2.0.0
- Z3 version 4.10.2

This should give you access to the `why3` binary.

## Installation using docker

If you have docker installed on your machine, you can pull a docker image by invoking `make` in the `why3` folder.

Then, if you have a X server (Linux), you can use `./why3-X.sh` (in the `why3` folder). Otherwise, you can use `./why3-web.sh`.

In the following, we will write `WHY3` for either `why3`, `./why3-X.sh` or `./why3-web.sh` depending on the installation you chose.

## Usage

The formal verification can be replayed by invoking `WHY3 replay -L . morpho`. Replace `morpho` by the basename another `.mlw` file to replay it.

To show the Why3 GUI, run `WHY3 ide -L . morpho`. In case where you launcher is `./why3-web.sh`, you also need to open a browser and navigate to [localhost](http://localhost:8080/).
