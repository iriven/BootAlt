#!/usr/bin/env bash
# Header_start
##############################################################################################
#                                                                                            #
#  Author:         Alfred TCHONDJO - Iriven France                                           #
#  Date:           2019-05-14                                                                #
#  Website:        https://github.com/iriven?tab=repositories                                #
#                                                                                            #
# ------------------------------------------------------------------------------------------ #
#                                                                                            #
#  Project:        Linux Alternate Boot (BOOTALT)                                            #
#  Description:	   An advanced tool to create alternate boot environment on Linux servers.   #
#  Version:        1.0.1    (G1R0C1)                                                         #
#                                                                                            #
#  License:        GNU GPLv3                                                                 #
#                                                                                            #
#  This program is free software: you can redistribute it and/or modify                      #
#  it under the terms of the GNU General Public License as published by                      #
#  the Free Software Foundation, either version 3 of the License, or                         #
#  (at your option) any later version.                                                       #
#                                                                                            #
#  This program is distributed in the hope that it will be useful,                           #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of                            #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                             #
#  GNU General Public License for more details.                                              #
#                                                                                            #
#  You should have received a copy of the GNU General Public License                         #
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.                     #
#                                                                                            #
# ------------------------------------------------------------------------------------------ #
#  Revisions                                                                                 #
#                                                                                            #
#  - G1R0C0 :        Creation du script le 14/05/2019 (AT)                                   #
#  - G1R0C1 :        Update - détection auto des FS le 30/09/2019 (AT)                       #
#                                                                                            #
##############################################################################################
# Header_end
# set -x
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  printf "\\n%s is a part of bash Linux Alternate Boot (BOOTALT) project. Dont execute it directly!\\n\\n" "${0##*/}"
  exit 1
fi
#-------------------------------------------------------------------
#               DECLARATION DES FONCTIONS
#--------------------------------------------------------------------


function isAllreadyInstalled(){
	local pkgName=$1
	local found=$(rpm -qa | ${AWK} "/^$pkgName/ "' { print $0 }')
	[ ! -z "${found}" ] && return 0 || return 1
}

function installPackage(){
	local pkgName=$1
	isAllreadyInstalled "${pkgName}" && return 0;
	writeLog "Installation de la librairie ${pkgName} " "info";
	yum -y install "${pkgName}" > /dev/null 2>&1 | wait;
	[ $? -eq 0 ]  && return 0 || return 1
}

function enableRepo(){

	for file in $(ls /etc/yum.repos.d/*.repo|grep -vi 'media'|grep -vi 'debug'|grep -vi 'source'); do
		sed -i -e 's/^[[:space:]]*\(enable*\)=\(.*\)$/\1=1/Ig' ${file}
	done	
	sleep 2
}
function disableRepo(){

	for file in $(ls /etc/yum.repos.d/*.repo); do
		sed -i -e 's/^[[:space:]]*\(enable*\)=\(.*\)$/\1=0/Ig' ${file}
	done	
	sleep 2
}

function installRequiredPackages(){
	local packages=("$@")
	local count=${#packages[@]}
	enableRepo 
	for (( i=0;i<${count};i++)); do 
	    local dependance=${packages[${i}]} 
	    if [ ! -z "${dependance}" ]
	    then
	    	installPackage "${dependance}" ||  writeLog "Echec d'installation du package: ${dependance}"
	    fi 
	done
	disableRepo 
}
