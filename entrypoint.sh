#!/usr/bin/env bash
set -e

log() {
  echo ">> [local]" "$@"
}

cleanup() {
  set +e
  log "Killing ssh agent."
  ssh-agent -k
  log "Removing workspace archive."
  rm -f /tmp/workspace.tar.bz2
}
trap cleanup EXIT

log "Packing workspace into archive to transfer onto remote machine."
tar cjvf /tmp/workspace.tar.bz2 $TAR_PACKAGE_OPERATION_MODIFIERS .

log "Launching ssh agent."
eval `ssh-agent -s`

ssh-add <(echo "$SSH_PRIVATE_KEY")

remote_command="set -e;

srcdir=\"\$HOME/workspace/$PROJECT_NAME/src\";
storedir=\"\$HOME/workspace/$PROJECT_NAME/store\";

log() {
    echo '>> [remote]' \$@ ;
};

if [ -d \$srcdir ]
then
  log 'Deleting source directory...';
  rm -rf \$srcdir;
fi

if [ ! -d \$storedir ]; then
  log 'Creating storage directory...';
  mkdir -p \$storedir;
fi

log 'Creating source directory...';
mkdir -p \$srcdir;

log 'Unpacking source...';
tar -C \$srcdir -xjv;

log 'Launching docker compose...';
cd \$srcdir;
cd $DOCKER_COMPOSE_FILE_PATH;

if $DOCKER_COMPOSE_DOWN
then
  log 'Executing docker compose down...';
  docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" down
fi

if [ -n \"$DOCKERHUB_USERNAME\" ] && [ -n \"$DOCKERHUB_PASSWORD\" ]
then
  log 'Executing docker login...';
  docker login -u \"$DOCKERHUB_USERNAME\" -p \"$DOCKERHUB_PASSWORD\"
fi

dangling=$(docker images --filter "dangling=true" -q --no-trunc)
if [ ! -z $dangling ]; then
  log 'Cleaning dangling docker images...';
  docker rmi $dangling;

log 'Executing docker compose pull...';
docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" pull

if $NO_CACHE
then
  docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" build --no-cache
  docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" up -d --remove-orphans --force-recreate
else
  docker-compose -f \"$DOCKER_COMPOSE_FILENAME\" -p \"$DOCKER_COMPOSE_PREFIX\" up -d --remove-orphans --build;
fi"

log "Connecting to remote host."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=100 \
  "$SSH_USER@$SSH_HOST" -p "$SSH_PORT" \
  "$remote_command" \
  < /tmp/workspace.tar.bz2
