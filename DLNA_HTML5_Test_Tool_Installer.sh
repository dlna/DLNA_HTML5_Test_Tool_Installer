#!/bin/bash

# Load and saved config
CONFIG=$HOME/.htt_installer/config
if [ -e $CONFIG ]; then
	source $CONFIG
fi

VERSION=${VERSION:=Release_2014.09.31}
GITHUB_USER=${GITHUB_USER:=dlna}
SERVICE_USER=${SERVICE_USER:=dhtt}
WPT_DIR=${WPT_DIR:=/usr/local/web-platform-test}
WPT_RESULTS_DIR=${WPT_RESULTS_DIR:=/var/www/html/upload}
IFACE_INET=${IFACE_INET:=eth0}
IFACE_TEST=${IFACE_TEST:=eth1}

INSTALL_DRM_CONTENT=${INSTALL_DRM_CONTENT:=${DRM_CONTENT:=0}}
INSTALL_WPT=${INSTALL_WPT:=1}
INSTALL_WPT_RESULTS=${INSTALL_WPT_RESULTS:=1}
INSTALL_NETWORK=${INSTALL_NETWORK:=1}
INSTALL_ROUTER=${INSTALL_ROUTER:=1}

# Script statics
SCRIPT=$(basename ${BASH_SOURCE[0]})
SCRIPT_VERSION="1.0.1"

TEMP_DIR=$(mktemp --directory)

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
WARN=$(tput setaf 3)
NC=$(tput sgr0)
BOLD=$(tput bold)
REV=$(tput smso)

S3_DRM_DIR="s3://content.dlna.org/DRM Content/Staging/"

# Some support functions
function error()
{
	echo "${RED}$*${NC}" >&2
	cleanup
	exit 1
}

function abort()
{
	error "Abort."
}

function cleanup()
{
	rm -fr $TEMP_DIR
}

function msg()
{
	echo "${GREEN}$*${NC}"
}

function warn()
{
	echo "${WARN}$*${NC}"
}

function usage()
{
  echo "Help documentation for ${BOLD}${SCRIPT}${NC}."
  echo "${BOLD}$SCRIPT${NC} [OPTION] "
  echo "Command line switches are optional. The following switches are recognized."
  echo "${REV}-u <user>${NC}  Sets the Github user account to grab the repositories from. Default is ${BOLD}dlna${NC}."
  echo "${REV}-r <tag>${NC}   Sets version to download. For the latest version use ${BOLD}master${NC}. Default is ${BOLD}${VERSION}${NC}."
  echo "${REV}-d${NC}         Download the DRM test content, requires access to DLNA Test Content on Amazon S3"
  echo "${REV}-h${NC}         Displays this help message. No further functions are performed."
  echo "${REV}-v${NC}         Displays the installer script version. No further functions are performed."
  echo "${REV}-y${NC}         Answer 'yes' to any applicable questions from the installer. For use in automated setup, not recommended for normal use."
  echo "Example: ${BOLD}${SCRIPT} -u ${GITHUB_USER} -r ${VERSION}${NC}"
  exit 0
}

function git-update()
{
	DIR=$1
	REPO=$2
	if [ -e $DIR ]; then 
		msg "### Updating ${REPO} version ${VERSION} from ${GITHUB_USER}"
		cd $DIR
		# Add the new remote if needed 
		git remote show | grep ${GITHUB_USER}  > /dev/null || git remote add ${GITHUB_USER} "https://github.com/${GITHUB_USER}/${REPO}.git" || abort
		git fetch ${GITHUB_USER} || abort
		git tag | grep $VERSION > /dev/null
		if [ $? -eq 0 ]; then 
			git checkout $VERSION || abort
		else
			git config user.name "DLNA HTML5 Test Tool Installer"
			git config user.email "htt@dlna.org"
			git merge ${GITHUB_USER}/$VERSION -m "Merge remote-tracking branch '${GITHUB_USER}/$VERSION'"
		fi
	else
		msg "### Installing ${REPO} version ${VERSION} from ${GITHUB_USER}"
		git clone --origin ${GITHUB_USER} --branch $VERSION "https://github.com/${GITHUB_USER}/${REPO}.git" $DIR || abort
	fi
	if [ -e $DIR/.gitmodules ]; then
		cd $DIR
		git submodule update --init --recursive
	fi
}

