#!/usr/bin/env bash

TIMESTAMP=$(date '+%Y%m%d-%s')
APP_ARCHIVE_DIR=/home/user/development/deploy/packed/
APP_SOURCE_PATH=/home/wid/development/prj/name
APP_ARCHIVE_NAME=deploy_name_${TIMESTAMP}.tar.gz

#: compress file
pack() {
    cd "${APP_SOURCE_PATH}"
    make clean
    cd ..
    zip -9 \
    -r "${APP_ARCHIVE_DIR}${APP_ARCHIVE_NAME}" \
    foldername \
    -x"*.git/*" "*.idea/*" "*.env" "*tmp/*" "*DOCS/*" ""*TODO*""
}

pack
