#!/usr/bin/env bash

# main() {
#   echo "Backups Oh yeah"
# }


######
# get_token_rest - get accessJWT token with REST command for Dgraph 1.x
##########################
get_token_rest() {
  JSON="{\"userid\": \"${USER}\", \"password\": \"${PASSWORD}\" }"
  ACCESS_JWT=$(
    /usr/bin/curl --silent \
      $CACERT_OPT \
      $CLIENT_CERT_OPT \
      $CLIENT_KEY_OPT \
      --request POST \
      ${ALPHA_HOST}:8080/login \
      --data "${JSON}" #\
        | grep -o '(?<=accessJWT":")[^"]*'
  )

}

######
# get_token_graphql - get accessJWT token using GraphQL for Dgraph 20.03.1+
##########################
get_token_graphql() {
  GQL="{\"query\": \"mutation { login(userId: \\\"${USER}\\\" password: \\\"${PASSWORD}\\\") { response { accessJWT } } }\"}"
  ACCESS_JWT=$(
    echo /usr/bin/curl --silent \
      --header "Content-Type: application/json" \
      $CACERT_OPT \
      $CLIENT_CERT_OPT \
      $CLIENT_KEY_OPT \
      --request POST \
      ${ALPHA_HOST}:8080/admin \
      --data "${GQL}" \
        | grep -o '(?<=accessJWT":")[^"]*'
  )
}

######
# get_token - get accessJWT using GraphQL /agdmin or REST /login
#  params:
#    1: user (required)
#    2: password (required)
#  envvars:
#    ALPHA_HOST (default: localhost) - dns name or of dgraph alpha node
#    CACERT_PATH - path to dgraph root ca (e.g. ca.crt) if TLS is enabled
#    CLIENT_CERT_PATH - path to client cert (e.g. client.dgraphuser.crt) for client TLS
#    CLIENT_KEY_PATH - path to client cert (e.g. client.dgraphuser.key) for client TLS
##########################
get_token() {
  USER=${1}
  PASSWORD=${2}
  CACERT_PATH=${CACERT_PATH:-""}
  CLIENT_CERT_PATH=${CLIENT_CERT_PATH:-""}
  CLIENT_KEY_PATH=${CLIENT_KEY_PATH:-""}

  ALPHA_HOST=${ALPHA_HOST:-"localhost"}
  API_TYPE=${API_TYPE:-"graphql"}

  if [[ -z "$USER" || -z "$PASSWORD" ]]; then
    return 1
  fi

  if [[ "$API_TYPE" == "graphql" ]]; then
    get_token_graphql
  else
    get_token_rest
  fi
}

######
# backup - trigger binary backup GraphQL /agdmin or REST /login
#  params:
#    1: token (optional) - if ACL enabled pass token from get_token()
#  envvars:
#    BACKUP_DESTINATION (required) - filepath ("/path/to/backup"), s3://, or minio://
#    ALPHA_HOST (default: localhost) - dns name or of dgraph alpha node
#    MINIO_SECURE (default: false) - set to true if minio service supports https
#    FORCE_FULL (default: false) - set to true if forcing a full backup
#    CACERT_PATH - path to dgraph root ca (e.g. ca.crt) if TLS is enabled
#    CLIENT_CERT_PATH - path to client cert (e.g. client.dgraphuser.crt) for client TLS
#    CLIENT_KEY_PATH - path to client cert (e.g. client.dgraphuser.key) for client TLS
##########################
backup() {
  TOKEN=${1:-""}
  CACERT_PATH=${CACERT_PATH:-""}
  CLIENT_CERT_PATH=${CLIENT_CERT_PATH:-""}
  CLIENT_KEY_PATH=${CLIENT_KEY_PATH:-""}

  ALPHA_HOST=${ALPHA_HOST:-"localhost"}
  API_TYPE=${API_TYPE:-"graphql"}

  MINIO_SECURE=${MINIO_SECURE:-"false"}
  FORCE_FULL=${FORCE_FULL:-"false"}

  [[ -z "$BACKUP_DESTINATION" ]] && \
    { echo "'BACKUP_DESTINATION' is not set. Exiting" >&2; return 1; }

  if [[ -z "$TOKEN" ]]; then
    TOKEN_OPT=""
  else
    TOKEN_OPT="--header 'X-Dgraph-AccessToken: $TOKEN'"
  fi

  if [[ -z "$CACERT_PATH" ]]; then
    CACERT_OPT=""
  else
    CACERT_OPT="--cacert $CACERT_PATH"
  fi

  if [[ -z "$CLIENT_CERT_PATH" || -z "$CLIENT_KEY_PATH" ]]; then
    CLIENT_CERT_OPT=""
    CLIENT_KEY_OPT=""
  else
    CLIENT_CERT_OPT="--cert $CLIENT_CERT_PATH"
    CLIENT_KEY_OPT="--key $CLIENT_CERT_PATH"
  fi

  if [[ "$BACKUP_DESTINATION" =~ "^minio" ]]; then
    if [[ "$MINIO_SECURE" == "true" ]]; then
      BACKUP_DESTINATION="${BACKUP_DESTINATION}/dgraph_$(date +%Y%m%d)"
    else
      BACKUP_DESTINATION="${BACKUP_DESTINATION}/dgraph_$(date +%Y%m%d)?secure=false"
    fi
  fi

  if [[ "$API_TYPE" == "graphql" ]]; then
    backup_graphql
  else
    backup_rest
  fi

}


backup_rest() {
  URL_PATH="admin/backup"
  if [[ "$FORCE_FULL" == "true" ]]; then
    URL_PATH="$URL_PATH?force_full=true"
  fi

  echo /usr/bin/curl --silent \
    --header "${CONTENT_TYPE}" \
    $TOKEN_OPT \
    $CACERT_OPT \
    $CLIENT_CERT_OPT \
    $CLIENT_KEY_OPT \
    --request POST \
    ${ALPHA_HOST}:8080/$URL_PATH \
    --data "destination=$BACKUP_DESTINATION"
}

backup_graphql() {
  if [[ "$FORCE_FULL" == "true" ]]; then
    GQL="{\"query\": \"mutation { backup(input: {destination: \\\"${BACKUP_DESTINATION}\\\" forceFull: true }) { response { message code } } }\"}"
  else
    GQL="{\"query\": \"mutation { backup(input: {destination: \\\"${BACKUP_DESTINATION}\\\" }) { response { message code } } }\"}"
  fi

  echo /usr/bin/curl --silent \
    --header "Content-Type: application/json" \
    $TOKEN_OPT \
    $CACERT_OPT \
    $CLIENT_CERT_OPT \
    $CLIENT_KEY_OPT \
    --request POST \
    $ALPHA_HOST:8080/admin \
    --data "$GQL"
}


# main $@