function cp_net()
{
	IN=$1
	OUT=$2

	cat $IN |
		sed s/eth0/IFACE_INET/ |
		sed s/eth1/IFACE_TEST/ |
		sed s/IFACE_INET/$IFACE_INET/ |
		sed s/IFACE_TEST/$IFACE_TEST/ > $OUT
}

msg "DLNA HTML5 Test Tool Installer"
msg "=============================="
msg ""

# Test for pre-requisites 
if [ "$(id -u)" != "0" ]; then
	# This is not ideal but will do for a first version
	error "This script must be run as root" 
fi

# Check for support OS
source /etc/lsb-release

if [ "$DISTRIB_ID" != "Ubuntu" -o \( "$DISTRIB_RELEASE" != "14.04" -a "$DISTRIB_RELEASE" != "16.04" \) ]; then
	# This is not ideal but will do for a first version
	error "This script only supports Ubuntu 14.04, found $DISTRIB_ID $DISTRIB_RELEASE"
fi

# NOTE: This requires GNU getopt.
TEMP=$(getopt -o u:r:hvdy --long user:,revision:,version,help,yes,drm-content,disable-network -- "$@")

if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi

# Note the quotes around `$TEMP': they are essential!
eval set -- "$TEMP"

# Parse command line
FORCE_YES=0
while true; do
	case "$1" in
		-u | --user)
			GITHUB_USER=$2
			shift 2 ;;
		-r | --revision)
			VERSION=$2
			shift 2 ;;
		-h | --help)  # show help
			usage
			;;
		-v | --version)  # show version
			msg "$SCRIPT v$SCRIPT_VERSION"
			exit 0
			shift ;;
		-d | --drm-content)  # Download DRM content
			INSTALL_DRM_CONTENT=1
			shift ;;
		-y | --yes)  # Don't confirm
			FORCE_YES=1
			shift ;;
		--disable-network )
			INSTALL_NETWORK=0;
			shift ;;
		-- ) shift; break ;;
		* ) break ;;
	esac
done

if [ 0 == ${FORCE_YES} ]; then
	echo -n "Install Version $VERSION from $GITHUB_USER? [y/N] "
	read CONFIRM
	if [ "y" != "$CONFIRM" -a "Y" != "$CONFIRM" ]; then
		abort
	fi
fi

# Check for ethernet adapters
if [ 1 -eq ${INSTALL_NETWORK} ]; then
	CONFIG_IFACE=0
	ifconfig $IFACE_INET > /dev/null 2>&1 > /dev/null || CONFIG_IFACE=1
	ifconfig $IFACE_TEST > /dev/null 2>&1 > /dev/null || CONFIG_IFACE=1

	if [ 1 == $CONFIG_IFACE ]; then
		msg "### Configure network interfaces"

		ifaces=($(ifconfig -a | grep "encap\|mtu" | awk -F'[ :]' {'print $1'} | grep -v lo))

		printf "\nSelect Test Network Interface:\n"
		for i in "${!ifaces[@]}"; do
			printf "\t%s)\t%s\t" "$i" "${ifaces[$i]}"
			printf "$(ifconfig ${ifaces[$i]} | grep 'inet addr' | awk {'print $2'} | sed 's/addr://g')\n"
		done
		read -r -p "> " tlanq
		IFACE_INET=(${ifaces[tlanq]})

		printf "\nSelect Internet Interface:\n"
		for i in "${!ifaces[@]}"; do
			printf "\t%s)\t%s\t" "$i" "${ifaces[$i]}"
			printf "$(ifconfig ${ifaces[$i]} | grep 'inet addr' | awk {'print $2'} | sed 's/addr://g')\n"
		done
		read -r -p "> " inetq
		IFACE_TEST=(${ifaces[inetq]})
	fi

	if [ "$IFACE_INET" == "$IFACE_TEST" ]; then
		error "Can not use the same interface for both Internet and Test networks"
	fi
fi

