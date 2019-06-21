#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Bibliotheque de fonctions utiles à la creation des fichiers             #
#       de gestion des mots de passe de la plateforme D&CB                      #
# ----------------------------------------------------------------------------- #
#       Author: Alfred TCHONDJO - Iriven France                                 #
#       Date: 2017-11-28                                                        #
# ----------------------------------------------------------------------------- #
#       Revisions                                                               #
#                                                                               #
#       G1R0C0 :        Creation du script le 28/11/2017 (AT)                   #
#################################################################################
# Header_end
# set -x
#-------------------------------------------------------------------
#               DECLARATION DES VARIABLES
#-------------------------------------------------------------------

BOOTALT_COMMON_FUNCTION_FILE=${BOOTALT_LIBRARIES_DIRECTORY}/Common.sh
BOOTALT_TDEV_FUNCTION_FILE=${BOOTALT_LIBRARIES_DIRECTORY}/Tdev.sh
BOOTALT_KERN_FUNCTION_FILE=${BOOTALT_LIBRARIES_DIRECTORY}/Kernel.sh
BOOTALT_FS_FUNCTION_FILE=${BOOTALT_LIBRARIES_DIRECTORY}/Filesystem.sh
BOOTALT_PKG_FUNCTION_FILE=${BOOTALT_LIBRARIES_DIRECTORY}/Packages.sh
#-------------------------------------------------------------------
#               DECLARATION DES FONCTIONS
#--------------------------------------------------------------------
function require()
{
   local filepath="$1"
   if [ ! -f "${filepath}" ]; then
        [[ $(basename ${filepath}) =~ ^.watermar* ]] || echo "Le fichier ${filepath} est introuvable!"
        exit 1
   fi
}
require ${BOOTALT_WATERMARK}
require ${BOOTALT_COMMON_FUNCTION_FILE}
require ${BOOTALT_PKG_FUNCTION_FILE}
require ${BOOTALT_TDEV_FUNCTION_FILE}
require ${BOOTALT_KERN_FUNCTION_FILE}
require ${BOOTALT_FS_FUNCTION_FILE}
. ${BOOTALT_WATERMARK}
. ${BOOTALT_COMMON_FUNCTION_FILE}
. ${BOOTALT_PKG_FUNCTION_FILE}
. ${BOOTALT_TDEV_FUNCTION_FILE}
. ${BOOTALT_KERN_FUNCTION_FILE}
. ${BOOTALT_FS_FUNCTION_FILE}

