#!/usr/bin/env bash
# Header_start
##############################################################################################
#                                                                                            #
#  Author:         Alfred TCHONDJO - Iriven France                                           #
#  Date:           2019-05-14                                                                #
#  Website:        https://github.com/iriven?tab=repositories                                #
#                                                                                            #
# ------------------------------------------------------------------------------------------ #
#                                                                                            #
#  Project:        Linux Alternate Boot (BOOTALT)                                            #
#  Description:	   An advanced tool to create alternate boot environment on Linux servers.   #
#  Version:        1.0.1    (G1R0C1)                                                         #
#                                                                                            #
#  License:        GNU GPLv3                                                                 #
#                                                                                            #
#  This program is free software: you can redistribute it and/or modify                      #
#  it under the terms of the GNU General Public License as published by                      #
#  the Free Software Foundation, either version 3 of the License, or                         #
#  (at your option) any later version.                                                       #
#                                                                                            #
#  This program is distributed in the hope that it will be useful,                           #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of                            #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                             #
#  GNU General Public License for more details.                                              #
#                                                                                            #
#  You should have received a copy of the GNU General Public License                         #
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.                     #
#                                                                                            #
# ------------------------------------------------------------------------------------------ #
#  Revisions                                                                                 #
#                                                                                            #
#  - G1R0C0 :        Creation du script le 14/05/2019 (AT)                                   #
#  - G1R0C1 :        Update - détection auto des FS le 30/09/2019 (AT)                       #
#                                                                                            #
##############################################################################################
# Header_end
# set -x
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  printf "\\n%s is a part of bash Linux Alternate Boot (BOOTALT) project. Dont execute it directly!\\n\\n" "${0##*/}"
  exit 1
fi
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
export CHROOT=$(${WHICH} chroot)
export CP=$(${WHICH} cp)
export CPIO=$(${WHICH} cpio)
export CUT=$(${WHICH} cut)
export DATE=$(${WHICH} date)
export DF=$(${WHICH} df)
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
export RHMAJVER=$(getOSVersion)
export RM=$(${WHICH} rm)
export SED=$(${WHICH} sed)
export SFDISK=$(${WHICH} sfdisk)
export SLEEP=$(${WHICH} sleep)
export SORT=$(${WHICH} sort)
export SYNC=$(${WHICH} sync)
export TAIL=$(${WHICH} tail)
export TR=$(${WHICH} tr)
export UMOUNT=$(${WHICH} umount)
export UNAME=$(${WHICH} uname)
export VGCREATE=$(${WHICH} vgcreate)
export VGDISPLAY=$(${WHICH} vgdisplay)
export VGEXTEND=$(${WHICH} vgextend)
export VGREMOVE=$(${WHICH} vgremove)
export VGS=$(${WHICH} vgs)
export WC=$(${WHICH} wc)
case "${RHMAJVER}" in
	3|4|5|6) 
 	export GRUBINSTALL=$(${WHICH} grub-install);
 	export GRUBMKCONFIG=$(${WHICH} grub-mkconfig);
 	export CONFGRUBFILE='/boot/grub/grub.conf'
 	export DEVMAPFILE='/boot/grub/device.map'
 	export LABELCMD=$(${WHICH} e2label)
;;
	*)
	export GRUBINSTALL=$(${WHICH} grub2-install)
	export GRUBMKCONFIG=$(${WHICH} grub2-mkconfig)
	export CONFGRUBFILE='/boot/grub2/grub.cfg'
	export DEVMAPFILE='/boot/grub2/device.map'
	export LABELCMD="$(${WHICH} xfs_admin) -l"
;;
esac
export FSTAB=/etc/fstab
export PROG=$(${BASENAME} ${BOOTALT_CORE_FILE})
export SCSIRESCAN="/usr/bin/rescan-scsi-bus.sh"