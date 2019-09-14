#!/bin/bash

PACKAGE=$1
PACKAGE_CONTENT=$(timeout 0.3 tar tf $PACKAGE resources/app.yaml 2>/dev/null)

## Shift positionals to remove the package file name from script arguments
shift

if [ $PACKAGE_CONTENT ]; then
  printf "Connecting to Gravity Ops Center...\n"
  gravity ops connect --insecure https://localhost:3009 admin Passw0rd123
  printf "Pushing application to Gravity Ops Center (background process)...\n"
  nohup gravity app import --force --insecure --ops-url=https://localhost:3009 $PACKAGE >> /var/log/gravity_app_import.log 2>&1 &
  printf "Generating application string...\n"
  APP_VERSION=$(timeout 0.3 tar xf $PACKAGE resources/app.yaml --to-command './yq r - metadata.resourceVersion; true')
  APP_NAME=$(timeout 0.3 tar xf $PACKAGE resources/Chart.yaml --to-command './yq r - metadata.name; true')
  REPO_NAME=$(timeout 0.3 tar xf $PACKAGE resources/app.yaml --to-command './yq r - metadata.repository; true')
  APP_STRING="$REPO_NAME/$APP_NAME:$APP_VERSION"
  #printf "Pulling application from Gravity Ops Center...\n"
  #gravity app pull --force --insecure --ops-url=https://localhost:3009 $APP_STRING
  printf "Importing application to local Gravity repository...\n"
  gravity app import $PACKAGE
  printf "Exporting application to local Docker registry...\n"
  gravity exec gravity app export $APP_STRING
  printf "Executing application install hook...\n"
  gravity exec gravity app hook $@ --debug $APP_STRING install
  printf "\n\nDone!\n"
else
  PACKAGE_CONTENT=$(timeout 0.3 tar tf $PACKAGE app.yaml 2>/dev/null)
  if [ $PACKAGE_CONTENT ]; then
    printf "Installing package...\n"
    gravity app install $@ $PACKAGE
  else
    printf "Not a valid Gravity package, exiting.\n"
    exit 1
  fi
fi
