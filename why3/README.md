# Verification of Morpho-AaveV3's core logic using Why3

## Installation

The formal verification uses [Why3](https://why3.lri.fr/).

### From sources or using opam

You can install why3 locally from sources or using opam, following the instructions from the project home page, and install the following versions of the provers:
- CVC4 version 1.8
- Alt-Ergo version 2.0.0
- Z3 version 4.10.2

This should give you access to the `why3` binary.

### Using docker

You can also use the docker version, install it by invoking `make`.

Then, if you have a X server (under Linux), you can use `./why3-X.sh`. Otherwise, you can invoke `./why3-web.sh`.

In the following, we will write `WHY3` for either `why3`, `./why3-X.sh` or `./why3-web.sh` depeding on the installation you chose.

## Usage

The formal verification can be replayed by invoking `WHY3 replay -L . morpho`. Replace `morpho` by another `.mlw` file to replay another file.

To fiddle with the verification, and show the why3 GUI, run `WHY3 ide -L . morpho`. In case where you launcher is `./why3-web.sh`, you also need to open a browser and navigate to [localhost](http://localhost:8080/).
