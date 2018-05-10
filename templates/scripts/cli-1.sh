#!/bin/bash

if ! command -v jq > /dev/null; then
    apt -qq update && apt -qq install -y jq
fi

export ORDERER_CA=/etc/hyperledger/crypto/ordererOrganizations/_DOMAIN_/orderers/orderer._DOMAIN_/msp/tlscacerts/tlsca._DOMAIN_-cert.pem && export CHANNEL_NAME=_CHANNEL_NAME_

echo ${ORDERER_CA} && echo ${CHANNEL_NAME}

peer channel fetch config config_block.pb -o orderer._DOMAIN_:7050 -c ${CHANNEL_NAME} --tls --cafile ${ORDERER_CA}

configtxlator proto_decode --input config_block.pb --type common.Block | jq .data.data[0].payload.data.config > config.json

jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"_ORG_MSP":.[1]}}}}}' config.json /etc/hyperledger/artifacts/_ORG_.json > modified_config.json

configtxlator proto_encode --input config.json --type common.Config --output config.pb

configtxlator proto_encode --input modified_config.json --type common.Config --output modified_config.pb

configtxlator compute_update --channel_id ${CHANNEL_NAME} --original config.pb --updated modified_config.pb --output _ORG__update.pb

configtxlator proto_decode --input _ORG__update.pb --type common.ConfigUpdate | jq . > _ORG__update.json

echo '{"payload":{"header":{"channel_header":{"channel_id":"_CHANNEL_NAME_", "type":2}},"data":{"config_update":'$(cat _ORG__update.json)'}}}' | jq . > _ORG__update_in_envelope.json

configtxlator proto_encode --input _ORG__update_in_envelope.json --type common.Envelope --output _ORG__update_in_envelope.pb

peer channel signconfigtx -f _ORG__update_in_envelope.pb

peer channel update -f _ORG__update_in_envelope.pb -c ${CHANNEL_NAME} -o orderer._DOMAIN_:7050 --tls --cafile ${ORDERER_CA}