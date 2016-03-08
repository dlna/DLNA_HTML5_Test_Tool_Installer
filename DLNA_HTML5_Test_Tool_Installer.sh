#!/bin/bash

VERSION="Release_2014.09.31"
GITHUB_USER="dlna"
TEMP_DIR=$(mktemp --directory)

SERVICE_USER="dhtt"

WPT_DIR="/usr/local/web-platform-test"
WPT_RESULTS_DIR="/var/www/html/upload"

# Some support functions
function error()
{
	echo "$*" >&2
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

echo "DLNA HTML5 Test Tool Installer"
echo "=============================="
echo ""


# Test for pre-requisites 
if [ "$(id -u)" != "0" ]; then
	# This is not ideal but will do for a first version
    error "This script must be run as root" 
fi

ifconfig eth0 > /dev/null 2>&1 > /dev/null || error "eth0 not found"
ifconfig eth1 > /dev/null 2>&1 > /dev/null || error "eth1 not found"

echo -n "Install Version $VERSION? [y/N] "
read CONFIRM
if [ "y" != "$CONFIRM" -a "Y" != "$CONFIRM" ]; then
	abort
fi

echo "### Installing pre-requisits"
apt-get install -y ssh git bind9 isc-dhcp-server python python-html5lib curl apache2 php5 php5-dev libapache2-mod-php5 pkg-config libzmq-dev || abort

adduser --system --quiet $SERVICE_USER
addgroup --system --quiet $SERVICE_USER
adduser --quiet $SERVICE_USER $SERVICE_USER

if [ -e $WPT_DIR ]; then 
	echo "# Updating web-platform-test version $VERSION"
	cd $WPT_DIR
	git remote set-url origin "https://github.com/${GITHUB_USER}/web-platform-tests.git" || about
	git fetch origin || abort
	git checkout $VERSION || abort
else
	echo "# Installing web-platform-test version $VERSION"
	git clone --branch $VERSION "https://github.com/${GITHUB_USER}/web-platform-tests.git" $WPT_DIR || about
	cd $WPT_DIR
	git submodule update --init --recursive
fi
python tools/scripts/manifest.py
cp config.default.json config.json
sed 's!"bind_hostname": true}!"bind_hostname"\: true,"test_tool_endpoint": "http://web-platform.test/upload/api.php/"}!' -i config.json

if [ -e $WPT_RESULTS_DIR ]; then 
	echo "# Updating WPT_Results_Collection_Server version $VERSION"
	cd $WPT_RESULTS_DIR
	git remote set-url origin "https://github.com/${GITHUB_USER}/WPT_Results_Collection_Server.git" || about
	git fetch origin || abort
	git checkout $VERSION || abort
else
	echo "# Installing WPT_Results_Collection_Server version $VERSION"
	git clone --branch $VERSION "https://github.com/${GITHUB_USER}/WPT_Results_Collection_Server.git" $WPT_RESULTS_DIR || about
	cd $WPT_RESULTS_DIR
fi
if [ -e $WPT_RESULTS_DIR/composer.json ]; then
	if [ ! -x /usr/local/bin/composer ]; then 
		echo "# Installing composer"
		cd $TEMP_DIR
		curl -sS https://getcomposer.org/installer | php || about
		mv composer.phar /usr/local/bin/composer || about
	fi
	
	cd $WPT_RESULTS_DIR
	composer install || about
	
	if [ -e $WPT_RESULTS_DIR/Notifier ]; then 
		echo "# Installing Notifier"
		if [ ! -e /etc/php5/apache2/conf.d/99-zmq.ini ]; then 
			cd $TEMP_DIR
			git clone git://github.com/mkoppanen/php-zmq.git || about
			cd php-zmq|| about
			phpize && ./configure || about
			make || about
			make install || about
			echo extension=zmq.so | tee /etc/php5/apache2/conf.d/99-zmq.ini || about
			echo extension=zmq.so | tee /etc/php5/cli/conf.d/99-zmq.ini || about
		fi
		
		cd $WPT_RESULTS_DIR/Notifier
		composer install || about
	fi
fi

if [ ! -e $WPT_RESULTS_DIR/logs ]; then
	mkdir $WPT_RESULTS_DIR/logs || abort
	chown www-data:www-data $WPT_RESULTS_DIR/logs || abort
fi

sudo sed -E -i "s/upload_max_filesize *= *[0-9]+M/upload_max_filesize = 200M/" /etc/php5/apache2/php.ini 
sudo sed -E -i "s/post_max_size *= *[0-9]+M/post_max_size = 200M/" /etc/php5/apache2/php.ini 
sudo sed -E -i "s/memory_limit *= *[0-9]+M/memory_limit = 512M/" /etc/php5/apache2/php.ini 

echo "# Installing HTML5_Test_Suite_Server_Support version $VERSION"
cd $TEMP_DIR
git clone --branch $VERSION "https://github.com/${GITHUB_USER}/HTML5_Test_Suite_Server_Support.git" || about

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/interfaces /etc/network/interfaces || about
cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/iptables.up.rules /etc/iptables.up.rules || about
cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/network/sysctl.conf /etc/sysctl.conf || about
for IF in eth0 eth1
do
	ifdown $IF
	ifup $IF
done

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/bind9/* /etc/bind/ || about
service bind9 restart

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/dhcp/* /etc/dhcp/ || about
service isc-dhcp-server restart

cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/web-platform-test/web-platform-test /etc/init.d/ || about
sed -i "s:USER=\"ubuntu\":USER=\"$SERVICE_USER\":" /etc/init.d/web-platform-test || about
sed -i "s:WPT_DIR=\"/home/\$USER/web-platform-tests\":WPT_DIR=\"${WPT_DIR}\":" /etc/init.d/web-platform-test || about
update-rc.d web-platform-test defaults || about
service web-platform-test start

if [ -e $TEMP_DIR/HTML5_Test_Suite_Server_Support/wpt-results ]; then
	cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/wpt-results/wpt-results /etc/init.d/ || about
	sed -i "s:USER=\"ubuntu\":USER=\"$SERVICE_USER\":" /etc/init.d/wpt-results || about
	sed -i "s:WPT_RESULTS_DIR=\"/home/\$USER/WPT_Results_Collection_Server\":WPT_RESULTS_DIR=\"${WPT_RESULTS_DIR}\":" /etc/init.d/wpt-results || about
	update-rc.d wpt-results defaults || abou
	service wpt-results start
fi

if [ -e $TEMP_DIR/HTML5_Test_Suite_Server_Support/web ]; then
	if [ -e mv /var/www/html/index.html ]; then
		mv /var/www/html/index.html /var/www/html/~index.html || about
	fi
	cp $TEMP_DIR/HTML5_Test_Suite_Server_Support/web/* /var/www/html/ || about
fi

cleanup
