#!/usr/bin/env bash
# Header_start
#################################################################################
#                                                                               #
#       Fichier de Configuration du Script de creation du boot alterné        #
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
#               DECLARATION DES VARIABLES
#-------------------------------------------------------------------
BOOTALT_COMMONLIB_DIRECTORY="${BOOTALT_LIB_DIRECTORY}/Common"
BOOTALT_TDEVLIB_DIRECTORY="${BOOTALT_LIB_DIRECTORY}/Tdev"
BOOTALT_KERNLIB_DIRECTORY="${BOOTALT_LIB_DIRECTORY}/Kernel"
BOOTALT_FSLIB_DIRECTORY="${BOOTALT_LIB_DIRECTORY}/Filesystem"
BOOTALT_PKGLIB_DIRECTORY="${BOOTALT_LIB_DIRECTORY}/Packages"

BOOTALT_COMMONFUNC_FILE="${BOOTALT_COMMONLIB_DIRECTORY}/Common.libraries.sh"
BOOTALT_TDEVFUNC_FILE="${BOOTALT_TDEVLIB_DIRECTORY}/Tdev.libraries.sh"
BOOTALT_KERNFUNC_FILE="${BOOTALT_KERNLIB_DIRECTORY}/Kernel.libraries.sh"
BOOTALT_FSFUNC_FILE="${BOOTALT_FSLIB_DIRECTORY}/Filesystem.libraries.sh"
BOOTALT_PKGFUNC_FILE="${BOOTALT_PKGLIB_DIRECTORY}/Packages.libraries.sh"
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
require ${BOOTALT_XCOPY_FILE}
require ${BOOTALT_COMMONFUNC_FILE}
require ${BOOTALT_PKGFUNC_FILE}
require ${BOOTALT_TDEVFUNC_FILE}
require ${BOOTALT_KERNFUNC_FILE}
require ${BOOTALT_FSFUNC_FILE}
. ${BOOTALT_XCOPY_FILE}
. ${BOOTALT_COMMONFUNC_FILE}
. ${BOOTALT_PKGFUNC_FILE}
. ${BOOTALT_TDEVFUNC_FILE}
. ${BOOTALT_KERNFUNC_FILE}
. ${BOOTALT_FSFUNC_FILE}

