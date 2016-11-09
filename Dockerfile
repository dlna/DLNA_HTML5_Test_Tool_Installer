FROM ubuntu:14.04
MAINTAINER Jeremy Poulter <jeremy@global-dlna.org>
WORKDIR /root
COPY DLNA_HTML5_Test_Tool_Installer.sh DLNA_HTML5_Test_Tool_Installer.sh
RUN bash DLNA_HTML5_Test_Tool_Installer.sh -u jeremypoulter -r master -y

