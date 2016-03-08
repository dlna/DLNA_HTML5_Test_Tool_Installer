#!/bin/bash

VERSION="Release_2014.09.31"
GITHUB_USER="dlna"
TEMP_DIR=$(mktemp --directory)

SERVICE_USER="dhtt"

WPT_DIR="/usr/local/web-platform-test"
WPT_RESULTS_DIR="/var/www/html/upload"

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
NC=$(tput sgr0)
BOLD=$(tput bold)
REV=$(tput smso)

SCRIPT=$(basename ${BASH_SOURCE[0]})
SCRIPT_VERSION="1.0.0"

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

function usage()
{
  echo "Help documentation for ${BOLD}${SCRIPT}${NC}."
  echo "${BOLD}$SCRIPT${NC} [OPTION] "
  echo "Command line switches are optional. The following switches are recognized."
  echo "${REV}-u <user>${NC}  Sets the Github user account to grab the repositories from. Default is ${BOLD}dlna${NC}."
  echo "${REV}-r <tag>${NC}   Sets version to download. For the latest version use ${BOLD}master${NC}. Default is ${BOLD}${VERSION}${NC}."
  echo "${REV}-h${NC}         Displays this help message. No further functions are performed."
  echo "${REV}-v${NC}         Displays the installer script. No further functions are performed."
  echo "Example: ${BOLD}${SCRIPT} -u ${GITHUB_USER} -r ${VERSION}${NC}"
  exit 1
}

function git-update()
{
	REPO=$1
	DIR=$2
	if [ -e $DIR ]; then 
		msg "# Updating ${REPO} version ${VERSION}"
		cd $DIR
		git remote set-url origin "https://github.com/${GITHUB_USER}/${REPO}.git" || abort
		git fetch origin || abort
		git checkout $VERSION || abort
		git tag | grep $VERSION > /dev/null
		if [ $? -ne 0 ]; then 
			git pull origin $VERSION || abort
		fi
	else
		msg "# Installing ${REPO} version ${VERSION}"
		git clone --branch $VERSION "https://github.com/${GITHUB_USER}/${REPO}.git" $DIR || abort
		cd $DIR
		git submodule update --init --recursive
	fi
}

msg "DLNA HTML5 Test Tool Installer"
msg "=============================="
msg ""

# Test for pre-requisites 
if [ "$(id -u)" != "0" ]; then
	# This is not ideal but will do for a first version
    error "This script must be run as root" 
fi

ifconfig eth0 > /dev/null 2>&1 > /dev/null || error "eth0 not found"
ifconfig eth1 > /dev/null 2>&1 > /dev/null || error "eth1 not found"

# Parse command line
while getopts ":u:r:hv" opt; do
  case $opt in
    u)
      GITHUB_USER=$OPTARG
      ;;
    r)
      VERSION=$OPTARG
      ;;
    h)  # show help
      usage
      ;;
    v)  # show version
      msg "$SCRIPT v$SCRIPT_VERSION"
      ;;
    \?)
      error "Invalid option: -$OPTARG"
      ;;
    :)
      error "Option -$OPTARG requires an argument."
      ;;
  esac
done

echo -n "Install Version $VERSION? [y/N] "
read CONFIRM
if [ "y" != "$CONFIRM" -a "Y" != "$CONFIRM" ]; then
	abort
fi

msg "### Installing pre-requisits"
apt-get install -y ssh git bind9 isc-dhcp-server python python-html5lib curl apache2 php5 php5-dev libapache2-mod-php5 pkg-config libzmq-dev || abort

adduser --system --quiet $SERVICE_USER
addgroup --system --quiet $SERVICE_USER
adduser --quiet $SERVICE_USER $SERVICE_USER

if [ -e $WPT_DIR ]; then 
	msg "# Updating web-platform-test version $VERSION"
	cd $WPT_DIR
	git remote set-url origin "https://github.com/${GITHUB_USER}/web-platform-tests.git" || abort
	git fetch origin || abort
	git checkout $VERSION || abort
else
	msg "# Installing web-platform-test version $VERSION"
	git clone --branch $VERSION "https://github.com/${GITHUB_USER}/web-platform-tests.git" $WPT_DIR || abort
	cd $WPT_DIR
	git submodule update --init --recursive
fi
python tools/scripts/manifest.py
cp config.default.json config.json
sed 's!"bind_hostname": true}!"bind_hostname"\: true,"test_tool_endpoint": "http://web-platform.test/upload/api.php/"}!' -i config.json

