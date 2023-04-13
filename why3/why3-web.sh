#!/bin/sh
exec docker run --rm -p 8080:8080 --env WHY3IDE=web --user `id -u` --volume `pwd`:/data --workdir /data why3 "$@"
