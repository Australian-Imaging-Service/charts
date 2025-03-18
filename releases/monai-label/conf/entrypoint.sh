#!/bin/bash
APPS=( endoscopy monaibundle pathology radiology )

# https://www.uvicorn.org/#command-line-options
export WEB_CONCURRENCY=2

[[ -f /conf/.env ]] && { source /conf/.env; cat /conf/.env; echo; }

#cd $HOME
mkdir -p {{ .Values.appDir }}
for APP in "${APPS[@]}"; do
	[[ -d {{ .Values.appDir }}/$APP ]] || \
		echo "monailabel apps --name $APP --download --output {{ .Values.appDir }}"
		monailabel apps --name $APP --download --output {{ .Values.appDir }}
done

echo "monailabel apps"
monailabel apps
echo "monailabel datasets"
monailabel datasets
echo "monailabel plugins"
monailabel plugins
