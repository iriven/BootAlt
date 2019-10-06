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
function getRootFS(){
    ${DF} -P / | ${TAIL} -1 | ${AWK} '{ print $1 }'
}

function getRootVG(){
    local rootvg=$(getRootFS | ${SED} "s/\/dev\(\/[^\/]*\/*\)\([^-]*\)\([-\/]\)\([^-]*\)$/\\2/")
    ${ECHO} "${rootvg}"
}

function getRootLV(){
    local rootlv=$(getRootFS | ${SED} "s/\/dev\(\/[^\/]*\/*\)\([^-]*\)\([-\/]\)\([^-]*\)$/\\4/")
    ${ECHO} "${rootlv}"
}

function migratevg() 
{
    local origvg=$1
    local altvg=$2
    local Copyworkspace=$3
    writeLog "Copie du ${origvg} vers ${altvg}" "info"
    ${MKDIR} -p ${Copyworkspace}
    for i in `${LVS} --noheadings --options lv_name "${origvg}" | ${SED} 's/\s//g'`
    do
        fs=$(${MOUNT} | ${GREP} "/dev[^[:space:]]*/${origvg}\([-\/]\)${i}[[:space:]]" | ${SED} -re "s/\/dev[^[:space:]]*\/${origvg}[-\/]${i}\son\s(.*)\stype ext..*/\1/"|head -1)
        if [ -n "${fs}" ]
        then
            ${MKDIR} -p "${Copyworkspace}${fs}"
            fstype=$(getFSType "/dev/mapper/${altvg}-${i}")
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

function getVGFilesystemList(){
    local vgname=$1
    local output=()
    for lv in $(${LVS} --noheadings --options lv_name "${vgname}" | ${SED} 's/\s//g')
    do
        output+=("/dev/mapper/${vgname}-${lv}")
    done
    ${ECHO} "${output[@]}"
}

function getDeviceStdFilesystemList(){

    local device=$(normalizeDeviceName "${1}")
    local local output=()  
    diskexists "${device}" || writeLog "${device} n'est pas un nom de disque connu sur ce serveur: $?"
    local nbPart=$(diskPartitionCount "${device}")
    [ ${nbPart} -ne 0 ] || writeLog "Aucune partition trouvée sur le disque: ${device}"
    local counter=0
    while [ ${counter} -lt ${nbPart} ]
    do
        counter=$(expr ${counter} + 1)
        local partitiontype=$(${SFDISK} --print-id ${device} ${counter})
        case ${partitiontype} in
            '8e'|'0'|'f'|' f' )
                ;;  
            *)
                output+=("${device}${counter}")
            ;;                                              
        esac
    done
    ${ECHO} "${output[@]}"
}

function migrateStdFilesystem(){
    local srcdisk=$(normalizeDeviceName "${1}")  
    local tgtdisk=$(normalizeDeviceName "${2}") 
    local counter="${3}"
    local exeworkspace="${4}"
    local srcPartition="${srcdisk}${counter}"
    local tgtPartition="${tgtdisk}${counter}"
    local partitiontype=$(${SFDISK} --print-id ${srcdisk} ${counter}) 
    if [ "${partitiontype}" == "83" ]; then
      local sedfspattern=$(escapeSlashes "${srcPartition}")
      local srcfsmountpoint=$(${MOUNT} | ${GREP} "${srcPartition}[[:space:]]" | ${SED} -re "s/${sedfspattern}\son\s(.*)\stype ext..*/\1/"|head -1)
      if [ -n "${srcfsmountpoint}" ]
      then
        local fstype=$(getFSType "${srcPartition}")
        local tgtfsmountpoint="${exeworkspace}${srcfsmountpoint}"
        writeLog "Copie de ${srcfsmountpoint} vers ${tgtfsmountpoint}" "info"
        ${MKDIR} -p ${tgtfsmountpoint}
        ${SYNC};${SYNC}
        ${MOUNT} -t ${fstype} "${tgtPartition}"  ${tgtfsmountpoint} || writeLog "impossible de monter la partition ${tgtPartition} :$?"
        cd ${tgtfsmountpoint} && ${DUMP} -f - ${srcfsmountpoint} | ${RESTORE} -r -f - || writeLog "echec de copie du ${srcfsmountpoint}"
        cd ~/ &&  ${UMOUNT}  ${tgtfsmountpoint} || writeLog "Impossible de demonter la partition ${tgtfsmountpoint} :$?"
        writeLog "Copie de ${srcfsmountpoint} terminée  ................  OK" "info"
      fi
      ${SYNC};${SYNC};${SYNC}
    fi
}

