#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Script de creation de Boot Alterné sur des serveurs redhat              #
# ----------------------------------------------------------------------------- #
#       Author: Alfred TCHONDJO - Iriven France                                 #
#       Date: 2019-06-02                                                        #
# ----------------------------------------------------------------------------- #
#       Revisions                                                               #
#                                                                               #
#       G1R0C0 :        Creation du script le 02/06/2019 (AT)                   #
#################################################################################
# Header_end
# set -x
#-------------------------------------------------------------------
#               DECLARATION DES VARIABLES
#-------------------------------------------------------------------
BOOTALT_CUST_ENVFILE="${BOOTALT_CORE_DIRECTORY}/Environnement.sh"
BOOTALT_LIBRARIES_DIRECTORY="${BOOTALT_CORE_DIRECTORY}/Libs"
BOOTALT_LIBRARIES_FILE="${BOOTALT_LIBRARIES_DIRECTORY}/Functions.sh"
BOOTALT_WATERMARK="${BOOTALT_CORE_DIRECTORY}/.watermark"
BOOTALT_CONFIG_FILE="${BOOTALT_CONFIG_DIRECTORY}/Setup.conf"
#-------------------------------------------------------------------
#               DEBUT DU TRAITEMENT
#-------------------------------------------------------------------
#
# chargement des fonctions 
if [ ! -f "${BOOTALT_LIBRARIES_FILE}" ]; then
   printf " \e[31m %s \n\e[0m" "Blibliotheque de fonction introuvable!" 
   exit 1 
fi
. ${BOOTALT_LIBRARIES_FILE}
require ${BOOTALT_CONFIG_FILE}
require ${BOOTALT_CUST_ENVFILE}
ValidateConfigSyntax "${BOOTALT_CONFIG_FILE}"
. ${BOOTALT_CONFIG_FILE}
. ${BOOTALT_CUST_ENVFILE}