function BootAltInitialize(){
  local tplpath="${1}"
  local altbootdev=$(${READLINK} -f "${2}")
  local altrootvg="${3}"
  local rootpv="${4}"
  local altrootpv=$(${READLINK} -f "${5}")
  local rootvg="${6}"
  local altinfrapv=$(${READLINK} -f "${7}")
  local infravg="${8}"
  local altinfravg="${9}"
  local altdisk=$(${READLINK} -f "${10}")
  local sandisk="${11}"
  local initworkspace="${12}"
  local rootlv="${13}"
  local osversion=$(getRedhatVersion)
  local osrelease=$(getRedhatRelease)
  local tplfile=$(getTemplateFile "${tplpath}")
  local grubcfgfile=$(getGrubConfigFile)
  local padlock="${initworkspace}/tmp/BOOTALT.lock"
  local args=$#
  [[ "${args}" -ne 13 ]]   && writeLog "BootAltInitialize a besoin de 13 arguments ";
  [[ "${osversion}" -lt 5 ]]   && writeLog "Version OS non pris en chage: ${osversion}";
  writeLog "Creation du boot alterne" "info"
  ${MKDIR} -p ${initworkspace}/{boot,root,tmp}
  isparted=$(DiskIsPArted "${altrootpv}")
  if ! isTrue "${isparted}" 
  then
    writeLog "Creation de la table de partition du disque de boot alterne" "info"
    clonePartitiontable "${sandisk}" "${altdisk}" "${tplpath}/.partition.tbl"
    altrootpv=$(${READLINK} -f "${altrootpv}")
    altbootdev=$(${READLINK} -f "${altbootdev}")
    altdisk=$(${READLINK} -f "${altdisk}")
    altinfrapv=$(${READLINK} -f "${altinfrapv}")
    ${PVCREATE} "${altrootpv}" > /dev/null || writeLog "Initialize - Erreur lors de la creation du PV ${altrootpv} : $?"
    ${PVCREATE} "${altinfrapv}" > /dev/null || writeLog "Initialize - Erreur lors de la creation du PV ${altinfrapv} : $?"
    ${VGCREATE} "${altrootvg}" "${altrootpv}" > /dev/null || writeLog "Initialize - Erreur lors de la creation du VG ${altrootvg} : $?"
    ${VGCREATE} "${altinfravg}" "${altinfrapv}" > /dev/null || writeLog "Initialize - Erreur lors de la creation du VG ${altinfravg} : $?"
    ${SYNC};${SYNC};${SYNC}
    cleanupFilesystem "${rootpv}" "${altrootpv}" "${rootvg}" "${altrootvg}" "${altinfrapv}" "${infravg}" "${altinfravg}" "${padlock}"
    [[ ! -f "${padlock}" ]] && touch "${padlock}"
  fi
  if [ -f "${tplfile}" ]
  then
    osplateform=$(${UNAME} -r)
    altBootblkid=$(${BLKID} "${altbootdev}" | ${AWK} -F\" '{print $2}')
    altRootblkid=$(${BLKID} "/dev/mapper/${altrootvg}-${rootlv}" | ${AWK} -F\" '{print $2}')
    isOk=$(${CAT} "${grubcfgfile}"| ${GREP} "BOOTALT" )
    if [ -z "${isOk}" ] 
    then
      writeLog "Verification et ajout d'une entrée BOOTALT dans le Grub Menu" "info"
      ${SED} -e "s/KERNELVERSION/${osplateform}/" "${tplfile}"  >> "${grubcfgfile}"
      ${SED} -i "s/BOOTALTBLKID/${altBootblkid}/" "${grubcfgfile}"
      ${SED} -i "s/ROOTALTBLKID/${altRootblkid}/" "${grubcfgfile}"
      ${SED} -i "s/RELEASEVERSION/${osrelease}/" "${grubcfgfile}"
      ${RM} -f $(${DIRNAME} "${grubcfgfile}")/{20_*,30_*}
      ${SED} -i -e "s/^GRUB_TIMEOUT=.*//g" /etc/default/grub
      ${ECHO} "GRUB_TIMEOUT=10" >> /etc/default/grub
      ${GRUBMKCONFIG} -o /boot/grub2/grub.cfg
      ${SYNC};${SYNC};${SYNC}
    fi
  fi
  cleanupFilesystem "${rootpv}" "${altrootpv}" "${rootvg}" "${altrootvg}" "${altinfrapv}" "${infravg}" "${altinfravg}" "${padlock}"
  [[ -f "${padlock}" ]] && ${RM} -f "${padlock}"
}

function BootAltExecute(){
    local altbootdev=$(${READLINK} -f "${1}")
    local altdisk=$(${READLINK} -f "${2}")
    local rootvg=$3
    local altrootvg=$4
    local infravg=$5
    local altinfravg=$6 
    local exeworkspace=$7
    local args=$#
    [[ "${args}" -ne 7 ]]   && writeLog "BootAltExecute a besoin de 7 arguments ";
    writeLog "Migration des données vers le disque de boot alterné" "info"
    ${MKDIR} -p ${exeworkspace}/{boot,root,infra}
    migrateboot "${altbootdev}" "${altdisk}" "${exeworkspace}/boot"
    migratevg "${rootvg}" "${altrootvg}" "${exeworkspace}/root"
    migratevg "${infravg}" "${altinfravg}" "${exeworkspace}/infra"
    writeLog "Fin de Migration des données" "info"
}

function BootAltClose(){
    local altbootdev=$(${READLINK} -f $1)
    local altrootvg=$2 
    local altrootlv=$3
    local infravg=$4
    local altinfravg=$5 
    local Closeworkspace=$6
    local rootvg=$7
    local bootwspace="${Closeworkspace}/boot"
    local rootwspace="${Closeworkspace}/root"
    local sbootfstype=$(${FSCK} -N /boot | ${AWK} '/\//{found=1};found{print $5}'|${AWK} -F. '{print $2}') 
    local altrootfstype=$(${BLKID} "/dev/mapper/${altrootvg}-${altrootlv}" | ${SED} -re 's/.*TYPE="(.*)"/\1/')
    local altbootuuid=$(${BLKID} ${altbootdev}|${AWK} -F\" '{print $2}')
    local osversion=$(getRedhatVersion)
    local args=$#
    [[ "${args}" -ne 7 ]]   && writeLog "BootAltClose a besoin de 7 arguments";   
    ${MKDIR} -p ${Closeworkspace}/{root,boot}/
    ${SYNC};${SYNC};${SYNC}
    ${MOUNT} -t ${sbootfstype} "${altbootdev}"  "${bootwspace}" || writeLog "impossible de monter la partition ${altbootdev} :$?"
    ${MOUNT} -t ${altrootfstype} "/dev/mapper/${altrootvg}-${altrootlv}"  "${rootwspace}" || writeLog "impossible de monter le FS /dev/mapper/${altrootvg}-${altrootlv} :$?"
    writeLog "Mise à jour des fichiers de configuration systeme du boot alterné" "info"
    ${SED} -i "s/${rootvg}/${altrootvg}/g" "${rootwspace}/etc/default/grub"
    ${SED} -i "s/${rootvg}/${altrootvg}/g" "${rootwspace}/etc/fstab"
    ${SED} -i "s/${infravg}/${altinfravg}/g" "${rootwspace}/etc/fstab"
    ${SED} -i -e "s/\(.*\)=\(.*\s\)\(\/boot\s.*\)/\1=${altbootuuid} \3/g" "${rootwspace}/etc/fstab"	
    writeLog "Fin de Mise à jour des fichiers de configuration systeme " "info"
    writeLog "Creation d'une image du noyau Linux sur le disque de boot alterné" "info"
      case "${osversion}" in
        3|4|5)   cd ${bootwspace} &&  ${MKINITRD} -f --fstab=${rootwspace}/etc/fstab ${bootwspace}/initrd-$(${UNAME} -r).BOOTALT.img $(${UNAME} -r) ;;
        *)   cd ${bootwspace} &&  ${MKINITRD} -f --fstab=${rootwspace}/etc/fstab ${bootwspace}/initramfs-$(${UNAME} -r).BOOTALT.img $(${UNAME} -r) ;;
      esac
      ${SYNC};${SYNC};${SYNC}
      ${RM} -f /boot/*-$(${UNAME} -r).BOOTALT.*
      ${CP} ${bootwspace}/*-$(${UNAME} -r).BOOTALT.* /boot
      cd ~/ && ${UMOUNT} ${Closeworkspace}/{root,boot}  || writeLog "Erreur au ${UMOUNT} ${Closeworkspace}/{root,boot} : $?"
    ${RM} -rf "${Closeworkspace}"
    writeLog "Fin de la creation du boot alterne" "info"
}