if [ -e $WPT_RESULTS_DIR ]; then 
	msg "# Updating WPT_Results_Collection_Server version $VERSION"
	cd $WPT_RESULTS_DIR
	git remote set-url origin "https://github.com/${GITHUB_USER}/WPT_Results_Collection_Server.git" || abort
	git fetch origin || abort
	git checkout $VERSION || abort
else
	msg "# Installing WPT_Results_Collection_Server version $VERSION"
	git clone --branch $VERSION "https://github.com/${GITHUB_USER}/WPT_Results_Collection_Server.git" $WPT_RESULTS_DIR || abort
	cd $WPT_RESULTS_DIR
fi

if [ -e $WPT_RESULTS_DIR/composer.json ]; then
	if [ ! -x /usr/local/bin/composer ]; then 
		msg "# Installing composer"
		cd $TEMP_DIR
		curl -sS https://getcomposer.org/installer | php || abort
		mv composer.phar /usr/local/bin/composer || abort
	fi
	
	if [ ! -e /etc/php5/apache2/conf.d/99-zmq.ini ]; then 
		msg "# Installing PHP ZQM extension"
		cd $TEMP_DIR
		git clone git://github.com/mkoppanen/php-zmq.git || abort
		cd php-zmq || abort
		phpize && ./configure || abort
		make || abort
		make install || abort
		echo extension=zmq.so | tee /etc/php5/apache2/conf.d/99-zmq.ini || abort
		echo extension=zmq.so | tee /etc/php5/cli/conf.d/99-zmq.ini || abort
	fi
	
	cd $WPT_RESULTS_DIR
	composer install || abort

	if [ -e $WPT_RESULTS_DIR/Notifier ]; then 
		msg "# Installing Notifier"
		cd $WPT_RESULTS_DIR/Notifier
		composer install || abort
	fi
fi

if [ ! -e $WPT_RESULTS_DIR/logs ]; then
	mkdir $WPT_RESULTS_DIR/logs || abort
	chown www-data:www-data $WPT_RESULTS_DIR/logs || abort
fi

sed -E -i "s/upload_max_filesize *= *[0-9]+M/upload_max_filesize = 200M/" /etc/php5/apache2/php.ini 
sed -E -i "s/post_max_size *= *[0-9]+M/post_max_size = 200M/" /etc/php5/apache2/php.ini 
sed -E -i "s/memory_limit *= *[0-9]+M/memory_limit = 512M/" /etc/php5/apache2/php.ini 

msg "# Installing HTML5_Test_Suite_Server_Support version $VERSION"
cd $TEMP_DIR
git clone --branch $VERSION "https://github.com/${GITHUB_USER}/HTML5_Test_Suite_Server_Support.git" || abort

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/interfaces /etc/network/interfaces || abort
cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/iptables.up.rules /etc/iptables.up.rules || abort
cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/sysctl.conf /etc/sysctl.conf || abort
for IF in eth0 eth1
do
	ifdown $IF
	ifup $IF
done

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/bind9/* /etc/bind/ || abort
service bind9 restart

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/dhcp/* /etc/dhcp/ || abort
service isc-dhcp-server restart

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/web-platform-test/web-platform-test /etc/init.d/ || abort
sed -i "s:USER=\"ubuntu\":USER=\"$SERVICE_USER\":" /etc/init.d/web-platform-test || abort
sed -i "s:WPT_DIR=\"/home/\$USER/web-platform-tests\":WPT_DIR=\"${WPT_DIR}\":" /etc/init.d/web-platform-test || abort
update-rc.d web-platform-test defaults || abort
service web-platform-test start

if [ -e $TEMP_DIR/HTML5_Test_Suite_Server_Support/wpt-results ]; then
	cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/wpt-results/wpt-results /etc/init.d/ || abort
	sed -i "s:USER=\"ubuntu\":USER=\"$SERVICE_USER\":" /etc/init.d/wpt-results || abort
	sed -i "s:WPT_RESULTS_DIR=\"/home/\$USER/WPT_Results_Collection_Server\":WPT_RESULTS_DIR=\"${WPT_RESULTS_DIR}\":" /etc/init.d/wpt-results || abort
	update-rc.d wpt-results defaults || abou
	service wpt-results start
fi

if [ -e $TEMP_DIR/HTML5_Test_Suite_Server_Support/web ]; then
	if [ -e /var/www/html/index.html ]; then
		mv /var/www/html/index.html /var/www/html/~index.html || abort
	fi
	cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/web/* /var/www/html/ || abort
fi

cleanup
