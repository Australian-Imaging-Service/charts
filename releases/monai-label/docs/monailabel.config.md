# monailabel.config

* https://docs.monai.io/projects/label/en/latest/apidocs/monailabel.config.html

```.env
export MONAI_LABEL_API_STR=
export MONAI_LABEL_PROJECT_NAME=MONAILabel
export MONAI_LABEL_APP_DIR=/home/user/apps/radiology
export MONAI_LABEL_STUDIES=/home/user/datasets/Task09_Spleen/imagesTr
export MONAI_LABEL_APP_CONF='{}'
export MONAI_LABEL_AUTH_ENABLE=False
export MONAI_LABEL_AUTH_REALM_URI=http://localhost:8080/realms/monailabel
export MONAI_LABEL_AUTH_TIMEOUT=10
export MONAI_LABEL_AUTH_TOKEN_USERNAME=preferred_username
export MONAI_LABEL_AUTH_TOKEN_EMAIL=email
export MONAI_LABEL_AUTH_TOKEN_NAME=name
export MONAI_LABEL_AUTH_TOKEN_ROLES=realm_access#roles
export MONAI_LABEL_AUTH_CLIENT_ID=monailabel-app
export MONAI_LABEL_AUTH_ROLE_ADMIN=monailabel-admin
export MONAI_LABEL_AUTH_ROLE_REVIEWER=monailabel-reviewer
export MONAI_LABEL_AUTH_ROLE_ANNOTATOR=monailabel-annotator
export MONAI_LABEL_AUTH_ROLE_USER=monailabel-user
export MONAI_LABEL_TASKS_TRAIN=True
export MONAI_LABEL_TASKS_STRATEGY=True
export MONAI_LABEL_TASKS_SCORING=True
export MONAI_LABEL_TASKS_BATCH_INFER=True
export MONAI_LABEL_DATASTORE=
export MONAI_LABEL_DATASTORE_URL=
export MONAI_LABEL_DATASTORE_USERNAME=
export MONAI_LABEL_DATASTORE_PASSWORD=
export MONAI_LABEL_DATASTORE_API_KEY=
export MONAI_LABEL_DATASTORE_CACHE_PATH=
export MONAI_LABEL_DATASTORE_PROJECT=
export MONAI_LABEL_DATASTORE_ASSET_PATH=
export MONAI_LABEL_DATASTORE_DSA_ANNOTATION_GROUPS=
export MONAI_LABEL_DICOMWEB_USERNAME=
export MONAI_LABEL_DICOMWEB_PASSWORD=
export MONAI_LABEL_DICOMWEB_CACHE_PATH=
export MONAI_LABEL_QIDO_PREFIX=None
export MONAI_LABEL_WADO_PREFIX=None
export MONAI_LABEL_STOW_PREFIX=None
export MONAI_LABEL_DICOMWEB_FETCH_BY_FRAME=False
export MONAI_LABEL_DICOMWEB_CONVERT_TO_NIFTI=True
export MONAI_LABEL_DICOMWEB_SEARCH_FILTER='{"Modality": "CT"}'
export MONAI_LABEL_DICOMWEB_CACHE_EXPIRY=7200
export MONAI_LABEL_DICOMWEB_PROXY_TIMEOUT=30.0
export MONAI_LABEL_DICOMWEB_READ_TIMEOUT=5.0
export MONAI_LABEL_DATASTORE_AUTO_RELOAD=True
export MONAI_LABEL_DATASTORE_READ_ONLY=False
export MONAI_LABEL_DATASTORE_FILE_EXT='["*.nii.gz", "*.nii", "*.nrrd", "*.jpg", "*.png", "*.tif", "*.svs", "*.xml"]'
export MONAI_LABEL_SERVER_PORT=8000
export MONAI_LABEL_CORS_ORIGINS='[]'
export MONAI_LABEL_SESSIONS=True
export MONAI_LABEL_SESSION_PATH=
export MONAI_LABEL_SESSION_EXPIRY=3600
export MONAI_LABEL_INFER_CONCURRENCY=-1
export MONAI_LABEL_INFER_TIMEOUT=600
export MONAI_LABEL_TRACKING_ENABLED=True
export MONAI_LABEL_TRACKING_URI=
export MONAI_ZOO_SOURCE=github
export MONAI_ZOO_REPO=Project-MONAI/model-zoo/hosting_storage_v1
export MONAI_ZOO_AUTH_TOKEN=
export MONAI_LABEL_AUTO_UPDATE_SCORING=True
export PYTHONPATH=/usr::/home/user/apps/radiology:/home/user/apps/radiology:/home/user/apps/radiology/lib
export PATH=/usr/local/lib/python3.10/dist-packages/torch_tensorrt/bin:/usr/local/mpi/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/ucx/bin:/opt/tensorrt/bin:/opt/tools:/opt/tools/ngc-cli:/opt/tools:/home/user/apps/radiology/bin
```
