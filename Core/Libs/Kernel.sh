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

#
# cree_initrd_alt
#
#Cree une version alternee du initrd pour booter sur rootvg_alt
#
#Arguments :
# $1=nom du VG source
# $2=nom du VG dest

function custmkinitrd() {
        local sourcevg=$1
        local destvg=$2
        local initworkspace=$3
        local osversion=$(getRedhatVersion)
        writeLog "Creation d'une image du noyau Linux pour le boot alterné" "info"
        ${RM} -rf "${initworkspace}"
        ${MKDIR} -p "${initworkspace}"
        cd "${initworkspace}"
        case "${osversion}" in

          3|4|5)    ${GZIP} -cd /boot/initrd-$(${UNAME} -r).img | ${CPIO} -imd --quiet
                ${CAT} init | ${SED} -re "s/${sourcevg}/${destvg}/g" > /tmp/init
                ${CP} /tmp/init .
                ${FIND} . | ${CPIO} --quiet -H newc -o | ${GZIP} -9 -n > /boot/initrd-$(${UNAME} -r).BOOTALT.img
                ;;
          *)    ${GZIP} -cd /boot/initramfs-$(${UNAME} -r).img | ${CPIO} -imd --quiet
                ${CAT} init | ${SED} -re "s/${sourcevg}/${destvg}/g" > /tmp/init
                ${CP} /tmp/init .
                ${FIND} . | ${CPIO} --quiet -H newc -o | ${GZIP} -9 -n > /boot/initramfs-$(${UNAME} -r).BOOTALT.img
                ;;
        esac

        writeLog "Fin de Creation d'une image du noyau Linux" "info"
}

#
#
#grub-install --recheck --root-directory=/alt $ALT_DISK
#Arguments :
# $1=nom du dev boot dest
# $2=nom du dev grub

function migrateboot() {
    local altbootdev=$(${READLINK} -f $1)
    local altdevname=$2
    local bootwspace="$3"    
    local sbootfstype=$(fsck -N /boot | awk '/\//{found=1};found{print $5}'|awk -F. '{print $2}')
    local osversion=$(getRedhatVersion)
    writeLog "Configuration du secteur de boot sur le disque de boot alterné" "info"
    ${MKFS}.${sbootfstype} -q "${altbootdev}" ||  writeLog "Incident inattendu lors du formatage de la partition ${altbootdev} :$?"
    ${MKDIR} -p ${bootwspace}
    ${MOUNT} -t ${sbootfstype} "${altbootdev}"  ${bootwspace} || writeLog "impossible de monter la partition ${altbootdev} :$?"
    cd ${bootwspace} && ${DUMP} -f - /boot | ${RESTORE} -r -f - || writeLog "echec de copie du /boot: $?"
    case "${osversion}" in
      3|4|5|6)    devicemap="${bootwspace}/grub/device.map" ; grubconfig="${bootwspace}/grub/grub.cfg" ;;
      *)  devicemap="${bootwspace}/grub2/device.map" ; grubconfig="${bootwspace}/grub2/grub.cfg" ;;   
    esac
    #updateDevicemap "${devicemap}"
    permuteGrubMenuEntry "${grubconfig}"
    writeLog "Mise à jour du grub du disque de boot alterné" "info"
    ${GRUBINSTALL} --no-floppy --recheck --root-directory=$(${DIRNAME} "${bootwspace}") ${altdevname} > /dev/null || writeLog "Echec de la mise à jour du GRUB: $?"
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
