INSTALL=$(docker run -dit ubuntu:${HTT_OS_VERSION} /bin/bash)
    # Updates needed for Docker, needs to be manually setup the network
sudo pipework br0 ${INSTALL} 192.168.0.1/24
docker exec ${INSTALL} sh -c 'echo "192.168.0.1   web-platform.test" >> /etc/hosts'
docker exec ${INSTALL} sh -c 'echo "192.168.0.1   www.web-platform.test" >> /etc/hosts'
docker exec ${INSTALL} sh -c 'echo "192.168.0.1   www1.web-platform.test" >> /etc/hosts'
docker exec ${INSTALL} sh -c 'echo "192.168.0.1   www2.web-platform.test" >> /etc/hosts'
docker exec ${INSTALL} sh -c 'echo "192.168.0.1   xn--n8j6ds53lwwkrqhv28a.web-platform.test" >> /etc/hosts'
docker exec ${INSTALL} sh -c 'echo "192.168.0.1   xn--lve-6lad.web-platform.test" >> /etc/hosts'
docker exec ${INSTALL} sh -c 'echo "0.0.0.0       nonexistent-origin.web-platform.test" >> /etc/hosts'
    # Run the test script in the Docker container
docker cp DLNA_HTML5_Test_Tool_Installer.sh ${INSTALL}:/root/DLNA_HTML5_Test_Tool_Installer.sh
for HTT_VERSION in ${HTT_VERSIONS}; do 
        docker exec ${INSTALL} bash /root/DLNA_HTML5_Test_Tool_Installer.sh --disable-network -y -r ${HTT_VERSION} || exit $?; 
      done
    # Test that things are up and running
TEST=$(docker run -dit ubuntu:16.04 /bin/bash)
docker exec ${TEST} apt-get -y update
docker exec ${TEST} apt-get -y install host net-tools curl isc-dhcp-client
sudo bash pipework br0 -i eth1 ${TEST} dhclient
docker cp Validate_Install.sh ${TEST}:/root/Validate_Install.sh
docker exec ${TEST} bash /root/Validate_Install.sh