function BootAltInitialize(){
  local srcdisk=$(normalizeDeviceName "${1}")  
  local tgtdisk=$(normalizeDeviceName "${2}")
  local tplpath="${3}"
  local initworkspace="${4}"
  local suffix=${5:-_alt}
  local args=$#
  [[ "${args}" -lt 4 ]]   && writeLog "BootAltInitialize a besoin de 5 arguments ";
  local osversion=$(getOSVersion)
  [[ "${osversion}" -lt 5 ]]   && writeLog "Version OS non pris en chage: ${osversion}";

  if isAlternate "${srcdisk}"; then
      local envtypemsg='alterné'; 
      local envtypealtmsg='nominal'; 
  else
      local envtypemsg='nominal'; 
      local envtypealtmsg='alterné';
  fi
  diskexists "${srcdisk}" || writeLog "Le nom disque systeme ${envtypemsg}: ${srcdisk} est incorrect: $?"
  diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} est introuvable: $?"

  writeLog "Debut de Creation d'un environnement de boot alterne" "info"
  checkPrerequisites "${srcdisk}" "${tgtdisk}" "${suffix}"
  ${MKDIR} -p ${initworkspace}
  syncDeviceTopology "${srcdisk}" "${tgtdisk}" "${suffix}"

  local osrelease=$(getOSRelease)  
  local tplfile=$(getTemplateFile "${tplpath}")
  local custcfgfile=$(getCustGrubConfigFile)
  if [ -f "${tplfile}" ]
  then
   local osplateform=$(${UNAME} -r)
   local srcBootindex=$(bootPartitionIndex "${srcdisk}")
   local srcRootFS=$(getRootFS)
   local srcBootFS="${srcdisk}${srcBootindex}"

   local tgtRootFS=$(getFSPartner "${srcRootFS}" "${tgtdisk}" "${suffix}")
   local tgtBootFS=$(getFSPartner "${srcBootFS}" "${tgtdisk}" "${suffix}")
   local tgtRootFSescaped=$(escapeSlashes "${tgtRootFS}")

   local tgtBootblkid=$(getBlockId "${tgtBootFS}")
   local tgtRootblkid=$(getBlockId "${tgtRootFS}")

   local tgtRootVG=$(alternateEntityName "$(getRootVG)" "${suffix}")
   local tgtRootLV=$(getRootLV)

    removeTextBetweenMarkers "menuentry" "}" "${custcfgfile}"
      writeLog "Verification et ajout d'une entrée BOOTALT dans le Grub Menu" "info"
      ${SED} -e "s/KERNELVERSION/${osplateform}/" "${tplfile}" >> "${custcfgfile}"
      ${SED} -i "s/BOOTALTBLKID/${tgtBootblkid}/" "${custcfgfile}"
      ${SED} -i "s/ROOTALTBLKID/${tgtRootblkid}/" "${custcfgfile}"
      ${SED} -i "s/RELEASEVERSION/${osrelease}/" "${custcfgfile}"
      ${SED} -i "s/ROOTALTFILESYSTEM/${tgtRootFSescaped}/" "${custcfgfile}"
      ${SED} -i "s/ROOTALTVG/${tgtRootVG}/" "${custcfgfile}"
      ${SED} -i "s/ROOTALTLV/${tgtRootLV}/" "${custcfgfile}"

      ${SED} -i '/^$/d' "${custcfgfile}"
      ${CHMOD} a+x "${custcfgfile}"
      ${RM} -f $(${DIRNAME} "${custcfgfile}")/{20_*,30_*}
      ${SED} -i -e "s/^GRUB_TIMEOUT=.*//g" /etc/default/grub
      ${ECHO} "GRUB_TIMEOUT=10" >> /etc/default/grub
      ${GRUBMKCONFIG} -o /boot/grub2/grub.cfg
      ${SYNC};${SYNC};${SYNC}
  fi
}

function BootAltExecute(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local exeworkspace="${3}"    
    local suffix=${4:-_alt}
    local args=$#
    [[ "${args}" -lt 3 ]]   && writeLog "BootAltExecute a besoin de 4 arguments ";
    if isAlternate "${srcdisk}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
    fi
    diskexists "${srcdisk}" || writeLog "Le nom disque systeme ${envtypemsg}: ${srcdisk} est incorrect: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} est introuvable: $?"
    writeLog "DEBUT DE MIGRATION DES DONNEES VERS LE DISQUE ALTERNE." "info"
    ${MKDIR} -p ${exeworkspace}
    ${SLEEP} 2
    local nbsrcPart=$(diskPartitionCount "${srcdisk}")
    local nbtgtPart=$(diskPartitionCount "${tgtdisk}")
    [ ${nbsrcPart} -ne ${nbtgtPart} ] && writeLog "La table de partition du disque source doit etre identique à celle de celui de destination: $?"
    local counter=0
    while [ ${counter} -lt ${nbtgtPart} ]
    do
      let "counter=counter+1"
      migrateStdFilesystem "${srcdisk}" "${tgtdisk}" "${counter}" "${exeworkspace}"
    done
    local srcrootvg=$(getRootVG)
    local tgtrootvg=$(alternateEntityName "${srcrootvg}" "${suffix}")
    migratevg "${srcrootvg}" "${tgtrootvg}" "${exeworkspace}"
    for srcvg in $(getDeviceVolumeGroups "${srcdisk}"); do
      local tgtvg=$(alternateEntityName "${srcvg}" "${suffix}")
      [ "${srcvg}" != "${srcrootvg}" ] && migratevg "${srcvg}" "${tgtvg}" "${exeworkspace}"
      ${SYNC};${SYNC};${SYNC}
    done
    writeLog "FIN DE MIGRATION DES DONNEES." "info"
}


