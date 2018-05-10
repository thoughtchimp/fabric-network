peer channel fetch 0 _CHANNEL_NAME_.block -o orderer._DOMAIN_:7050 -c _CHANNEL_NAME_ --tls --cafile /etc/hyperledger/crypto/ordererOrganizations/_DOMAIN_/orderers/orderer._DOMAIN_/msp/tlscacerts/tlsca._DOMAIN_-cert.pem

peer channel join -b mychannel.block

export CORE_PEER_TLS_ROOTCERT_FILE=/etc/hyperledger/_ORG_/peers/peer1._ORG_._DOMAIN_/tls/ca.crt
export CORE_PEER_ADDRESS=peer1._ORG_._DOMAIN_:7051

peer channel join -b mychannel.block