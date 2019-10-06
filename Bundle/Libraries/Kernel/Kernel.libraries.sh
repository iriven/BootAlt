#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Fichier de Configuration du Script de creation du boot alterné          #
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

function installBootLoader(){
    local device=$(normalizeDeviceName "${1}")
    diskexists "${device}" || writeLog "installBootLoader - Le nom disque ${device} est incorrect: $?"
    writeLog "Installation du bootloader sur ${device} " "info"
    ${GRUBINSTALL} --no-floppy --recheck ${device} >/dev/null 2>&1  || writeLog "Echec de la mise à jour du GRUB sur ${device}: $?"
    ${WAIT}
}

function permuteGrubMenuEntry() {
    local filepath=$1
    local srcmarker_open="### BEGIN /etc/grub.d/10_linux ###"
    local srcmarker_close="### END /etc/grub.d/10_linux ###"
    local tgtmarker_open="### BEGIN /etc/grub.d/40_custom ###"
    local tgtmarker_close="### END /etc/grub.d/40_custom ###"
    local cachefile="/tmp/tempdata.txt"
    [ -f "${filepath}" ] || writeLog "Le fichier de Configuration du grub est introuvable"
    writeLog "Priorisation de l'Initrd du BOOTALT" "info"
    firstBlockBeginningLine=$(${GREP} -n "${srcmarker_open}" ${filepath}| ${SED} 's/\(.*\):.*/\1/g')
    lastBlockEndingLine=$(${GREP} -n "${tgtmarker_close}" ${filepath} | ${SED} 's/\(.*\):.*/\1/g')
    srcmarker_open=$(escapeSlashes "${srcmarker_open}" )
    srcmarker_close=$(escapeSlashes "${srcmarker_close}" )
    tgtmarker_open=$(escapeSlashes "${tgtmarker_open}" )
    tgtmarker_close=$(escapeSlashes "${tgtmarker_close}" )
    if [ "${firstBlockBeginningLine}" -lt "${lastBlockEndingLine}" ] 
    then
        ${SED} -n "/${tgtmarker_open}*/,/${tgtmarker_close}/p" ${filepath} > ${cachefile}
        ${SED} -n "/${srcmarker_open}*/,/${srcmarker_close}/p" ${filepath} >> ${cachefile}
        ${CAT} <(${HEAD} -n $(${EXPR} $firstBlockBeginningLine - 1) ${filepath}) ${cachefile} <(${TAIL} -n +$(${EXPR} $lastBlockEndingLine + 1) ${filepath}) >temp
        ${MV} temp ${filepath}
        ${RM} -f ${cachefile}
    fi
}

function getCustGrubConfigFile(){
    local osversion=$(getOSVersion)
    local grubcfgfile=
    case "${osversion}" in
      3|4|5|6)  grubcfgfile="/boot/grub/grub.conf" ;;
      *)   grubcfgfile="/etc/grub.d/40_custom" ;;
    esac
     [ -f "${grubcfgfile}" ] || writeLog "Le fichier de Configuration du grub est introuvable"
    echo "${grubcfgfile}"
}

function getTemplateFile(){
    local tpldir=$1
    local osversion=$(getOSVersion)
    local tplfile="${tpldir}/menuentry-"
    case "${osversion}" in
      3|4|5|6)  tplfile="${tplfile}3456.tpl" ;;
      *)   tplfile="${tplfile}78.tpl" ;;
    esac
     [ -f "${tplfile}" ] || writeLog "Le template de Configuration du menu de Boot alterné est introuvable"
    echo "${tplfile}"
}

function isInternalDevice() {
    local filepath=$1
    local srcmarker_open="### BEGIN /etc/grub.d/10_linux ###"
    local srcmarker_close="### END /etc/grub.d/10_linux ###"
    local tgtmarker_open="### BEGIN /etc/grub.d/40_custom ###"
    local tgtmarker_close="### END /etc/grub.d/40_custom ###"
    [ ! -f "${filepath}" ] && return 0;
    firstBlockBeginningLine=$(${GREP} -n "${srcmarker_open}" ${filepath}| ${SED} -e 's/\(.*\):.*/\1/g')
    lastBlockEndingLine=$(${GREP} -n "${tgtmarker_close}" ${filepath} | ${SED} -e 's/\(.*\):.*/\1/g')
    [ "${firstBlockBeginningLine}" -ge "${lastBlockEndingLine}" ] && return 0 || return 1 ;
}

function getCustGrubMenuFile(){
    local osversion=$(getOSVersion)
    local grubcfgfile=
    case "${osversion}" in
      3|4|5|6)  grubcfgfile="/boot/grub/grub.conf" ;;
      *)   grubcfgfile="/etc/grub.d/40_custom" ;;
    esac
     [ -f "${grubcfgfile}" ] || writeLog "Le fichier contenant le menuentry personnalisé du grub est introuvable"
    ${ECHO} "${grubcfgfile}"
}

function isAlternateEnv(){
    local suffix=${1:-_alt}
    local rootvg=$(getRootVG)
    isAlternate "${rootvg}" "${suffix}" && return 0
    [ $(${MOUNT} | ${GREP} "${suffix}" | wc -l) -ne 0 ] && return 0 || return 1
}