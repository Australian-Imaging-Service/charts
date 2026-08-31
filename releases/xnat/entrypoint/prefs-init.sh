#!/bin/bash
PREFS_INIT="${XNAT_HOME}/config/prefs-init.ini"
if [[ -f "${PREFS_INIT}" ]]; then
  FILE_STORE_PATH=$(sed -n 's/^fileStorePath=\(.*\)/\1/p' "${PREFS_INIT}")
  while IFS= read -r line; do
    if [[ $line == /* ]]; then
      mkdir -p "${line}"
    else
      mkdir -p "${FILE_STORE_PATH}/${line}"
    fi
  done < <(sed -n 's/^[a-z]\+Path=\(.*\)$/\1/p' "${PREFS_INIT}")
fi
