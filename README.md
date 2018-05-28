Multiple Organizations Setup - Fabric Network
======

Hyperledger Fabric Network is an easy way to deploy [Hyperledger Fabric](https://www.hyperledger.org/projects/fabric) on development or production environment.


## Clone Repository
Clone this branch to get the latest code using the following command.

* `git clone https://github.com/thoughtchimp/hyperledger-network -b multi-orgs`
* `cd hyperledger-network`


## Install Prerequisites
Hyperledger Fabric has a few dependencies like Docker, Docker Compose, Fabric Binaries and so on. You can use the below command to get all prerequisites installed in one go. You can skip this step if you have already done this before.

`. ./setup.sh`

## Building the Network
Building the network is divided into three parts, it is recommended that you follow the instructions in the below order. If you want to create a network with only single Organisation, you can **skip** the commands for Org2-

### 1. Bootstrapping Org, Orderer, CLI and CA
- Start the Main Org (Org1) with Orderer `./launch.sh -m generate-main && ./launch.sh -m up-main`
* Start Org2 `./launch.sh -m generate-org2 && ./launch.sh -m up-org2`

### 2. Creating PeerAdmin
* Main Org `./launch.sh -m peeradmin-main`
* For Org2 `./launch.sh -m peeradmin-org2`

### 3. Installing the Network with sample .bna
* Main Org `./launch.sh -m installnetwork-main`
* For Org2 `./launch.sh -m installnetwork-org2`

## Bringing the Network Down
* Main Org `./launch.sh -m down-main`
* For Org2 `./launch.sh -m down-org2`

## Issues
This repo is still **under developement**, if you encounter any bugs, we would be glad to solve it together. So don't hesitate reporting [issues](https://github.com/thoughtchimp/fabric-network/issues)