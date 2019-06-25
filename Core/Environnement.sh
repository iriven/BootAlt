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
export WHICH=/usr/bin/which 
export AWK=$(${WHICH} awk)
export BASENAME=$(${WHICH} basename)
export BLKID=$(${WHICH} blkid)
export CAT=$(${WHICH} cat)
export CD=$(${WHICH} cd)
export CHMOD=$(${WHICH} chmod)
export CP=$(${WHICH} cp)
export CPIO=$(${WHICH} cpio)
export DATE=$(${WHICH} date)
export DIRNAME=$(${WHICH} dirname)
export DUMP=$(${WHICH} dump)
export ECHO=$(${WHICH} echo)
export EGREP=$(${WHICH} egrep)
export EXPR=$(${WHICH} expr)
export FDISK=$(${WHICH} fdisk)
export FGREP=$(${WHICH} fgrep)
export FIND=$(${WHICH} find)
export FSCK=$(${WHICH} fsck)
export GREP=$(${WHICH} grep)
export HEAD=$(${WHICH} head)
export LOGGER=$(${WHICH} logger)
export LS=$(${WHICH} ls)
export LVCREATE=$(${WHICH} lvcreate)
export LVS=$(${WHICH} lvs)
export MKDIR=$(${WHICH} mkdir)
export MKFS=$(${WHICH} mkfs)
export MKINITRD=$(${WHICH} mkinitrd)
export MKSWAP=$(${WHICH} mkswap)
export MOUNT=$(${WHICH} mount)
export MV=$(${WHICH} mv)
export PERL=$(${WHICH} perl)
export PVCREATE=$(${WHICH} pvcreate)
export PVDISPLAY=$(${WHICH} pvdisplay)
export PVREMOVE=$(${WHICH} pvremove)
export PVS=$(${WHICH} pvs)
export PWD=$(${WHICH} pwd)
export READLINK=$(${WHICH} readlink)
export RESTORE=$(${WHICH} restore)
export RHMAJVER=$(getRedhatVersion)
export RM=$(${WHICH} rm)
export SED=$(${WHICH} sed)
export SFDISK=$(${WHICH} sfdisk)
export SLEEP=$(${WHICH} sleep)
export SYNC=$(${WHICH} sync)
export TAIL=$(${WHICH} tail)
export TR=$(${WHICH} tr)
export UMOUNT=$(${WHICH} umount)
export UNAME=$(${WHICH} uname)
export VGCREATE=$(${WHICH} vgcreate)
export VGDISPLAY=$(${WHICH} vgdisplay)
export VGREMOVE=$(${WHICH} vgremove)
export VGS=$(${WHICH} vgs)
[ "${RHMAJVER}" -eq 5 ] && export EXTVER=3 || export EXTVER=4 ;
[ "${RHMAJVER}" -eq 7 ] && export GRUBINSTALL=$(${WHICH} grub2-install) || export GRUBINSTALL=$(${WHICH} grub-install);
[ "${RHMAJVER}" -eq 7 ] && export GRUBMKCONFIG=$(${WHICH} grub2-mkconfig) || export GRUBMKCONFIG=$(${WHICH} grub-mkconfig);
if [ "${RHMAJVER}" -lt 5 ]
then
        printf " \e[31m %s \e[0m" `${DATE}` ": Ne peut pas determiner la version Red Hat courante"  1>&2
        ${LOGGER} -p local7.err -t BootAlt "Ne peut pas determiner la version Red Hat courante"
        exit 1 
fi
