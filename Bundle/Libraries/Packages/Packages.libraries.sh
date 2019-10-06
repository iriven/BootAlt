#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Fichier de Configuration du Script de creation du boot alterné    		#
# ----------------------------------------------------------------------------- #
#       Author: Alfred TCHONDJO - Iriven France                                 #
#       Date: 2018-05-14                                                        #
# ----------------------------------------------------------------------------- #
#       Revisions                                                               #
#                                                                               #
#       G1R0C0 :        Creation du script le 14/05/2019 (AT)                   #
#       G1R0C1 :        Update - détection auto des FS le 30/09/2019 (AT)       #
#                                                                               #
#################################################################################
# Header_end
# set -x
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
