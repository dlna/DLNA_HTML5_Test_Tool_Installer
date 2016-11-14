# DLNA HTML5 Test Tool Installer

[![Build Status](https://travis-ci.org/dlna/DLNA_HTML5_Test_Tool_Installer.svg?branch=master)](https://travis-ci.org/dlna/DLNA_HTML5_Test_Tool_Installer)
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/f5332e05fd59485b82ce5f7882b96c04)](https://www.codacy.com/app/DLNA/DLNA_HTML5_Test_Tool_Installer?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=dlna/DLNA_HTML5_Test_Tool_Installer&amp;utm_campaign=Badge_Grade)

This repository provides an instillation script for the DLNA HTML5 Test Tool

## Usage

```
wget https://raw.githubusercontent.com/dlna/DLNA_HTML5_Test_Tool_Installer/master/DLNA_HTML5_Test_Tool_Installer.sh
sudo bash DLNA_HTML5_Test_Tool_Installer.sh
```

## Command line options

__Help__: ```-h```/```--help```  
Display a quick reference of the command usage of the installer.

__Version__:  ```-v```/```--version```  
Display the installer version number

__Revision__: ```-r <revision>```/```--revision <revision>```  
The Git tag/branch to install. Current valid values (for the DLNA repository) are;
* [Release_2014.09.31](https://github.com/dlna/web-platform-tests/releases/tag/Release_2014.09.31) (default)
* [Release_2016.03.11_Alpha](https://github.com/dlna/web-platform-tests/releases/tag/Release_2016.03.11_Alpha)
* master

__GitHub User__: ```-u <user>```/```--user <user>```  
The Github user to use when cloning the tests/support. Currently the same user is used for all the repositories
so all of the following will be need to be forked;
* [web-platform-tests](https://github.com/dlna/web-platform-tests)
* [WPT_Results_Collection_Server](https://github.com/dlna/WPT_Results_Collection_Server)
* [HTML5_Test_Suite_Server_Support](https://github.com/dlna/HTML5_Test_Suite_Server_Support)

__DRM Content__: ```-d```/```--drm-content```  
Download the content needed for DRM testing if supported in the test suite. You will need to be granted access to the 
content by DLNA staff, email [admin@dlna.org](mailto:admin@dlna.org) for more details.

__Answer Yes__: ```-y```/```--yes```  
Answer 'yes' to any applicable questions from the installer. For use in automated setup, not recommended for normal
use.

__Disable Network Setup__: ```--disable-network```  
Do not make changes to the network interface setup of the machine. The required setup will need to be made manyally. 
For use in automated setup, not recommended for normal use.
