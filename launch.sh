#!/bin/bash

# Exit on first error, print all commands.
set -e

# Including common functions
source ./common.sh

templatesFolder="templates"

composeTemplatesFolder="${templatesFolder}/docker-compose"
artifactsTemplatesFolder="${templatesFolder}/crypto"
scriptsTemplateFolder="${templatesFolder}/scripts"

ARCH=`uname -m`

: ${HOME_PATH:=${PWD}}
: ${TEMPLATES_CRYPTO_FOLDER:=${HOME_PATH}/${artifactsTemplatesFolder}}
: ${TEMPLATES_DOCKER_COMPOSE_FOLDER:=${HOME_PATH}/${composeTemplatesFolder}}
: ${TEMPLATES_SCRIPTS_FOLDER:=${HOME_PATH}/${scriptsTemplateFolder}}

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

# Org1 functions
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

function createConnectionProfileMain() {
    org=$ORG1

    ORDERER_CA_CERT=$(certToString "${GENERATED_CRYPTO_CONFIG_FOLDER}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/ca.crt")
    PEER0_CA_CERT=$(certToString "${GENERATED_CRYPTO_CONFIG_FOLDER}/peerOrganizations/${org}.${DOMAIN}/peers/peer0.${org}.${DOMAIN}/tls/ca.crt")
    PEER1_CA_CERT=$(certToString "${GENERATED_CRYPTO_CONFIG_FOLDER}/peerOrganizations/${org}.${DOMAIN}/peers/peer1.${org}.${DOMAIN}/tls/ca.crt")

    f=${GENERATED_DOCKER_COMPOSE_FOLDER}/connection.json

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${org}/g" -e "s/CHANNEL_NAME/${CHANNEL_NAME}/g" -e "s~\"ORDERER_CA_CERT\"~\"${ORDERER_CA_CERT}\"~" -e "s~\"PEER0_CA_CERT\"~\"${PEER0_CA_CERT}\"~" -e "s~\"PEER1_CA_CERT\"~\"${PEER1_CA_CERT}\"~" ${templatesFolder}/connection-template.json > ${f}
}

