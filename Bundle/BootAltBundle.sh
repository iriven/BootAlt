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
#               DECLARATION DES VARIABLES
#-------------------------------------------------------------------
BOOTALT_PRV_DIRECTORY="${BOOTALT_CORE_DIRECTORY}/Private"
BOOTALT_LIB_DIRECTORY="${BOOTALT_CORE_DIRECTORY}/Libraries"
BOOTALT_TPL_DIRECTORY="${BOOTALT_CORE_DIRECTORY}/Templates"
BOOTALT_ENV_FILE="${BOOTALT_PRV_DIRECTORY}/Environnement.sh"
BOOTALT_LIB_FILE="${BOOTALT_LIB_DIRECTORY}/Functions.sh"
BOOTALT_XCOPY_FILE="${BOOTALT_PRV_DIRECTORY}/.watermark"
BOOTALT_CONFIG_FILE="${BOOTALT_CONFIG_DIRECTORY}/Setup.conf"
PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin"
: ${BOOTALT_SOURCEDEVICE:-}
: ${BOOTALT_TARGETDEVICE:-}
: ${BOOTALT_ITEMSUFFIX:-_alt}
: ${BOOTALT_DEBUGENABLED:-false}
: ${BOOTALT_EXECMODE:-backup}
: ${BOOTALT_WORKSPACE:-/mnt/BOOTALT}
export PATH="${BOOTALT_DIRECTORY}:${PATH}"
#-------------------------------------------------------------------
#               DEBUT DU TRAITEMENT
#-------------------------------------------------------------------
#
# chargement des fonctions 
if [ ! -f "${BOOTALT_LIB_FILE}" ]; then
   printf " \e[31m %s \n\e[0m" "Blibliotheque de fonction introuvable!" 
   exit 1 
fi
. ${BOOTALT_LIB_FILE}
[ $(whoami) != "root" ] && writeLog "Vous devez avoir les droits root pour executer ce script."
require ${BOOTALT_CONFIG_FILE}
require ${BOOTALT_ENV_FILE}
ValidateConfigSyntax "${BOOTALT_CONFIG_FILE}"
. ${BOOTALT_CONFIG_FILE}
. ${BOOTALT_ENV_FILE}
[ -f /var/run/${PROG}.pid ] && writeLog "Une autre instance de \"${PROG}\" est deja en cours d'execution." || ${ECHO} $$ >/var/run/${PROG}.pid

[[ -z "${BOOTALT_SOURCEDEVICE}" ]]   && writeLog "Parametre BOOTALT_SOURCEDEVICE manquant";
[[ -z "${BOOTALT_TARGETDEVICE}" ]] 	 && writeLog "Parametre BOOTALT_TARGETDEVICE manquant";
[[ -z "${BOOTALT_WORKSPACE}" ]]  	 && writeLog "Parametre BOOTALT_WORKSPACE manquant";
[[ -z "${BOOTALT_TPL_DIRECTORY}" ]]  && writeLog "Parametre BOOTALT_TPL_DIRECTORY manquant";
[[ -z "${BOOTALT_ITEMSUFFIX}" ]]     && writeLog "Parametre BOOTALT_ITEMSUFFIX manquant";
[[ -z "${BOOTALT_EXECMODE}" ]]     	 && writeLog "Parametre BOOTALT_EXECMODE manquant";

isTrue "${BOOTALT_DEBUGENABLED}" 	&& set -x;

BOOTALT_SOURCEDEVICE=$(normalizeDeviceName "${BOOTALT_SOURCEDEVICE}")
BOOTALT_TARGETDEVICE=$(normalizeDeviceName "${BOOTALT_TARGETDEVICE}")

case "${BOOTALT_EXECMODE}" in
	[Rr][eE][Ss][Tt]*) BOOTALT_EXECMODE="restore"
		;;
	[Bb][Aa][Cc][Kk]*) BOOTALT_EXECMODE="backup"
		;;
		*) writeLog "La valeur du Parametre BOOTALT_EXECMODE est invalide: 150"
		;;		
esac

if [ "${BOOTALT_EXECMODE}" == "restore" ]; then
	isAlternateEnv "${BOOTALT_ITEMSUFFIX}" || writeLog "Le mode 'restore' n'est possible que depuis l'Environnement de boot Alterné."
	BOOTALT_TEMPDEVICE="${BOOTALT_SOURCEDEVICE}"
	BOOTALT_SOURCEDEVICE="${BOOTALT_TARGETDEVICE}"
	BOOTALT_TARGETDEVICE="${BOOTALT_TEMPDEVICE}"
else
	isAlternateEnv "${BOOTALT_ITEMSUFFIX}" && writeLog "Le mode 'backup' n'est possible que depuis l'Environnement de boot nominal."
fi