# Check we are setup for downloading the DRM content
if [ 1 -eq ${INSTALL_DRM_CONTENT} ]; then
	which smbcmd || apt-get install -y s3cmd
	if [ ! -e ${HOME}/.s3cfg ]; then
		msg ">>> Please enter your Amazon S3 credentials to enable download of DRM content"
		s3cmd --configure
	fi
fi

# OS specific settings
case $DISTRIB_RELEASE in
14.04)
	PHP=php5
	PHP_CONF=/etc/php5
	;;
16.04)
	PHP=php
	PHP_CONF=/etc/php/7.0
	;;
*)
	error "Unknown OS version ($DISTRIB_RELEASE)"
	;;
esac

# TODO: Only install the things required for the features we are installing
msg "### Installing pre-requisits"
apt-get update -y
apt-get install -y ssh git bind9 isc-dhcp-server python python-html5lib curl apache2 ${PHP} ${PHP}-dev libapache2-mod-${PHP} pkg-config libzmq-dev || abort

if [ 1 -eq ${INSTALL_WPT} -o 1 -eq ${INSTALL_WPT_RESULTS} ]; then 
	adduser --system --quiet $SERVICE_USER
	addgroup --system --quiet $SERVICE_USER
	adduser --quiet $SERVICE_USER $SERVICE_USER
fi

if [ 1 -eq ${INSTALL_WPT} ]; then 
	git-update $WPT_DIR web-platform-tests
	python tools/scripts/manifest.py
	cp config.default.json config.json
	sed 's!"bind_hostname": true}!"bind_hostname"\: true,"test_tool_endpoint": "http://web-platform.test/upload/api.php/"}!' -i config.json

	if [ 1 -eq ${INSTALL_DRM_CONTENT} ]; then
		if [ -e ${WPT_DIR}/drm-tests ]; then
			mkdir -p ${WPT_DIR}/drm-tests/content
			s3cmd sync "${S3_DRM_DIR}" ${WPT_DIR}/drm-tests/content/
		else
			warn "Warning: web-platform-test version ${VERSION} from ${GITHUB_USER} does not support DRM testing"
		fi
	fi
fi

if [ 1 -eq ${INSTALL_WPT_RESULTS} ]; then 
	git-update $WPT_RESULTS_DIR WPT_Results_Collection_Server

	if [ -e $WPT_RESULTS_DIR/composer.json ]; then
		apt-get install -y libphp-pclzip unzip

		if [ ! -x /usr/local/bin/composer ]; then 
			msg "### Installing composer"
			cd $TEMP_DIR
			curl -sS https://getcomposer.org/installer | php || abort
			mv composer.phar /usr/local/bin/composer || abort
		fi
		
		if [ ! -e ${PHP_CONF}/apache2/conf.d/99-zmq.ini ]; then 
			msg "### Installing PHP ZQM extension"
			cd $TEMP_DIR
			git clone git://github.com/mkoppanen/php-zmq.git || abort
			cd php-zmq || abort
			phpize || abort
			./configure || abort
			make || abort
			make install || abort
			echo extension=zmq.so | tee ${PHP_CONF}/apache2/conf.d/99-zmq.ini || abort
			echo extension=zmq.so | tee ${PHP_CONF}/cli/conf.d/99-zmq.ini || abort
		fi
		
		cd $WPT_RESULTS_DIR
		composer install || abort

		if [ -e $WPT_RESULTS_DIR/Notifier ]; then 
			msg "### Installing Notifier"
			cd $WPT_RESULTS_DIR/Notifier
			composer install || abort
		fi

		if [ -e $WPT_RESULTS_DIR/js/DrmViewModel.js ]; then 
			# The DRM login code requires the PHP SOAP client
			apt-get install -y php-soap
		fi
	fi

	if [ ! -e $WPT_RESULTS_DIR/logs ]; then
		mkdir $WPT_RESULTS_DIR/logs || abort
		chown www-data:www-data $WPT_RESULTS_DIR/logs || abort
	fi

	if [ ! -e $WPT_RESULTS_DIR/data ]; then
		mkdir $WPT_RESULTS_DIR/data || abort
		chown www-data:www-data $WPT_RESULTS_DIR/data || abort
	fi

	sed -E -i "s/upload_max_filesize *= *[0-9]+M/upload_max_filesize = 200M/" ${PHP_CONF}/apache2/php.ini 
	sed -E -i "s/post_max_size *= *[0-9]+M/post_max_size = 200M/" ${PHP_CONF}/apache2/php.ini 
	sed -E -i "s/memory_limit *= *[0-9]+M/memory_limit = 512M/" ${PHP_CONF}/apache2/php.ini 
	
	service apache2 restart
