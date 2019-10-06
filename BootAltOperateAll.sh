#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Script de creation de Boot Alterné sur des serveurs redhat              #
# ----------------------------------------------------------------------------- #
#       Author: Alfred TCHONDJO - Iriven France   Pour Orange                   #
#       Date: 2019-05-02                                                        #
# ----------------------------------------------------------------------------- #
#       Revisions                                                               #
#                                                                               #
#       G1R0C0 :        Creation du script le 02/05/2019 (AT)                   #
#       G1R0C1 :        Update - détection auto des FS le 30/09/2019 (AT)       #
#                                                                               #
#################################################################################
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
