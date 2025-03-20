#!/bin/bash
# https://www.uvicorn.org/#command-line-options
export WEB_CONCURRENCY=2

source /conf/.env
APP_PATH="$(dirname $MONAI_LABEL_APP_DIR)"
APP_NAME="$(basename $MONAI_LABEL_APP_DIR)"

echo
echo "MONAI label environment settings"
cat /conf/.env
echo

echo "monailabel apps"
monailabel apps
echo "monailabel datasets"
monailabel datasets
echo "monailabel plugins"
monailabel plugins

[[ -d $APP_PATH ]] || mkdir -p "${APP_PATH}"
if [[ ! -d $MONAI_LABEL_APP_DIR ]]; then
	echo "monailabel apps --name ${APP_NAME} --download --output ${APP_PATH}"
	monailabel apps --name $APP_NAME --download --output ${APP_PATH}
fi
[[ -d $MONAI_LABEL_STUDIES ]] || mkdir -p "${MONAI_LABEL_STUDIES}"
