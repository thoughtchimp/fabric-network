#!/bin/bash

# Exit on first error, print all commands.
set -e

# Including common functions
source ./common.sh

composeTemplatesFolder="templates/docker-compose"
artifactsTemplatesFolder="templates/crypto"

ARCH=`uname -m`

: ${HOME_PATH:=${PWD}}
: ${TEMPLATES_CRYPTO_FOLDER:=${HOME_PATH}/${artifactsTemplatesFolder}}
: ${TEMPLATES_DOCKER_COMPOSE_FOLDER:=${HOME_PATH}/${composeTemplatesFolder}}
: ${GENERATED_DOCKER_COMPOSE_FOLDER:=./composer}
: ${GENERATED_ARTIFACTS_FOLDER:=${GENERATED_DOCKER_COMPOSE_FOLDER}/artifacts}
: ${GENERATED_CRYPTO_CONFIG_FOLDER:=${GENERATED_DOCKER_COMPOSE_FOLDER}/crypto-config}

: ${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER:=./org2-composer}
: ${GENERATED_ORG2_ARTIFACTS_FOLDER:=${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/artifacts}
: ${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER:=${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/crypto-config}

: ${CHANNEL_NAME:="mychannel"}
: ${DOMAIN:="example.com"}
: ${ORG1:="a"}
: ${ORG2:="b"}

DEFAULT_CLI_EXTRA_HOSTS=""
DEFAULT_PEER_EXTRA_HOSTS=""

if [ -z ${FABRIC_START_TIMEOUT+x} ]; then
    export FABRIC_START_TIMEOUT=15
else
    re='^[0-9]+$'
    if ! [[ ${FABRIC_START_TIMEOUT} =~ ${re} ]] ; then
        echo "FABRIC_START_TIMEOUT: Not a number" >&2; exit 1
    fi
fi

function removeArtifacts() {
    rm -rf ${1}
    [[ -d ${1} ]] || mkdir ${1}
    [[ -d ${1}/artifacts ]] || mkdir ${1}/artifacts
}

function generateMainOrgArtifacts() {
    cryptogen generate --config=./${GENERATED_DOCKER_COMPOSE_FOLDER}/crypto-config.yaml --output=${GENERATED_CRYPTO_CONFIG_FOLDER}

    export FABRIC_CFG_PATH=${GENERATED_DOCKER_COMPOSE_FOLDER}

    configtxgen -profile OrdererGenesis -outputBlock ./${GENERATED_ARTIFACTS_FOLDER}/genesis.block

    configtxgen -profile ${CHANNEL_NAME} -outputCreateChannelTx ./${GENERATED_ARTIFACTS_FOLDER}/channel.tx -channelID ${CHANNEL_NAME}
}

function generateDockerComposeMain() {
    echo "Creating docker-compose.yaml file with ${DOMAIN}, ${ORG1}"

    compose_template=${TEMPLATES_DOCKER_COMPOSE_FOLDER}/docker-compose-main-template.yaml

    f="${GENERATED_DOCKER_COMPOSE_FOLDER}/docker-compose.yaml"

    cli_extra_hosts=${DEFAULT_CLI_EXTRA_HOSTS}
    peer_extra_hosts=${DEFAULT_PEER_EXTRA_HOSTS}
    ca_secret_key=$(findCASecretKey ${GENERATED_CRYPTO_CONFIG_FOLDER} ${ORG1})

    if [[ -z "${ca_secret_key}" ]]; then
       print_error "Secret key was not found for ${ORG1}'s CA, please fix and retry"
       exit
    fi

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${ORG1}/g" -e "s/CLI_EXTRA_HOSTS/${cli_extra_hosts}/g" -e "s/PEER_EXTRA_HOSTS/${peer_extra_hosts}/g" -e "s/CA_SECRET_KEY/${ca_secret_key}/g" ${compose_template} | awk '{gsub(/\[newline\]/, "\n")}1' > ${f}
}

function generateConfigtxMain() {
    echo "Creating configx.yaml file with ${DOMAIN}, ${ORG1}"

    compose_template=${TEMPLATES_CRYPTO_FOLDER}/configtx-main-template.yaml

    f="${GENERATED_DOCKER_COMPOSE_FOLDER}/configtx.yaml"

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${ORG1}/g" -e "s/CHANNEL_NAME/${CHANNEL_NAME}/g" ${compose_template} > ${f}
}

function generateCryptoConfigMain() {
    echo "Creating crypto-config.yaml file with ${DOMAIN}, ${ORG1}"

    compose_template=${TEMPLATES_CRYPTO_FOLDER}/crypto-config-main-template.yaml

    f="${GENERATED_DOCKER_COMPOSE_FOLDER}/crypto-config.yaml"

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${ORG1}/g" ${compose_template} > ${f}
}

function startMainOrg() {
    ARCH=${ARCH} docker-compose -f "${GENERATED_DOCKER_COMPOSE_FOLDER}/docker-compose.yaml" down
    ARCH=${ARCH} docker-compose -f "${GENERATED_DOCKER_COMPOSE_FOLDER}/docker-compose.yaml" up -d

    echo "sleeping for ${FABRIC_START_TIMEOUT} seconds to wait for fabric to complete start up"
    sleep ${FABRIC_START_TIMEOUT}
}

function generateOrg2Artifacts() {
    cryptogen generate --config=./${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/crypto-config.yaml --output=${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}

    export FABRIC_CFG_PATH=${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}

    configtxgen -printOrg ${ORG2}MSP > ./${GENERATED_ORG2_ARTIFACTS_FOLDER}/org3.json
}

function generateDockerComposeOrg2() {
    echo "Creating docker-compose.yaml file with ${DOMAIN}, ${ORG2}"

    compose_template=${TEMPLATES_DOCKER_COMPOSE_FOLDER}/docker-compose-org2-template.yaml

    f="${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/docker-compose.yaml"

    cli_extra_hosts=${DEFAULT_CLI_EXTRA_HOSTS}
    peer_extra_hosts=${DEFAULT_PEER_EXTRA_HOSTS}
    ca_secret_key=$(findCASecretKey ${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER} ${ORG2})

    if [[ -z "${ca_secret_key}" ]]; then
       print_error "Secret key was not found for ${ORG2}'s CA, please fix and retry"
       exit
    fi

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${ORG2}/g" -e "s/CLI_EXTRA_HOSTS/${cli_extra_hosts}/g" -e "s/PEER_EXTRA_HOSTS/${peer_extra_hosts}/g" -e "s/ORG1/${ORG1}/g" -e "s/CA_SECRET_KEY/${ca_secret_key}/g" ${compose_template} | awk '{gsub(/\[newline\]/, "\n")}1' > ${f}
}

function generateConfigtxOrg2() {
    echo "Creating configx.yaml file with ${DOMAIN}, ${ORG2}"

    compose_template=${TEMPLATES_CRYPTO_FOLDER}/configtx-org2-template.yaml

    f="${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/configtx.yaml"

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${ORG2}/g" -e "s/CHANNEL_NAME/${CHANNEL_NAME}/g" ${compose_template} > ${f}
}

function generateCryptoConfigOrg2() {
    echo "Creating crypto-config.yaml file with ${DOMAIN}, ${ORG2}"

    compose_template=${TEMPLATES_CRYPTO_FOLDER}/crypto-config-org2-template.yaml

    f="${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/crypto-config.yaml"

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${ORG2}/g" ${compose_template} > ${f}
}

function startOrg2() {
    ARCH=${ARCH} docker-compose -f "${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/docker-compose.yaml" down
    ARCH=${ARCH} docker-compose -f "${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/docker-compose.yaml" up -d

    echo "sleeping for ${FABRIC_START_TIMEOUT} seconds to wait for fabric to complete start up"
    sleep ${FABRIC_START_TIMEOUT}
}

function findCASecretKey() {
    echo `find ${1}/peerOrganizations/${2}.${DOMAIN}/ca -type f -name "*_sk" 2>/dev/null | sed "s/.*\///"`
}

function createChannel() {
    docker exec peer0.${ORG1}.${DOMAIN} peer channel create -o orderer.${DOMAIN}:7050 -c ${CHANNEL_NAME} -f /etc/hyperledger/artifacts/channel.tx --tls --cafile /etc/hyperledger/crypto/orderer/tls/ca.crt
}

function fetchAndJoinChannel() {
    org=$1
    peer=$2

    docker exec ${peer}.${org}.${DOMAIN} peer channel fetch config -o orderer.${DOMAIN}:7050 -c ${CHANNEL_NAME} --tls --cafile /etc/hyperledger/crypto/orderer/tls/ca.crt
    docker exec ${peer}.${org}.${DOMAIN} peer channel join -b ${CHANNEL_NAME}_config.block
}

function joinChannel() {
    org=$1
    peer=$2

    docker exec ${peer}.${org}.${DOMAIN} peer channel join -b ${CHANNEL_NAME}.block
}

function getRemoteAddresses() {
    IP_ORDERER=$(get_input "$IP_ORDERER" "Enter Orderer IP: " "127.0.0.1")
    IP1=$(get_input "$IP1" "Enter Org1 IP: " "127.0.0.1")
    IP2=$(get_input "$IP2" "Enter Org2 IP: " "127.0.0.1")
    DEFAULT_PEER_EXTRA_HOSTS="extra_hosts:[newline]      - orderer.${DOMAIN}:${IP_ORDERER}"
    DEFAULT_CLI_EXTRA_HOSTS="extra_hosts:[newline]      - orderer.${DOMAIN}:${IP_ORDERER}"
}

function downloadArtifacts() {
    if [ "${REMOTE}" == "true" ]; then
        echo "Download from other machines"
    else
        echo "Copying artifacts from compose directory"
        cp -r ${GENERATED_ARTIFACTS_FOLDER}/* ${GENERATED_ORG2_ARTIFACTS_FOLDER}/
        cp -r ${GENERATED_CRYPTO_CONFIG_FOLDER}/peerOrganizations/${ORG1}.${DOMAIN} ${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}/peerOrganizations
        cp -r ${GENERATED_CRYPTO_CONFIG_FOLDER}/ordererOrganizations ${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}
    fi
}

# Parsing commandline args
while getopts "h?m:r" opt; do
    case "${opt}" in
        h|\?)
        printHelp
        exit 0
        ;;
        m)  MODE=$OPTARG
        ;;
        r)  REMOTE="true"
        ;;
    esac
done

if [ "${REMOTE}" == "true" ]; then
    getRemoteAddresses
fi

if [ "${MODE}" == "generate-main" ]; then
    echo "Generating artifacts for main org"
    removeArtifacts ${GENERATED_DOCKER_COMPOSE_FOLDER}
    generateConfigtxMain
    generateCryptoConfigMain
    generateMainOrgArtifacts
    generateDockerComposeMain # Temp
elif [ "${MODE}" == "generate-org2" ]; then
    echo "Generating artifacts for org2"
    removeArtifacts ${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}
    generateConfigtxOrg2
    generateCryptoConfigOrg2
    generateOrg2Artifacts
    downloadArtifacts
    generateDockerComposeOrg2 # Temp
elif [ "${MODE}" == "up-main" ]; then
    echo "Starting main org"
    generateDockerComposeMain
    startMainOrg
    createChannel
    joinChannel ${ORG1} "peer0"
    fetchAndJoinChannel ${ORG1} "peer1"
elif [ "${MODE}" == "up-org2" ]; then
    echo "Starting main org"
    generateDockerComposeOrg2
    startOrg2
    fetchAndJoinChannel ${ORG1} "peer0"
    fetchAndJoinChannel ${ORG1} "peer1"
    echo "Pending"
elif [ "${MODE}" == "down-main" ]; then
    echo "Pending"
elif [ "${MODE}" == "down-org2" ]; then
    echo "Pending"
else
  echo "Please provide a valid argument!"
  exit 1
fi
