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

function migratevg() 
{
        local origvg=$1
        local altvg=$2
        local Copyworkspace=$3
        writeLog "Copie du ${origvg} vers ${altvg}" "info"
        ${MKDIR} -p ${Copyworkspace}
        for i in `${LVS} --noheadings --options lv_name "${origvg}" | ${SED} 's/\s//g'`
        do
            fs=$(${MOUNT} | ${FGREP} "/dev/mapper/${origvg}-${i}" | ${SED} -re "s/\/dev\/mapper\/${origvg}-${i}\son\s(.*)\stype ext..*/\1/"|head -1)
            if [ -n "${fs}" ]
            then
                ${MKDIR} -p "${Copyworkspace}${fs}"
                fstype=$(${BLKID} "/dev/mapper/${altvg}-${i}" | ${SED} -re 's/.*TYPE="(.*)"/\1/'| ${SED} 's/\s//g')
                if [ "${fstype}" != "swap" ]
                then
                        writeLog "Copie du volume logique: ${i}" "info"
                        ${MOUNT} -t ${fstype} "/dev/mapper/${altvg}-${i}" "${Copyworkspace}${fs}" || writeLog "Erreur au ${MOUNT} /dev/mapper/${altvg}-${i} ${Copyworkspace}${fs} : $?"
                        cd "${Copyworkspace}${fs}" && ${DUMP} -f - "${fs}" | ${RESTORE} -r -f - || writeLog "Echec de copie du ${i}: $?"
                        cd ~/ && ${UMOUNT}  "${Copyworkspace}${fs}" || writeLog "Erreur au ${UMOUNT}  ${Copyworkspace}${fs} : $?"
                fi
            fi
        done
        writeLog "Fin de Copie de ${origvg}" "info"
}

