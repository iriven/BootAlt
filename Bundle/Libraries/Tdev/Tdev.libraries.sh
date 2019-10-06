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
function normalizeDeviceName(){
    local devicename="${1}"
    [ -z "${devicename}" ]  && writeLog "Invalid (empty) device name given: $?";
    case "${devicename}" in
        /dev/disk/by-*) devicename=$(${READLINK} -f "${devicename}");;
        *) ;;             
    esac
    ${ECHO} "${devicename}"
}

function diskexists(){
    local disk="$1"
    ${SFDISK} -s ${disk} >/dev/null
    [ $? -ne 0 ] && return 1 || return 0
}


function diskPartitionCount()
{
    local disk="$1"
    diskexists "${disk}" || writeLog "Le disque ${disk} n'existe pas sur ce serveur: $?"
    local nbPart=$(${SFDISK} -l ${disk} 2>/dev/null | ${GREP} "^${disk}" | ${GREP} -v "Empty$"  | wc -l)
    ${ECHO} ${nbPart}
}

function DeviceHasPartitions()
{
    local disk="$1"
    local nbPart=$(diskPartitionCount "${disk}")
    [ "${nbPart}" -ne 0 ] && return 0 || return 1
}

function readDiskGeometry(){
    local disk="$1"
    local osversion=$(getOSVersion)
    diskexists "${disk}" || writeLog "Le disque systeme  ${disk} n'existe pas: $?"
    
    case ${osversion} in
        3|4|5|6) local chsparams=$(${FDISK} -l "${disk}" | ${SED} -r '3!d;s#([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+).*#-H \1 -S \2 -C \3#')
            ;;
        *) local chsparams=$(${SFDISK} -c dos -u cylinders -l "${disk}" | ${SED} -r '3!d;s#([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+).*#-H \1 -S \2 -C \3#')
            ;;
    esac
    ${ECHO} "${chsparams}"
}

function isSystemDisk(){
    local srcdisk="$1"
    local flag=0
    diskexists "${srcdisk}" || writeLog "Le disque systeme : ${tgtdisk} est introuvable: $?"
    for part in $(${SFDISK} -l ${srcdisk} 2>/dev/null | ${GREP} "^${srcdisk}" | ${CUT} -d" " -f1)
    do
        if [ "$(${DF} ${part} 2>/dev/null | ${GREP}  -w ${part} | ${AWK} '{ print $NF }')" = "/boot" ] 
        then
            flag=1
            break;
        fi 
    done
    [ ${flag} -ne 0 ] && return 0 || return 1
}

