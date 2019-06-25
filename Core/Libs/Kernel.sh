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
#Arguments :
# $1=nom du dev boot dest
# $2=nom du dev grub

function migrateboot() {
    local altbootdev=$(${READLINK} -f $1)
    local altdevname=$2
    local bootwspace="$3"    
    local sbootfstype=$(getFSType "${altbootdev}")
    local osversion=$(getRedhatVersion)
    writeLog "Configuration du secteur de boot sur le disque de boot alterné" "info"
    ${MKDIR} -p ${bootwspace}
    ${MOUNT} -t ${sbootfstype} "${altbootdev}"  ${bootwspace} || writeLog "impossible de monter la partition ${altbootdev} :$?"
    cd ${bootwspace} && ${DUMP} -f - /boot | ${RESTORE} -r -f - || writeLog "echec de copie du /boot: $?"
    case "${osversion}" in
      3|4|5|6)    devicemap="${bootwspace}/grub/device.map" ; grubconfig="${bootwspace}/grub/grub.cfg" ;;
      *)  devicemap="${bootwspace}/grub2/device.map" ; grubconfig="${bootwspace}/grub2/grub.cfg" ;;   
    esac
    permuteGrubMenuEntry "${grubconfig}"
    writeLog "Mise à jour du grub du disque de boot alterné" "info"
    ${GRUBINSTALL} --no-floppy --recheck ${altdevname} > /dev/null || writeLog "Echec de la mise à jour du GRUB: $?"
    ${WAIT}
   cd ~/ &&  ${UMOUNT}  ${bootwspace} || writeLog "impossible de demonter la partition ${altbootdev} :$?"
    writeLog "Configuration du secteur de boot terminé  ................  OK" "info"
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

function getGrubConfigFile(){
    local osversion=$(getRedhatVersion)
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
    local osversion=$(getRedhatVersion)
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
    local osversion=$(getRedhatVersion)
    local grubcfgfile=
    case "${osversion}" in
      3|4|5|6)  grubcfgfile="/boot/grub/grub.conf" ;;
      *)   grubcfgfile="/etc/grub.d/40_custom" ;;
    esac
     [ -f "${grubcfgfile}" ] || writeLog "Le fichier contenant le menuentry personnalisé du grub est introuvable"
    ${ECHO} "${grubcfgfile}"
}

function makeAltBootFS(){
    local altbootdev="$1"
    local sbootfstype=$(fsck -N /boot | awk '/\//{found=1};found{print $5}'|awk -F. '{print $2}')
    local stdcheck=$(${LS} /dev/sd* |${GREP} -w "${altbootdev}")
    [ -z "${stdcheck}" ] && writeLog "La Partition ${altbootdev} est introuvable sur ce serveur :$?";
    writeLog "Formatage de la partition ${altbootdev}" "info"
    ${MKFS}.${sbootfstype} -q "${altbootdev}" ||  writeLog "Incident inattendu lors du formatage de la partition ${altbootdev} :$?"
}
