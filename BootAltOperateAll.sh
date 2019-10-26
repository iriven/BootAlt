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
#-------------------------------------------------------------------
#               DECLARATION DES VARIABLES
#-------------------------------------------------------------------
BOOTALT_DIRECTORY=$(dirname "$(readlink -f "$0")")
BOOTALT_CORE_DIRECTORY="${BOOTALT_DIRECTORY}/Bundle"
BOOTALT_CONFIG_DIRECTORY="${BOOTALT_DIRECTORY}/Settings"
BOOTALT_CORE_FILE="${BOOTALT_CORE_DIRECTORY}/BootAltBundle.sh"

#-------------------------------------------------------------------
#               DEBUT DU TRAITEMENT
#-------------------------------------------------------------------
#
# chargement des fonctions 
if [ ! -f "${BOOTALT_CORE_FILE}" ]; then
   printf " \e[31m %s \n\e[0m" "Des fichiers indispensables sont introuvables !"	
   exit 1 
fi
. ${BOOTALT_CORE_FILE}

BootAltInitialize "${BOOTALT_SOURCEDEVICE}" "${BOOTALT_TARGETDEVICE}" "${BOOTALT_TPL_DIRECTORY}" "${BOOTALT_WORKSPACE}" "${BOOTALT_ITEMSUFFIX}";
BootAltExecute  "${BOOTALT_SOURCEDEVICE}" "${BOOTALT_TARGETDEVICE}" "${BOOTALT_WORKSPACE}" "${BOOTALT_ITEMSUFFIX}";
BootAltClose "${BOOTALT_SOURCEDEVICE}" "${BOOTALT_TARGETDEVICE}" "${BOOTALT_WORKSPACE}" "${BOOTALT_ITEMSUFFIX}";

#cd /dev/disk/by-path
#ls -ltr

#crontab -e
#0 3 * * 0 /opt/BootAlt/BootAltOperateAll.sh 2>&1 | /usr/bin/tee /var/log/BootAlt_single.log >> /var/log/BootAlt.log
