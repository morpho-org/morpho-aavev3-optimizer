.EXPORT_ALL_VARIABLES:

PATH:=${shell pwd}/why3-provers:${PATH}

install:
	git lfs install
	git submodule update --init
	why3 config detect

replay-%:
	why3 replay -L. $*

.PHONY: install 