fi

msg "### Installing HTML5_Test_Suite_Server_Support version $VERSION"
cd $TEMP_DIR
git clone --branch $VERSION "https://github.com/${GITHUB_USER}/HTML5_Test_Suite_Server_Support.git" || abort

if [ 1 -eq ${INSTALL_NETWORK} ]; then 
	# Set up the network
	cp_net $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/interfaces /etc/network/interfaces || abort
	cp_net $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/iptables.up.rules /etc/iptables.up.rules || abort
	cp_net $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/sysctl.conf /etc/sysctl.conf || abort

	ifdown $IFACE_TEST
	ifup $IFACE_TEST
fi

if [ 1 -eq ${INSTALL_ROUTER} ]; then 
	for i in $TEMP_DIR/HTML5_Test_Suite_Server_Support/bind9/*
	do
		cp_net $i /etc/bind/$(basename $i) || abort
	done
	service bind9 restart

	for i in $TEMP_DIR/HTML5_Test_Suite_Server_Support/dhcp/*
	do
		cp_net $i /etc/dhcp/$(basename $i) || abort
	done
	service isc-dhcp-server restart
fi

if [ 1 -eq ${INSTALL_NETWORK} ]; then 
	ifdown $IFACE_INET
	ifup $IFACE_INET
fi

if [ 1 -eq ${INSTALL_WPT} ]; then 
	cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/web-platform-test/web-platform-test /etc/init.d/ || abort
	sed -i "s:USER=\"ubuntu\":USER=\"${SERVICE_USER}\":" /etc/init.d/web-platform-test || abort
	sed -i "s:WPT_DIR=\"/home/\$USER/web-platform-tests\":WPT_DIR=\"${WPT_DIR}\":" /etc/init.d/web-platform-test || abort
	update-rc.d web-platform-test defaults || abort
	service web-platform-test start
fi

if [ 1 -eq ${INSTALL_WPT_RESULTS} ]; then 
	if [ -e $TEMP_DIR/HTML5_Test_Suite_Server_Support/wpt-results ]; then
		cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/wpt-results/wpt-results /etc/init.d/ || abort
		sed -i "s:USER=\"ubuntu\":USER=\"${SERVICE_USER}\":" /etc/init.d/wpt-results || abort
		sed -i "s:WPT_RESULTS_DIR=\"/home/\$USER/WPT_Results_Collection_Server\":WPT_RESULTS_DIR=\"${WPT_RESULTS_DIR}\":" /etc/init.d/wpt-results || abort
		# Fix some bugs in older versions of the script
		sed -i "s:web-platform-test:wpt-results:" /etc/init.d/wpt-results || abort
		sed -i "s:W3C Web Platform Test:DLNA HTML5 Test Tool:" /etc/init.d/wpt-results || abort
		update-rc.d wpt-results defaults || about
		service wpt-results start
	fi

	if [ -e $TEMP_DIR/HTML5_Test_Suite_Server_Support/web ]; then
		if [ -e /var/www/html/index.html ]; then
			mv /var/www/html/index.html /var/www/html/~index.html || abort
		fi
		cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/web/* /var/www/html/ || abort
	fi
fi

# Save our config
mkdir -p $(dirname $CONFIG)
echo "VERSION=${VERSION}" > $CONFIG
echo "GITHUB_USER=${GITHUB_USER}" >> $CONFIG
echo "SERVICE_USER=${SERVICE_USER}" >> $CONFIG
echo "WPT_DIR=${WPT_DIR}" >> $CONFIG
echo "WPT_RESULTS_DIR=${WPT_RESULTS_DIR}" >> $CONFIG
echo "IFACE_INET=${IFACE_INET}" >> $CONFIG
echo "IFACE_TEST=${IFACE_TEST}" >> $CONFIG
echo "INSTALL_DRM_CONTENT=${INSTALL_DRM_CONTENT}" >> $CONFIG

cleanup