function getFSPartner(){
  local fs=$(normalizeDeviceName "${1}")
  local tgtdisk=$(normalizeDeviceName "${2}")
  local suffix="${3:-_alt}"
  diskexists "${fs}" || writeLog "Le Filesystem: ${fs} n'existe pas: $?"
  diskexists "${tgtdisk}" || writeLog "Le disque : ${tgtdisk} est introuvable: $?"
  if [[ "${fs}" =~ ^/dev[^[:space:]]+/([^-]+)([-\/])([^-]+)$ ]] ; then
      local srcvgname=$(${ECHO} "${fs}" | ${SED} "s/\/dev\(\/[^\/]*\/*\)\([^-]*\)\([-\/]\)\([^-]*\)$/\\2/") 
      local tgtvgname=$(alternateEntityName "${srcvgname}" "${suffix}")
      local homologue=$(${ECHO} "${fs}" |${SED} "s/${srcvgname}/${tgtvgname}/")    
  else
      local offset=$(partitionIndex "${fs}")
      local homologue="${tgtdisk}${offset}"
      diskexists "${homologue}" || writeLog "La partition: ${homologue} n'existe pas: $?"
  fi
  ${ECHO} "${homologue}"
}

function getVGSizeMB(){
    local vg="$1"
    local vgcheck=$(${VGS} | ${GREP} -w "${vg}")
    local TotalPVSize=0
    [[ -z "${vgcheck}" ]] && writeLog "Le volume Group ${vg} n'existe pas sur ce serveur"
    for pv in $(${VGS} -o pv_name --noheadings "${vg}" 2> /dev/null)
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

function getFSType(){
    local block="$1"
    local stdcheck=$(${LS} /dev/sd* |${GREP} -w "${block}")
    if [ -z "${stdcheck}" ]
    then
        local lvmcheck=$(${LS} /dev/mapper/* |${GREP} -w "${block}")
        [ -z "${lvmcheck}" ] && writeLog "Le Filesystem ${block} est introuvable sur ce serveur: $?";
    fi
    local fstype=$(${BLKID} -s TYPE -o value "${block}")
    ${ECHO} "${fstype}"
} 

function getVGPhysicalVolumes(){
    local vgname="$1"
    local vgcheck=$(${VGS} |${GREP} -w "${vgname}")
    [ -z "${vgcheck}" ]  && writeLog "Le VG ${vgname} est introuvable sur ce serveur";
    local output=($(${VGS} --options pv_name --noheadings "${vgname}"))
    ${ECHO} "${output[@]}"
}

function countDevicePhysicalVolumes(){
    local disk=$(normalizeDeviceName "${1}")
    local pvnum=$(getDevicePhysicalVolumes "${disk}" | wc -l )
    ${ECHO} ${pvnum}
}

function getDevicePhysicalVolumes(){
    local disk=$(normalizeDeviceName "${1}")
    diskexists "${disk}" || writeLog "Le disque ${disk} est introuvable sur ce serveur: $?";
    ${PVS} --noheadings --options pv_name 2>/dev/null|${AWK} -v TGTDISK="${disk}" '$1~TGTDISK"[0-9]*$" { print $1 }'
}

function getVGNameFromPhysicalVolume(){
    local pv="$1"
    diskexists "${pv}" || writeLog "Le PV ${pv} est introuvable sur ce serveur: $?";
    ${PVS} --noheadings --options pv_name,vg_name 2>/dev/null|${AWK} -v TGTDISK="${pv}" '$1~TGTDISK"[0-9]*$" { print $2 }'
}

function vgExtendCustom(){
    local vgname="$1"
    local pvname="$2"
    local vgcheck=$(${VGS} --noheadings --options vg_name | ${GREP} -w "${vgname}")
    local pvcheck=$(${PVS}  --noheadings --options pv_name | ${GREP} -w "${pvname}")
    [ -z "${pvcheck}" ] && writeLog "Le PV \"${pvname}\" n'existe pas sur ce serveur: impossible de l'associer au VG \"${vg}\""
    if [ -z "${vgcheck}" ] ; then
        ${VGCREATE} "${altVGname}" "${altpvname}" 2> /dev/null || writeLog "Erreur lors de la creation du VG \"${altVGname}\" : $?"
    else
        ${VGEXTEND} "${altVGname}" "${altpvname}" 2> /dev/null || writeLog "Erreur lors de l'ajout du PV \"${altpvname}\" dans le VG \"${altVGname}\" : $?"
    fi
}


function getDeviceVolumeGroups(){
    local disk=$(normalizeDeviceName "${1}")
    local vglist=();
    diskexists "${disk}" || writeLog "Le disque ${disk} est introuvable sur ce serveur: $?";
    local totalpv=$(countDevicePhysicalVolumes "${disk}")
    if [ ${totalpv} -ne 0 ]
    then
        for pv in $(getDevicePhysicalVolumes "${disk}"); do
            local vgname=$(getVGNameFromPhysicalVolume "${pv}")
            vglist+=("${vgname}")
        done
        vglist=($(${ECHO} "${vglist[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    fi
    ${ECHO} "${vglist[@]}"
}