function createPeerAdminCardMain() {
    org=$ORG1

    MSP_PATH=${GENERATED_CRYPTO_CONFIG_FOLDER}/peerOrganizations/${org}.${DOMAIN}/users/Admin@${org}.${DOMAIN}/msp

    CERT=${MSP_PATH}/signcerts/Admin@${org}.${DOMAIN}-cert.pem
    PRIVATE_KEY=${MSP_PATH}/keystore/*_sk
    PEER_ADMIN_CARD=PeerAdmin@${org}

    if composer card list --card ${PEER_ADMIN_CARD} > /dev/null; then
        composer card delete --card ${PEER_ADMIN_CARD}
    fi

    rm -rf ${GENERATED_DOCKER_COMPOSE_FOLDER}/${PEER_ADMIN_CARD}.card
    rm -rf ~/.composer/cards/${PEER_ADMIN_CARD}
    rm -rf ~/.composer/client-data/${PEER_ADMIN_CARD}

    echo "Creating connection profile for PeerAdmin card"
    createConnectionProfileMain

    echo "Creating PeerAdmin Card"
    composer card create -p ${GENERATED_DOCKER_COMPOSE_FOLDER}/connection.json -u PeerAdmin -c ${CERT} -k ${PRIVATE_KEY} -r PeerAdmin -r ChannelAdmin -f ${GENERATED_DOCKER_COMPOSE_FOLDER}/${PEER_ADMIN_CARD}.card

    echo "Importing PeerAdmin Card"
    composer card import --file ${GENERATED_DOCKER_COMPOSE_FOLDER}/${PEER_ADMIN_CARD}.card
}


# Org2 functions
function generateOrg2Artifacts() {
    cryptogen generate --config=./${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/crypto-config.yaml --output=${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}

    export FABRIC_CFG_PATH=${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}

    configtxgen -printOrg ${ORG2}MSP > ${GENERATED_ORG2_ARTIFACTS_FOLDER}/${ORG2}.json

    if [ "${REMOTE}" != "true" ]; then
        cp ${GENERATED_ORG2_ARTIFACTS_FOLDER}/${ORG2}.json ${GENERATED_ARTIFACTS_FOLDER}/${ORG2}.json
    fi
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

function generateScriptsOrg2() {
    for script in cli-1 cli-2
    do
        template=${TEMPLATES_SCRIPTS_FOLDER}/${script}.sh
        f=${GENERATED_ORG2_ARTIFACTS_FOLDER}/${script}.sh
        sed -e "s/_DOMAIN_/${DOMAIN}/g" -e "s/_ORG_/${ORG2}/g" -e "s/_CHANNEL_NAME_/${CHANNEL_NAME}/g" ${template} > ${f}
    done
}

function registerOrg2() {
    docker exec -i cli.${ORG1}.${DOMAIN} bash < ${GENERATED_ORG2_ARTIFACTS_FOLDER}/cli-1.sh
}

function startOrg2() {
    ARCH=${ARCH} docker-compose -f "${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/docker-compose.yaml" down
    ARCH=${ARCH} docker-compose -f "${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/docker-compose.yaml" up -d

    echo "sleeping for ${FABRIC_START_TIMEOUT} seconds to wait for fabric to complete start up"
    sleep ${FABRIC_START_TIMEOUT}
}

function createConnectionProfileOrg2() {
    org=$ORG2

    ORDERER_CA_CERT=$(certToString "${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}/ordererOrganizations/${DOMAIN}/orderers/orderer.${DOMAIN}/tls/ca.crt")
    PEER0_CA_CERT=$(certToString "${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}/peerOrganizations/${org}.${DOMAIN}/peers/peer0.${org}.${DOMAIN}/tls/ca.crt")
    PEER1_CA_CERT=$(certToString "${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}/peerOrganizations/${org}.${DOMAIN}/peers/peer1.${org}.${DOMAIN}/tls/ca.crt")

    f=${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/connection.json

    sed -e "s/DOMAIN/${DOMAIN}/g" -e "s/ORG/${org}/g" -e "s/CHANNEL_NAME/${CHANNEL_NAME}/g" -e "s~\"ORDERER_CA_CERT\"~\"${ORDERER_CA_CERT}\"~" -e "s~\"PEER0_CA_CERT\"~\"${PEER0_CA_CERT}\"~" -e "s~\"PEER1_CA_CERT\"~\"${PEER1_CA_CERT}\"~" ${templatesFolder}/connection-template.json > ${f}
}

function createPeerAdminCardOrg2() {
    org=$ORG2

    MSP_PATH=${GENERATED_ORG2_CRYPTO_CONFIG_FOLDER}/peerOrganizations/${org}.${DOMAIN}/users/Admin@${org}.${DOMAIN}/msp

    CERT=${MSP_PATH}/signcerts/Admin@${org}.${DOMAIN}-cert.pem
    PRIVATE_KEY=${MSP_PATH}/keystore/*_sk
    PEER_ADMIN_CARD=PeerAdmin@${org}

    echo "Deleting ${PEER_ADMIN_CARD} card if already exist"
    removeCard ${PEER_ADMIN_CARD}

    echo "Creating connection profile for PeerAdmin card"
    createConnectionProfileOrg2

    echo "Creating PeerAdmin Card"
    composer card create -p ${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/connection.json -u PeerAdmin -c ${CERT} -k ${PRIVATE_KEY} -r PeerAdmin -r ChannelAdmin -f ${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/${PEER_ADMIN_CARD}.card

    echo "Importing PeerAdmin Card"
    composer card import --file ${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}/${PEER_ADMIN_CARD}.card
}


# Common functions
function removeArtifacts() {
    rm -rf ${1}
    [[ -d ${1} ]] || mkdir ${1}
    [[ -d ${1}/artifacts ]] || mkdir ${1}/artifacts
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

    docker exec ${peer}.${org}.${DOMAIN} peer channel fetch 0 ${CHANNEL_NAME}.block -o orderer.${DOMAIN}:7050 -c ${CHANNEL_NAME} --tls --cafile /etc/hyperledger/crypto/orderer/tls/ca.crt
    docker exec ${peer}.${org}.${DOMAIN} peer channel join -b ${CHANNEL_NAME}.block
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

function certToString() {
    _temp=$(<$1)
    echo "${_temp//$'\n'/\\\\n}"
}

function installNetwork() {
    org=${1}
    compose_folder=${2}
    bna=${3}
    network=${4}

    PEER_ADMIN_CARD=PeerAdmin@${org}
    NETOWRK_ADMIN_CARD=admin@${network}

    echo "Installing Business Network"
    composer network install --card ${PEER_ADMIN_CARD} --archiveFile ${bna}

    echo "Starting Business Network"
    composer network start --card ${PEER_ADMIN_CARD} --networkName ${network} --networkVersion 0.0.1 --networkAdmin admin --networkAdminEnrollSecret adminpw --file ${compose_folder}/${NETOWRK_ADMIN_CARD}.card

    echo "Deleting ${NETOWRK_ADMIN_CARD} card if already exist"
    removeCard ${NETOWRK_ADMIN_CARD}

    echo "Import Business Network Admin Card"
    composer card import --file ${compose_folder}/${NETOWRK_ADMIN_CARD}.card

    echo "Ping Business Network to check status"
    composer network ping --card ${NETOWRK_ADMIN_CARD}
}

function removeCard() {
    card=${1}

    if composer card list --card ${card} > /dev/null; then
        composer card delete --card ${card}
    fi

    rm -rf ~/.composer/cards/${card}
    rm -rf ~/.composer/client-data/${card}
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
elif [ "${MODE}" == "generate-org2" ]; then
    echo "Generating artifacts for org2"
    removeArtifacts ${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER}
    generateConfigtxOrg2
    generateCryptoConfigOrg2
    generateOrg2Artifacts
    downloadArtifacts
    generateScriptsOrg2
elif [ "${MODE}" == "up-main" ]; then
    echo "Starting main org"
    generateDockerComposeMain
    startMainOrg
    createChannel
    joinChannel ${ORG1} "peer0"
    fetchAndJoinChannel ${ORG1} "peer1"
elif [ "${MODE}" == "up-org2" ]; then
    echo "Starting main org"
    registerOrg2
    generateDockerComposeOrg2
    startOrg2
    fetchAndJoinChannel ${ORG2} "peer0"
    fetchAndJoinChannel ${ORG2} "peer1"
elif [ "${MODE}" == "down-main" ]; then
    echo "Pending"
elif [ "${MODE}" == "down-org2" ]; then
    echo "Pending"
elif [ "${MODE}" == "peeradmin-main" ]; then
    createPeerAdminCardMain
    installNetwork ${ORG1} ${GENERATED_DOCKER_COMPOSE_FOLDER} export_import@0.0.1.bna export_import
elif [ "${MODE}" == "peeradmin-org2" ]; then
    createPeerAdminCardOrg2
    installNetwork ${ORG2} ${GENERATED_DOCKER_COMPOSE_ORG2_FOLDER} export_import@0.0.1.bna export_import
else
  echo "Please provide a valid argument!"
  exit 1
fi
