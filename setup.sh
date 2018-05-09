#!/bin/bash

source ./common.sh

sudo apt-add-repository -y ppa:git-core/ppa
sudo apt-get -qq update

# Fixing Locale
print_message "Fixing locale"
sudo locale-gen en_US.UTF-8
export LANGUAGE="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
sudo dpkg-reconfigure -p critical locales
echo -e 'LANGUAGE="en_US.UTF-8"\nLC_ALL="en_US.UTF-8"\n' | sudo bash -c 'tee >> /etc/environment'

if ! command -v nvm > /dev/null; then
	# Install nvm dependencies
	print_message "Installing nvm dependencies"
	sudo apt-get -qq -y install build-essential libssl-dev

	# Execute nvm installation script
	echo "Executing nvm installation script"
	curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.2/install.sh | bash

	# Set up nvm environment without restarting the shell
	echo "Setting nvm environment without restarting the shell"
	export NVM_DIR="${HOME}/.nvm"
	[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"
	[ -s "${NVM_DIR}/bash_completion" ] && . "${NVM_DIR}/bash_completion"

	if ! command -v node > /dev/null; then
		# Install node
		echo "Installing nodeJS"
		nvm install v8.11.1

		# Configure nvm to use version 8.11.1
		echo "Configuring nvm to use latest LTS node version"
		nvm use --lts
		nvm alias default 'lts/*'
	else
		echo "nodeJS already Installed"
	fi

	if ! command -v npm > /dev/null; then
		# Install the latest version of npm
		echo "Installing npm"
		npm install npm@latest -g
	else
		echo "NPM already Installed"
	fi
else
	echo "NVM already Installed"
fi

# Checking Docker Compose
if ! command -v docker-compose > /dev/null; then
	print_message "Installing Docker Compose"
	sudo curl -L https://github.com/docker/compose/releases/download/1.18.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
	sudo chmod +x /usr/local/bin/docker-compose
else
	print_message "Docker Composer already Installed"
fi

# Checking python v2
set +e
COUNT="$(python -V 2>&1 | grep -c 2.)"
if [ ${COUNT} -ne 1 ]
then
   sudo apt-get -qq install -y python-minimal
fi

# Checking Go
if ! command -v go > /dev/null; then
	print_message "Installing Go"
	sudo apt-get -qq install -y golang-go
else
	print_message "Go already Installed"
fi

# Checking ZIP
if ! command -v zip > /dev/null; then
	print_message "Installing ZIP"
	sudo apt-get -qq install -y zip
else
	print_message "ZIP already Installed"
fi

# Downloading Binaries
if ! command -v cryptogen > /dev/null; then
	downloadBinaries "1.1.0"
fi

# Checking Docker
if ! command -v docker > /dev/null; then
	print_message "Installing Docker"
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	sudo apt-get -qq update
	apt-cache policy docker-ce
	sudo apt-get -qq install -y docker-ce
	sudo usermod -a -G docker $USER
	newgrp docker
else
	print_message "Docker already Installed"
fi