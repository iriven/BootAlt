#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Script de creation de Boot Alterné sur des serveurs redhat              #
# ----------------------------------------------------------------------------- #
#       Author: Alfred TCHONDJO - Iriven France                                 #
#       Date: 2019-05-02                                                        #
# ----------------------------------------------------------------------------- #
#       Revisions                                                               #
#                                                                               #
#       G1R0C0 :        Creation du script le 02/05/2019 (AT)                   #
#################################################################################
# Header_end
# set -x
#-------------------------------------------------------------------
#               DECLARATION DES FONCTIONS
#--------------------------------------------------------------------


function pkgIsInstalled(){
	local pkgName=$1
	local found=$(rpm -qa | ${AWK} "/^$pkgName/ "' { print $0 }')
	[ ! -z "${found}" ] && return 0 || return 1
}


function pkgInstall(){
	local pkgName=$1
	pkgIsInstalled "${pkgName}" && return 0;
	writeLog "Installation de la librairie ${pkgName} " "info";
	yum -y install "${pkgName}" > /dev/null 2>&1 | wait;
	[ $? -eq 0 ]  && return 0 || return 1
}

#function enableRepo(){}

function installPrerequisites(){
	local packages=("$@")
	local count=${#packages[@]} 
	for (( i=0;i<${count};i++)); do 
	    local dependance=${packages[${i}]} 
	    if [ ! -z "${dependance}" ]
	    then
	    	pkgInstall "${dependance}" ||  writeLog "Echec d'installation du package: ${dependance}"
	    fi 
	done
}
