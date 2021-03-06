#!/bin/bash

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
#WARN=$(tput setaf 3)
NC=$(tput sgr0)
#BOLD=$(tput bold)
#REV=$(tput smso)

RET=0

assert()
{
    msg="${1:-}"
    res="${2:-1}"
    echo -n $msg 
    if [ ${res} -ne 0 ]
    then
        echo " [ ${RED}Fail${NC} ]"
        RET=$res
    else
        echo " [  ${GREEN}OK${NC}  ]"
    fi
}

ifconfig | grep 192.168.0.
assert "Interface on correct network" $?

grep 192.168.0.1 < /etc/resolv.conf
assert "Correct DNS server" $?

host web-platform.test
assert "Resolve domain name" $?

curl http://web-platform.test:8000/ > /dev/null
assert "Web Platform Test up" $?

curl http://web-platform.test/upload/ > /dev/null
assert "WPT results up" $?

exit ${RET}