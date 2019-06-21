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
function clonePartitiontable(){
    local srcdisk=$1
    local tgtdisk=$2
    local partitiontable=$3
    local lockfile="/.BootAlt.lock"
    local sedtgtdisk=$(escapeSlashes ${tgtdisk} )
    local sedsrcdisk=$(escapeSlashes ${srcdisk} ) 
#    local sedtgtdisk=$(echo ${tgtdisk} | escapeSlashes)
#    local sedsrcdisk=$(echo ${srcdisk} | escapeSlashes)    
    [[ ! -f "${partitiontable}" ]] && dumpdiskpartitiontable "${srcdisk}" "${partitiontable} "
    ${SED} -i "s/${sedsrcdisk}/${sedtgtdisk}/g" "${partitiontable}"
    restorediskpartitiontable "${tgtdisk}" "${partitiontable}"
    ${ECHO} "${tgtdisk}" > "${lockfile}"
}

function dumpdiskpartitiontable(){
    local disk=$1
    local savepath=$2
    local diskexists=$(${BLKID} "${disk}")
    [[ -z "${diskexists}" ]]  && writeLog "Le Disque ${disk} est introuvable sur ce serveur";
    local firstpart=$(getNextPV "${disk}")
    local firstpartexists=$(${BLKID} "${firstpart}")
    [[ -z "${firstpartexists}" ]]  && writeLog "Aucune table de partition trouvée sur la Disque ${disk}";
    ${SFDISK} -d ${disk} > ${savepath} || writeLog "Un probleme est survenu lors de la sauvevegarde de la table de partition du Disque ${disk}";
    writeLog "Sauvevegarde de la table de partition du Disque ${disk} terminée" "info";
}

function restorediskpartitiontable(){
    local disk=$1
    local partitiontable=$2
    local diskexists=$(${BLKID} "${disk}")
    [[ -z "${diskexists}" ]]  && writeLog "Le Disque ${disk} est introuvable sur ce serveur";
    [[ ! -f "${partitiontable}" ]] && writeLog "Aucune sauvegarde de la table de partition du Disque  de Boot Alterné n'a été trouvée";
    writeLog "Creation des partitions du Disque de Boot Alterné" "info";
    ${SFDISK} -f ${disk} < ${partitiontable}
    ${SLEEP} 1;
    ${SYNC};${SYNC};${SYNC}
    partprobe 
    writeLog "Creation des partitions terminée" "info";
}

function getDeviceAbsoluteName()
{
    local devpath=$1
    local pcidevname=$(basename ${devpath})
    local pathdir=$(dirname ${devpath})
    local devname=$(${LS} ${pathdir}|${GREP} -i "${pcidevname} "| ${AWK} -F"/" '{print $NF;}')
    [[ -z "${devname}" ]]  && writeLog "Le Disque de destination ${devpath} est introuvable";
    ${ECHO} "/dev/${devname}"
    # pci-0000:00:03.2-usb-0:4.1.1:1.0-scsi-0:0:0:0 -> ../../sd
}

function DiskIsPArted()
{
    local altrootpv=$1
    local pvexists=$(${PVDISPLAY} | ${GREP} -wq "${altrootpv}" && ${ECHO} "true" || ${ECHO} "false")
    ${ECHO}  ${pvexists}
}