function cleanupFilesystem(){
        local rootpv="$1"
        local altrootpv=$(${READLINK} -f "$2")
        local rootvg="$3"
        local altrootvg="$4"
        local altinfrapv="$5"
        local infravg="$6"
        local altinfravg="$7"
        local lockfile="$8" 
        local rootpvsize=$(getVGTotalPVSizeMB "${rootvg}")
        local altrootpvsize=$(getPVSizeMB "${altrootpv}")
        local infrapvsize=$(getVGTotalPVSizeMB "${infravg}")
        local altinfrapvsize=$(getPVSizeMB "${altinfrapv}")
        [[ -f "${lockfile}" ]] && return 0
        if numberCompare "${rootpvsize}" ">" "${altrootpvsize}"; then
            writeLog "Erreur : le pvsize du FS de destination (${altrootpv} : ${altrootpvsize}) est inférieur à celle de la source (${rootpv} : ${rootpvsize}) !"
        fi
        if numberCompare "${infrapvsize}" ">" "${altinfrapvsize}"; then
            writeLog "Erreur : le pvsize du FS de destination (${altinfrapv} : ${altinfrapvsize}) est inférieur à celle du vg source (${infravg} : ${infrapvsize}) !"
        fi
        writeLog "Reinitialisation des FS du disque de boot alterné" "info"
        ${VGREMOVE} -f "${altrootvg}" 2> /dev/null
        ${PVREMOVE} "${altrootpv}" 2> /dev/null
        ${PVCREATE} "${altrootpv}" 2> /dev/null || writeLog "Erreur lors de la creation du PV ${altrootpv} : $?"
        ${VGCREATE} "${altrootvg}" "${altrootpv}" 2> /dev/null || writeLog "Erreur lors de la creation du VG ${altrootvg} : $?"
        ${VGREMOVE} -f "${altinfravg}" 2> /dev/null
        ${PVREMOVE} "${altinfrapv}" 2> /dev/null
        ${PVCREATE} "${altinfrapv}" 2> /dev/null || writeLog "Erreur lors de la creation du PV ${altinfrapv} : $?"
        ${VGCREATE} "${altinfravg}" "${altinfrapv}" 2> /dev/null || writeLog "Erreur lors de la creation du VG ${altinfravg} : $?"
        ${SYNC};${SYNC};${SYNC}
        for i in $(${LVS} --noheadings --options lv_name,lv_size --units m --nosuffix --separator , "${rootvg}" | ${SED} 's/\s//g')
        do
            if [[ "${i}" =~ (.+),(.+) ]]
            then
                lvname=${BASH_REMATCH[1]}
                lvsize=${BASH_REMATCH[2]}
            else
                writeLog "Ne comprend pas le retour ${i} du lvs"
            fi
            ${LVCREATE} -Wy --yes -L "${lvsize}" -n "${lvname}" "${altrootvg}" > /dev/null || writeLog "Erreur au lvcreate -L ${lvsize} -n ${lvname} ${altrootvg} : $?"
            fstype=$(${BLKID} /dev/mapper/${rootvg}-${lvname} | ${SED} -re 's/.*TYPE="(.*)".*/\1/'| ${SED} 's/\s//g')
            if [ "${fstype}" != "swap" ]
            then
                ${MKFS}.${fstype} -q "/dev/${altrootvg}/${lvname}" || writeLog "Erreur au ${MKFS}.${fstype} /dev/${altrootvg}/${lvname} : $?"
            else
                ${MKSWAP} "/dev/${altrootvg}/${lvname}" || writeLog "Erreur au ${MKSWAP} /dev/${altrootvg}/${lvname} : $?"
            fi
        done
        ${SYNC};${SYNC};${SYNC}
        for i in $(${LVS} --noheadings --options lv_name,lv_size --units m --nosuffix --separator , "${infravg}" | ${SED} 's/\s//g')
        do
            if [[ "${i}" =~ (.+),(.+) ]]
            then
                lvname=${BASH_REMATCH[1]}
                lvsize=${BASH_REMATCH[2]}
            else
                writeLog "Ne comprend pas le retour ${i} du lvs"
            fi
            ${LVCREATE} -Wy --yes -L "${lvsize}" -n "${lvname}" "${altinfravg}" > /dev/null || writeLog "Erreur au lvcreate -L ${lvsize} -n ${lvname} ${altinfravg} : $?"
            fstype=$(${BLKID} /dev/mapper/${infravg}-${lvname} | ${SED} -re 's/.*TYPE="(.*)".*/\1/'| ${SED} 's/\s//g')
            if [ "${fstype}" != "swap" ]
            then
                ${MKFS}.${fstype} -q "/dev/${altinfravg}/${lvname}" || writeLog "Erreur au ${MKFS}.${fstype} /dev/${altinfravg}/${lvname} : $?"
            fi
        done
        ${SYNC};${SYNC};${SYNC}
        writeLog "Reinitialisation des FS terminé" "info"        
}

function getVGTotalPVSizeMB(){
    local vg="$1"
    local vgcheck=$(${VGS} | ${GREP} -w "${vg}")
    local TotalPVSize=0
    [[ -z "${vgcheck}" ]] && writeLog "Le volume Group ${vg} n'existe pas sur ce serveur"
    for pv in $(${VGDISPLAY} -v "${vg}" 2> /dev/null | ${AWK} '/PV Name/ {print $3}')
    do
        PVsizeMB=$(getPVSizeMB "${pv}")
        TotalPVSize=$(${ECHO}  "${TotalPVSize} + ${PVsizeMB}" | bc -l)
    done
    ${ECHO} ${TotalPVSize}
}

function getPVSizeMB(){
    local pv=$1
    local pvcheck=$(${PVS} | ${GREP} -w "${pv}")
    [[ -z "${pvcheck}" ]] && writeLog "Le Physical volume ${pv} n'existe pas sur ce serveur"
    local pvsize=$(${PVS} --noheadings --options pv_size --units m --nosuffix ${pv} | ${TR} -d [:space:])
    ${ECHO} ${pvsize}
}

function getNextPV(){
    local currentpv=$1
    local currentpvid=$(printf '%s' "${currentpv#${currentpv%?}}")
    local currentpvprefix=$(printf '%s' "${currentpv%?}")
    if ! isNumeric "${currentpvid}" ; then
        currentpvid=0
        currentpvprefix="${currentpv}"
    fi
    local nextpartid=$(( currentpvid + 1 ))
    printf '%s' "${currentpvprefix}${nextpartid}"
}  
