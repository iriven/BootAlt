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
#               DECLARATION DES VARIABLES
#-------------------------------------------------------------------
BOOTALT_DIRECTORY=$(dirname "$(readlink -f "$0")")
BOOTALT_CONFIG_DIRECTORY="${BOOTALT_DIRECTORY}/Settings"
BOOTALT_CORE_DIRECTORY="${BOOTALT_DIRECTORY}/Core"
BOOTALT_CORE_FILE="${BOOTALT_CORE_DIRECTORY}/BootAltBundle.sh"
BOOTALT_TPL_DIRECTORY="${BOOTALT_CORE_DIRECTORY}/Templates"
: ${ORIG_DISK:-}
: ${ORIG_ROOT_PV:-}
: ${ORIG_ROOT_VG:-rootvg}
: ${ORIG_INFRA_VG:-infravg}
: ${ORIG_ROOT_LV:-root_lv}
: ${ALT_BOOT_DEV:-}
: ${ALT_ROOT_PV:-}
: ${ALT_ROOT_VG:-altrootvg}
: ${ALT_INFRA_VG:-altinfravg}
: ${ALT_INFRA_PV:-}
: ${ALT_DISK:-}
: ${DEBUG_ENABLED:-false}
: ${ALT_WORKSPACE:-/mnt/BOOTALT}

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

isTrue "${DEBUG_ENABLED}" 	&& set -x;

ALT_DISK=$(readlink -f "${ALT_DISK}")
ALT_ROOT_PV=$(readlink -f "${ALT_ROOT_PV}")
ALT_BOOT_DEV=$(readlink -f "${ALT_BOOT_DEV}")
ALT_INFRA_PV=$(readlink -f "${ALT_INFRA_PV}")

[[ -z "${ORIG_DISK}" ]]    	&& writeLog "Parametre ORIG_DISK manquant";
[[ -z "${ORIG_ROOT_PV}" ]]  && writeLog "Parametre ORIG_ROOT_PV manquant";
[[ -z "${ORIG_ROOT_VG}" ]]  && writeLog "Parametre ORIG_ROOT_VG manquant";
[[ -z "${ORIG_ROOT_LV}" ]]  && writeLog "Parametre ORIG_ROOT_LV manquant";
[[ -z "${ALT_ROOT_PV}" ]] 	&& writeLog "Parametre ALT_ROOT_PV manquant";
[[ -z "${ALT_ROOT_VG}" ]]  	&& writeLog "Parametre ALT_ROOT_VG manquant";
[[ -z "${ALT_BOOT_DEV}" ]] 	&& writeLog "Parametre ALT_BOOT_DEV manquant";
[[ -z "${ALT_DISK}" ]] 		&& writeLog "Parametre ALT_DISK manquant";
[[ -z "${ALT_WORKSPACE}" ]] && writeLog "Parametre ALT_WORKSPACE manquant";
[[ -z "${ALT_INFRA_PV}" ]]  && writeLog "Parametre ALT_INFRA_PV manquant";
[[ -z "${ALT_INFRA_VG}" ]]  && writeLog "Parametre ALT_INFRA_VG manquant";

BootAltInitialize "${BOOTALT_TPL_DIRECTORY}" "${ALT_BOOT_DEV}" "${ALT_ROOT_VG}" "${ORIG_ROOT_PV}" \
"${ALT_ROOT_PV}" "${ORIG_ROOT_VG}" "${ALT_INFRA_PV}" "${ORIG_INFRA_VG}" "${ALT_INFRA_VG}" "${ALT_DISK}" \
"${ORIG_DISK}" "${ALT_WORKSPACE}" "${ORIG_ROOT_LV}";
BootAltExecute  "${ALT_BOOT_DEV}" "${ALT_DISK}" "${ORIG_ROOT_VG}" "${ALT_ROOT_VG}" "${ORIG_INFRA_VG}" "${ALT_INFRA_VG}" "${ALT_WORKSPACE}"
BootAltClose "${ALT_BOOT_DEV}" "${ALT_ROOT_VG}" "${ORIG_ROOT_LV}" "${ORIG_INFRA_VG}" "${ALT_INFRA_VG}" "${ALT_WORKSPACE}" "${ORIG_ROOT_VG}"