function getBlockId(){
    local block="$1"
    local stdcheck=$(${LS} /dev/sd* | ${GREP} -w "${block}")
    if [ -z "${stdcheck}" ]
    then
        local lvmcheck=$(${LS} /dev/mapper/* |${GREP} -w "${block}")
        [ -z "${lvmcheck}" ] && writeLog "La Partition ${block} est introuvable sur ce serveur";
    fi 
    local blockid=$(${BLKID} -s UUID -o value "${block}")
    ${ECHO} "${blockid}"
}

function clonePartitiontable(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local partitiontable="${3:-/tmp/$(basename ${srcdisk}).$$}"
    local suffix="${4:-_alt}"   
    if isAlternateEnv; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
    fi
    diskexists "${srcdisk}" || writeLog "Le nom disque systeme ${envtypemsg}: ${srcdisk} est incorrect: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} est introuvable: $?"
    local sedtgtdisk=$(escapeSlashes ${tgtdisk} )
    local sedsrcdisk=$(escapeSlashes ${srcdisk} )
    [[ ! -f "${partitiontable}" ]] && dumpdiskpartitiontable "${srcdisk}" "${partitiontable} "
    ${SED} -i "s/${sedsrcdisk}/${sedtgtdisk}/g" "${partitiontable}"
    restorediskpartitiontable "${tgtdisk}" "${partitiontable}"
}


function dumpdiskpartitiontable(){
    local disk=$(normalizeDeviceName "${1}")
    local savepath="${2}"
    DeviceHasPartitions "${disk}" || writeLog "Aucune table de partition trouvée sur la Disque ${disk}";
    ${SFDISK} -d ${disk} > ${savepath} || writeLog "Un probleme est survenu lors de la sauvevegarde de la table de partition du Disque ${disk}";
    writeLog "Sauvevegarde de la table de partition du Disque ${disk} terminée" "info";
}

function restorediskpartitiontable(){
    local disk=$(normalizeDeviceName "${1}")
    local partitiontable="${2}"
    diskexists "${disk}" || writeLog "Le Disque ${disk} est n'existe sur ce serveur. Impossible de creer la table de partition: $?"
    [ ! -f "${partitiontable}" ] && writeLog "Aucune sauvegarde de la table de partition du Disque  de Boot Alterné n'a été trouvée";
    writeLog "Creation des partitions du Disque de Boot Alterné" "info";
    local partInstance=$(${SFDISK} -f ${disk} < ${partitiontable} 2>/dev/null)
    local returnCode=$?
    local end=0
    ${SLEEP} 2;
    ${SYNC};${SYNC};${SYNC}
    partprobe  >/dev/null 2>&1
    ${SLEEP} 2;
    ${SCSIRESCAN} >/dev/null 2>&1
    while [ ${end} -eq 0 ]; do
        end=1
        for part in $(${SFDISK} -l ${disk}| ${GREP} -v "Empty$" | ${GREP} "^${disk}" | cut -d" " -f1); do
            ls ${part} > /dev/null 2>&1
            if [ $? -ne 0 ]; then
                partprobe >/dev/null 2>&1
                sleep 2
                  ${SYNC};${SYNC};${SYNC}
                ${SCSIRESCAN} >/dev/null 2>&1
                end=0
            fi
        done
    done
    if [ ${returnCode} -ne 0 ]
    then
        ${ECHO} "${partInstance}" | ${GREP} -iq "successfully wrote"
        [ $? -ne 0 ] && writeLog "Erreur lors de la (re-)creation des partitions sur ${disk}: ${returnCode}"
    fi
    ${RM} -f "${partitiontable}"
    writeLog "Creation des partitions terminée" "info";
}

function bootPartitionIndex(){
    local disk=$(normalizeDeviceName "${1}")
    local BootPartitionId=0
    local nbPart=$(diskPartitionCount "${disk}")
    if [[ ${nbPart} -ne 0 ]] ; then
        local BootPartition=$(${SFDISK} -l "${disk}" | ${GREP}  "*"| ${AWK} '{print $1;}')
        [ ! -z "${BootPartition}" ] || writeLog "Aucune partition bootable n'a été trouvée sur le disque ${disk} : $?"
        local BootPartitionId=$(partitionIndex "${BootPartition}")
    fi
    [[ "${BootPartitionId}" -eq 0 ]] && writeLog "Impossible de determiner la partition de boot sur le disque ${disk} : $?"
    ${ECHO} ${BootPartitionId}
}

function partitionIndex(){
    local partition=$(normalizeDeviceName "${1}")
    diskexists "${partition}" || writeLog "nom de partition invalide ${partition}: $?"
    ${ECHO} "${partition}" | ${AWK} -v FPAT="[0-9]+" '{print $NF}'
}

function syncDeviceTopology(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local suffix="${3:-_alt}"
    if isAlternate "${srcdisk}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
    fi
    diskexists "${srcdisk}" || writeLog "Le nom disque systeme ${envtypemsg}: ${srcdisk} est incorrect: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} est introuvable: $?"
    if DeviceHasPartitions "${tgtdisk}"; then
        writeLog "(Re-)Initialisation du disque ${envtypealtmsg} \"${tgtdisk}\"" "info"
        local tgtVGS=($(getDeviceVolumeGroups "${tgtdisk}"))
        local tgtPVS=($(getDevicePhysicalVolumes "${tgtdisk}"))
        [ ! -z "${tgtVGS[*]}" ] && ${VGREMOVE} -ff ${tgtVGS[@]} >/dev/null 2>&1
        [ ! -z "${tgtPVS[*]}" ] && ${PVREMOVE} -ff ${tgtPVS[@]} >/dev/null 2>&1
        ${SYNC};${SYNC};${SYNC}
    fi
    clonePartitiontable "${srcdisk}" "${tgtdisk}"
    writeLog "Preparation du disque ${envtypealtmsg} \"${tgtdisk}\" pour la copie des données" "info"
    for pv in $(getDevicePhysicalVolumes "${srcdisk}") ; do 
        local pvindex=$(partitionIndex "${pv}")
        local partitiontype=$(${SFDISK} --print-id ${srcdisk} ${pvindex})
        if [ "${partitiontype}" == "8e" ]; then
            local altpvname="${tgtdisk}${pvindex}"
            ${PVCREATE} "${altpvname}" 2> /dev/null || writeLog "Erreur lors de la creation du PV ${altpvname} : $?"
            local VGname=$(getVGNameFromPhysicalVolume "${pv}")
            local altVGname=$(alternateEntityName "${VGname}" "${suffix}")
            vgExtendCustom "${altVGname}" "${altpvname}"
        fi
        ${SYNC};${SYNC}
    done
    ${SYNC};${SYNC};${SYNC}
    formatStdPartitions "${srcdisk}" "${tgtdisk}" "${suffix}"
    for srcvg in $(getDeviceVolumeGroups "${srcdisk}"); 
    do
       local tgtvg=$(alternateEntityName "${srcvg}" "${suffix}")
       local srcvgsize=$(getVGSizeMB "${srcvg}")
       local tgtvgsize=$(getVGSizeMB "${tgtvg}")
       if  numberCompare "${srcvgsize}" ">" "${tgtvgsize}"; then
           writeLog "Erreur : la taille du VG de destination (${tgtvg} : ${tgtvgsize} MB) est inférieur à celle de la source (${srcvg} : ${srcvgsize} MB) !"
       fi
       writeLog "Création des FS du VG ${envtypealtmsg} \"${tgtvg}\"" "info"
       for i in $(${LVS} --noheadings --options lv_name,lv_size --units m --nosuffix --separator , "${srcvg}" | ${SED} 's/\s//g')
       do
           if [[ "${i}" =~ (.+),(.+) ]]
           then
               lvname=${BASH_REMATCH[1]}
               lvsize=${BASH_REMATCH[2]}
           else
               writeLog "Ne comprend pas le retour ${i} du lvs"
           fi
           writeLog "Création du LV \"${lvname}\" sur \"${tgtvg}\"" "info"
           ${LVCREATE} -Wy --yes -L "${lvsize}" -n "${lvname}" "${tgtvg}"  >/dev/null 2>&1 || writeLog "Erreur au lvcreate -L ${lvsize} -n ${lvname} ${tgtvg} : $?"
           local fstype=$(getFSType "/dev/mapper/${srcvg}-${lvname}")
           writeLog "Formatage de /dev/mapper/${tgtvg}-${lvname} en \"${fstype}\"" "info"
           if [ "${fstype}" != "swap" ]
           then
               ${MKFS}.${fstype} -q "/dev/${tgtvg}/${lvname}" || writeLog "Erreur au ${MKFS}.${fstype} /dev/${tgtvg}/${lvname} : $?"
           else
               ${MKSWAP} "/dev/${tgtvg}/${lvname}"  >/dev/null 2>&1 || writeLog "Erreur au ${MKSWAP} /dev/${tgtvg}/${lvname} : $?"
           fi
           ${SYNC};${SYNC}
       done
       ${SYNC};${SYNC};${SYNC}
    done
}

function formatStdPartitions(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local suffix="${3:-_alt}"   
    if isAlternateEnv; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
    fi
    diskexists "${srcdisk}" || writeLog "Le nom disque systeme ${envtypemsg}: ${srcdisk} est incorrect: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} est introuvable: $?" 
    local nbsrcPart=$(diskPartitionCount "${srcdisk}")
    local nbtgtPart=$(diskPartitionCount "${tgtdisk}")
    [[ ${nbsrcPart} -ne ${nbtgtPart} ]] && writeLog "La table de partition du disque source doit etre identique à celle de celui de destination: $?"
    local counter=0
    while [[ ${counter} -lt ${nbtgtPart} ]]
    do
        let "counter=counter+1"
        local tgtPartition="${tgtdisk}${counter}"
        local partitiontype=$(${SFDISK} --print-id ${srcdisk} ${counter}) 
        case ${partitiontype} in
            '82')
                writeLog "Formatage de la partition swap ${tgtPartition}" "info"
                local swplabel=$(alternateEntityName "swap" "${suffix}")
                ${MKSWAP} -L "${swplabel}" "${tgtPartition}" || writeLog "Erreur au ${MKSWAP} ${tgtPartition} : $?"
                ;;
            '83')
                local tgtFSType=$(getFSType "${srcdisk}${counter}")
                writeLog "Formatage de la partition de boot ${tgtPartition}" "info"
                ${MKFS}.${tgtFSType} -q "${tgtPartition}" ||  writeLog "Incident inattendu lors du formatage de la partition ${tgtPartition} :$?"
                ;;
            '8e'|'0'|'f'|' f' )
                ;;  
            *)
                writeLog "La partition ${tgtPartition} de type ${partitiontype} n'est pas traitée: $?" "warning"
            ;;                                              
        esac
        ${SYNC};${SYNC};${SYNC}
    done
}