function BootAltClose(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local Closeworkspace=$3
    local suffix=${4:-_alt}
    local args=$#
    [[ "${args}" -lt 3 ]]   && writeLog "BootAltClose a besoin de 4 arguments";       
    if isAlternate "${srcdisk}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
    fi
    diskexists "${srcdisk}" || writeLog "Le nom disque systeme ${envtypemsg}: ${srcdisk} est incorrect: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} est introuvable: $?"
    local osversion=$(getOSVersion)
    local bootwspace="${Closeworkspace}/boot"
    local rootwspace="${Closeworkspace}"
    local srcBootindex=$(bootPartitionIndex "${srcdisk}")
    local srcRootFS=$(getRootFS)
    local srcBootFS="${srcdisk}${srcBootindex}"
    local tgtRootFS=$(getFSPartner "${srcRootFS}" "${tgtdisk}" "${suffix}")
    local tgtBootFS=$(getFSPartner "${srcBootFS}" "${tgtdisk}" "${suffix}")
    local tgtBootblkid=$(getBlockId "${tgtBootFS}")
    local tgtRootblkid=$(getBlockId "${tgtRootFS}")
    local tgtBootFStype=$(getFSType "${tgtBootFS}") 
    local tgtRootFStype=$(getFSType "${tgtRootFS}")   
    local srcrootvg=$(getRootVG)
    local tgtRootVG=$(alternateEntityName "${srcrootvg}" "${suffix}")
    local custcfgfile=$(getCustGrubConfigFile)

    ${MKDIR} -p "${rootwspace}"
    ${SYNC};${SYNC}
    ${MOUNT} -t ${tgtRootFStype} "${tgtRootFS}"  "${rootwspace}" || writeLog "impossible de monter le FS ${tgtRootFS} :$?"
    ${MKDIR} -p "${bootwspace}"
    ${SYNC};${SYNC}
    ${MOUNT} -t ${tgtBootFStype} "${tgtBootFS}"  "${bootwspace}" || writeLog "impossible de monter la partition ${tgtBootFS} :$?"
    writeLog "Mise à jour des fichiers de configuration systeme du boot alterné" "info"
    for srcvg in $(getDeviceVolumeGroups "${srcdisk}"); do
      local tgtvg=$(alternateEntityName "${srcvg}" "${suffix}")
      [ "${srcrootvg}" == "${srcvg}" ] && ${SED} -i "s/\/${srcvg}\(\[-\/]\)/\/${tgtvg}\1/g" "${rootwspace}/etc/default/grub"
      ${SED} -i -e "s/\/dev\(\/[^\/]*\/*\)${srcvg}\([-\/]\)\([^-]*\)$/\/dev\\1${tgtvg}\\2\\3/g" "${rootwspace}/etc/fstab"
      for fs in $(getVGFilesystemList "${srcvg}"); do
        local fspartner=$(getFSPartner "${fs}" "${tgtdisk}" "${suffix}")
        local fsblkid=$(getBlockId "${fs}")
        local fspartnerblkid=$(getBlockId "${fspartner}")
        ${SED} -i "s/${fsblkid}/${fspartnerblkid}/Ig" "${rootwspace}/etc/fstab"
      done
      ${SYNC};${SYNC};${SYNC}
    done
    for stdfs in $(getDeviceStdFilesystemList "${srcdisk}"); do
        local stdfspartner=$(getFSPartner "${stdfs}" "${tgtdisk}" "${suffix}")
        local stdfsblkid=$(getBlockId "${stdfs}")
        local stdfspartnerblkid=$(getBlockId "${stdfspartner}")
        local stdfsescaped=$(escapeSlashes "${stdfs}")
        local stdfspartnerescaped=$(escapeSlashes "${stdfspartner}")
        ${SED} -i "s/${stdfsblkid}/${stdfspartnerblkid}/Ig" "${rootwspace}/etc/fstab"
        ${SED} -i "s/${stdfsescaped}/${stdfspartnerescaped}/g" "${rootwspace}/etc/fstab"
    done
    writeLog "Fin de Mise à jour des fichiers de configuration systeme " "info"
    if isAlternateEnv "${suffix}"; then
        local srcbiosdevname="hd1"
        local tgtbiosdevname="hd0"
        local srcbiosdevahci="ahci1"
        local tgtbiosdevahci="ahci0"
        local removeBootalt=1
        local initrdTag=""         
    else
        local srcbiosdevname="hd0"
        local tgtbiosdevname="hd1"
        local srcbiosdevahci="ahci0"
        local tgtbiosdevahci="ahci1"
        local removeBootalt=0 
        local initrdTag=".BOOTALT" 

    fi
    local tgtRootFSescaped=$(escapeSlashes "${tgtRootFS}")
    local srcRootFSescaped=$(escapeSlashes "${srcRootFS}")
    ${SED} -i "s/${tgtbiosdevname}/${srcbiosdevname}/Ig" "${rootwspace}${custcfgfile}"
    ${SED} -i "s/${tgtbiosdevahci}/${srcbiosdevahci}/Ig" "${rootwspace}${custcfgfile}"
    ${SED} -i "s/${tgtBootblkid}/${srcBootblkid}/g" "${rootwspace}${custcfgfile}"
    ${SED} -i "s/${tgtRootblkid}/${srcRootblkid}/g" "${rootwspace}${custcfgfile}"
    ${SED} -i "s/${tgtRootFSescaped}/${srcRootFSescaped}/g" "${rootwspace}${custcfgfile}"
    ${SED} -i "s/${tgtRootVG}/${srcrootvg}/g" "${rootwspace}${custcfgfile}"
   
    if [ "${removeBootalt}" -ne 0 ]; then
          ${SED} -i -re  "s/[[:space:]]*[(]BOOTALT[)]//g" "${rootwspace}${custcfgfile}"
          ${SED} -i -re  "s/[.]BOOTALT//g" "${rootwspace}${custcfgfile}"
    fi
    case "${osversion}" in
      3|4|5|6)    local grubconfig="${bootwspace}/grub/grub.cfg"; grubdefaulconfig= ;;
      *)  local grubconfig="${bootwspace}/grub2/grub.cfg"; grubdefaulconfig="${rootwspace}/etc/default/grub" ;;   
    esac
    [ -f "${grubdefaulconfig}" ] && ${SED} -i "s/${srcrootvg}/${tgtRootVG}/g" "${grubdefaulconfig}"
    permuteGrubMenuEntry "${grubconfig}"
    installBootLoader "${srcdisk}"
    installBootLoader "${tgtdisk}"
    writeLog "Creation d'une image du noyau Linux sur le disque de boot alterné" "info"
    #yum --releasever=/ --installroot=${Closeworkspace} install iputils vim
    for dir in /proc /sys /dev /run /dev/pts; do ${MKDIR} -p "${Closeworkspace}${dir}"; done
    #${MOUNT} -t proc   /proc        "${Closeworkspace}/proc"
    #${MOUNT} -t sysfs  /sys         "${Closeworkspace}/sys"
    #${MOUNT} -o bind   /dev        "${Closeworkspace}/dev"
    #${MOUNT} -o bind   /run        "${Closeworkspace}/run"
    #${MOUNT} -o bind   /dev/pts    "${Closeworkspace}/dev/pts"
    #${CHROOT} "${Closeworkspace}" ${GRUBMKCONFIG} -o ${CONFGRUBFILE}
    #${SLEEP} 5
      case "${osversion}" in
        3|4|5)   cd ${bootwspace} &&  ${MKINITRD} -f --fstab=${rootwspace}/etc/fstab ${bootwspace}/initrd-$(${UNAME} -r)${initrdTag}.img $(${UNAME} -r) ;;
        *)   cd ${bootwspace} &&  ${MKINITRD} -f --fstab=${rootwspace}/etc/fstab ${bootwspace}/initramfs-$(${UNAME} -r)${initrdTag}.img $(${UNAME} -r) ;;
      esac
    #${UMOUNT}   "${Closeworkspace}/proc"    >/dev/null 2>&1 
    #${UMOUNT}   "${Closeworkspace}/sys"     >/dev/null 2>&1 
    #${UMOUNT}   "${Closeworkspace}/run"     >/dev/null 2>&1 
    #${UMOUNT}   "${Closeworkspace}/dev/pts" >/dev/null 2>&1  
    #${UMOUNT}   "${Closeworkspace}/dev"    >/dev/null 2>&1     
    ${SYNC};${SYNC};${SYNC}
    ${RM} -f /boot/*-$(${UNAME} -r)${initrdTag}.img
    ${CP} ${bootwspace}/*-$(${UNAME} -r)${initrdTag}.img /boot
    cd ~/ && ${UMOUNT} ${bootwspace}  || writeLog "Erreur au ${UMOUNT} ${Closeworkspace}/{root,boot} : $?"
    ${UMOUNT} ${rootwspace}
    ${RM} -rf "${Closeworkspace}"
    [ -f /var/run/${PROG}.pid ] && ${RM} -rf "/var/run/${PROG}.pid"
    writeLog "Fin de la creation du boot alterne" "info"
}


function checkPrerequisites(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local suffix="${3:-_alt}"
    writeLog "VERIFICATION DES PREREQUIS SYSTEMES ET LOGICIELS" "info"
    if isAlternate "${srcdisk}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
    fi
    diskexists "${srcdisk}" || writeLog "Le disque systeme ${envtypemsg}: ${srcdisk} n'existe pas: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} n'existe pas: $?"
    [ "${srcdisk}" != "${tgtdisk}" ] || writeLog "Le disque systeme source et celui de destination sont identiques: $?"
    writeLog "Recherche du disque OS actuel" "info"
    local currentOSdisk=$(getCurrentOSDevice)
    [ "${srcdisk}" == "${currentOSdisk}" ] || writeLog "Le disque systeme source ne correspond pas au disque OS actuel: $?"
    writeLog "${srcdisk} correspond bien au disque OS .......... OK" "info"
    for file in "${CONFGRUBFILE}" "${FSTAB}"; do [ ! -s "${file}" ] && writeLog "Le Fichier ${file} est absent ou vide: $?"; done #"${DEVMAPFILE}" 
    #local srcbiosdevname=$(${GREP} ${srcdisk} ${DEVMAPFILE} | ${GREP} -v "^#" | ${AWK} '{ print $1 }'| ${SED} 's/[()]//g')
    #local tgtbiosdevname=$(${GREP} ${tgtdisk} ${DEVMAPFILE} | ${GREP} -v "^#" | ${AWK} '{ print $1 }'| ${SED} 's/[()]//g')
    #[ ! -z "${srcbiosdevname}" ] ||  writeLog "Nom 'bios' du Disque ${envtypemsg} ${srcdisk} absent dans ${DEVMAPFILE}. Ajouter le manuellement si necessaire: $?"
    #[ ! -z "${tgtbiosdevname}" ] ||  writeLog "Nom 'bios' du Disque ${envtypealtmsg} ${tgtdisk} absent dans ${DEVMAPFILE}. Ajouter le manuellement si necessaire: $?"
    #writeLog "Disque ${envtypemsg}  : ${srcdisk}  (nom 'bios' pour GRUB : ${srcbiosdevname})" "info"
    #writeLog "Disque ${envtypealtmsg}  : ${tgtdisk}  (nom 'bios' pour GRUB : ${tgtbiosdevname})" "info"
    writeLog "Vérification des contraintes liées à la taille des disques." "info"
    local srcdisksize=$(${SFDISK} -s ${srcdisk} >/dev/null)
    local tgtdisksize=$(${SFDISK} -s ${tgtdisk} >/dev/null)
    local srcdisksizeGB=$(( (${srcdisksize} + ((1024 * 1024) + 1)) / (1024 * 1024)))
    local tgtdisksizeGB=$(( (${tgtdisksize} + ((1024 * 1024) + 1)) / (1024 * 1024)))
    writeLog "CAPACITE DISQUE OS:       ${srcdisksizeGB} GB" "info"
    writeLog "CAPACITE DISQUE ALTERNE:  ${tgtdisksizeGB} GB" "info"
    if numberCompare "${srcdisksize}" ">" "${tgtdisksize}"; then
       isAlternateEnv || writeLog "La capacite disque ${envtypealtmsg} (${tgtdisk}) ne peut être inférieure à celle du disque ${envtypemsg} (${srcdisk}). Capacite minimale requise : ${srcdisksizeGB} GB)"
    fi
    writeLog "Prérequis disque ......... OK" "info"
    installRequiredPackages "gzip" "bc" "dump" "perl" "cpio"
}