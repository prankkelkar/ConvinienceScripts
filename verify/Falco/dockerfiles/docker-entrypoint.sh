#!/bin/bash


if [[ -z "${SYSDIG_SKIP_LOAD}" ]]; then
    echo "* Setting up /usr/src links from host"

    for i in $(ls $SYSDIG_HOST_ROOT/usr/src)
    do
        ln -s $SYSDIG_HOST_ROOT/usr/src/$i /usr/src/$i
    done

    /usr/bin/falco-probe-loader
fi

exec "$@"