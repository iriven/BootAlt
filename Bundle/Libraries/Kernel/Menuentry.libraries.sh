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
#Arguments :
# $1=nom du dev boot dest
# $2=nom du dev grub

function rebuildMenuentry(){
	local srcdisk=$(normalizeDeviceName "${1}")
	local tgtdisk=$(normalizeDeviceName "${2}")
	local suffix="${3:-_alt}"
	local osversion=$(getOSVersion)
    if isAlternateEnv "${suffix}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
        local tgtbiosdevname="hd0"         
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
        local tgtbiosdevname="hd1"        
    fi
    diskexists "${srcdisk}" || writeLog "Le disque systeme ${envtypemsg}: ${srcdisk} n'existe pas: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} n'existe pas: $?"   
    writeLog "PERSONNALISATION DU MENU DE DEMARRAGE SYSTEME (GRUB)" "info"

    writeLog "Suppression eventuelle des entrees [BOOTALT] dans le fichier : ${CONFGRUBFILE}" "info"
	case ${osversion} in
		3|4|5|6 ) 

          awk -v var=${tgtbiosdevname} '{
            if ( $1 == "title" ){titleLine=$0;}
            else
            {
              if ( $1 == "root" ){ rootLine=$0;}
              else
              {
                if ( $1 == "kernel" ){kernelLine=$0;}
                else{ if ( $1 == "initrd" ){ initrdLine=$0} else{ print $0 }}
              }
            }
            if ( $1 == "initrd" )
            {
              if ( index(rootLine,var) == 0 )
              {
                print titleLine
                print rootLine
                print kernelLine
                print initrdLine
              }
            }
            }' ${CONFGRUBFILE} >temp && mv temp ${CONFGRUBFILE}
            chmod 0644 ${CONFGRUBFILE}
            rebuildSysvinitMenuentry "${srcdisk}" "${tgtdisk}" "${suffix}"
			;;
		* ) 
            awk -v var="${tgtbiosdevname}" '{ memfile [NR] = $0 ;}
            END {
                    for ( i = 1 ; i <= NR ; i++ ) {
                    if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+)/ ) {
                            found_clone = 0
                            for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) { if ( memfile[j] ~ var ) { found_clone = 1 } }
                            if ( found_clone == 0 ) {for ( k = i ; k <= j ; k++ ) {  print memfile[k] ;} } i = j; 
                        } else { print memfile[i];}}
                }' ${CONFGRUBFILE} >temp && mv temp ${CONFGRUBFILE}
            chmod 0644 ${CONFGRUBFILE}
            rebuildSystemdMenuentry "${srcdisk}" "${tgtdisk}" "${suffix}"
			;;			
	esac
    writeLog "FIN DE PERSONNALISATION DU GRUB" "info"
}


function rebuildSystemdMenuentry(){
	local srcdisk=$(normalizeDeviceName "${1}")
	local tgtdisk=$(normalizeDeviceName "${2}")
	local suffix="${3:-_alt}"	
    local osversion=$(getOSVersion)
    local CustomGrubFile=$(RuntimeGrubFile)
    local currdate=$(date "+%Y%m%d%H%M%S")
    local templatefile0="/tmp/bootalt_grub0.txt" 
    local templatefile1="/tmp/bootalt_grub1.txt" 
    local templatefile2="/tmp/bootalt_grub2.txt" 
    local alt_templatefile1="/tmp/bootalt_grub01.txt" 
    local alt_templatefile2="/tmp/bootalt_grub02.txt"
    [ "${osversion}" -lt 7 ] && writeLog "Cette function n'est pas compatible avec votre version d'OS: $?" 
    if isAlternateEnv "${suffix}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
        local srcbiosdevname="hd1"
        local tgtbiosdevname="hd0"
        local srcbiosdevahci="ahci1"
        local tgtbiosdevahci="ahci0"          
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
        local srcbiosdevname="hd0"
        local tgtbiosdevname="hd1"
        local srcbiosdevahci="ahci0"
        local tgtbiosdevahci="ahci1"         
    fi
    diskexists "${srcdisk}" || writeLog "Le disque systeme ${envtypemsg}: ${srcdisk} n'existe pas: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} n'existe pas: $?"	

    writeLog "Sauvegarde du fichier ${CustomGrubFile} en ${CustomGrubFile}_${currdate}" "info"
    ${FIND} ${CustomGrubFile}_* -mtime +15 -exec ${RM} {} \;
    ${CHMOD} a+x ${CustomGrubFile}
    ${CP} -f ${CustomGrubFile}{,"_${currdate}"}
    ${CHMOD} a-x ${CustomGrubFile}_*
    local CustomGrubDir=$(${DIRNAME} "${CustomGrubFile}")

    if [ -f "${CustomGrubDir}/00_tuned" ]; then
        ${CP} -f ${CustomGrubFile}{,"_${currdate}"}
        ${CP} -Rp ${CustomGrubDir}{,"_${currdate}"}
        ${FIND} "${CustomGrubDir}" -maxdepth 1 -type f ! -name 00_header ! -name 40_custom ! -name 01_users ! -name README -exec ${RM} -f {} \; 2>/dev/null
        ${FIND} "${BOOTALT_WORKSPACE}${CustomGrubDir}" -maxdepth 1 -type f ! -name 00_header ! -name 40_custom ! -name 01_users ! -name README -exec ${RM} -f {} \; 2>/dev/null
    fi
   # local altRootblkid=$(getBlkid "/dev/mapper/${altrootvg}-${rootlv}")    

    ${CAT} <<EOF > "${templatefile0}" 
    #!/bin/sh
    exec tail -n +3 \$0
    # This file provides an easy way to add custom menu entries.  Simply type the
    # menu entries you want to add after this comment.  Be careful not to change
    # the 'exec tail' line above.
EOF
    ${AWK} '/BEGIN \/etc\/grub.d\/10_linux/ {flag=1;next} /END \/etc\/grub.d\/10_linux/{flag=0} flag {print}' ${CONFGRUBFILE} >${templatefile1}
    local file1contentlength=$(${CAT}  ${templatefile1}| ${SED} '/^[[:space:]]*$/d' | ${WC} -l)
    if [ "${file1contentlength}" -eq 0 ]; 
        ${AWK} '/BEGIN \/etc\/grub.d\/40_custom/ {flag=1;next} /END \/etc\/grub.d\/40_custom/{flag=0} flag {print}' ${CONFGRUBFILE} | ${GREP} -v "^#" >${templatefile1}
        local file1contentlength=$(${CAT}  ${templatefile1}|${WC} -l)
        [ "${file1contentlength}" -eq 0 ] && writeLog "Aucune entrée de boot n'a été trouvée dans ${CONFGRUBFILE}: $?"
    fi
    ${SED} -e 's/hd0/hd1/g' -e 's/ahci0/ahci1/g' ${templatefile1} >${alt_templatefile1}
    
    local kernelVersion=$(${UNAME} -r)
    local srcBootPartitionId=$(bootPartitionIndex "${srcdisk}") 
    local tgtBootPartitionId=$(bootPartitionIndex "${tgtdisk}") 

    local srcBootPartition="${srcdisk}${srcBootPartitionId}" 
    local tgtBootPartition="${tgtdisk}${tgtBootPartitionId}" 

    local srcBootUuid=$(getBlkid "${srcBootPartition}")
    local tgtBootUuid=$(getBlkid "${tgtBootPartition}")   

    local srcRootFS=$(getFilesystem "/")
    local tgtRootFS=$(getPartnerFilesystem "${srcRootFS}" "${tgtdisk}" "${suffix}")

    local srcRootUuid=$(getBlkid "${srcRootFS}")
    local tgtRootUuid=$(getBlkid "${tgtRootFS}") 

    ${SED} -e "s/${srcBootUuid}/${tgtBootUuid}/g" ${templatefile1} > ${CustomGrubFile}
    ${SED} -i -e "s/${srcRootUuid}/${tgtRootUuid}/g" ${CustomGrubFile}
    local dmcheck=$(${GREP} "/dev/mapper/" ${CustomGrubFile})
    if [ ! -z "${dmcheck}" ]; then
        local srcRootvg=$(trim "$(${LVS} -o vg_name --noheadings ${srcRootFS})"| ${TR} -d '[[:space:]]')
        local tgtRootvg=$(alternateEntityName "${srcRootvg}" "${suffix}") 
        ${SED} -i -e "s/${srcRootvg}/${tgtRootvg}/g" ${CustomGrubFile}
    fi
         
    if isAlternateEnv "${suffix}"; then  
        ${SED} -i -e "s#^[[:space:]]*menuentry[[:space:]]*'\[BOOTALT\][[:space:]]*\(.*\)#menuentry '\1#" ${CustomGrubFile}
        ${SED} -i -e "s/\(initrd16\)[[:space:]]*\([^[:space:]]*\).BOOTALT\(.*\)$/\1 \2\3/" ${CustomGrubFile}
        ${SED} -i -e "s#^[[:space:]]*\(.*\"x\$default\"\)[[:space:]]*=[[:space:]]*'\[BOOTALT\][[:space:]]*\(.*\)#\1 = '\2#" ${CustomGrubFile}
    else
        ${SED} -i -e "s#^[[:space:]]*menuentry[[:space:]]*'\(.*\)'\(.*\)#menuentry '\[BOOTALT\] \1'\2#" ${CustomGrubFile}
        ${SED} -i -e "s/\(initrd16\)[[:space:]]*\([^[:space:]]*\)\(.img.*\)$/\1 \2.BOOTALT\3/" ${CustomGrubFile}
        ${SED} -i -e "s#^[[:space:]]*\(.*\"x\$default\"\)[[:space:]]*=[[:space:]]*'\(.*\)#\1 = '\[BOOTALT\] \2#" ${CustomGrubFile}
    fi
    ${SED} -e 's/hd1/hd0/g' -e 's/ahci1/ahci0/g' ${CustomGrubFile} > ${alt_templatefile2}
  
    for initrdfile in $(${GREP} "^[[:space:]]*initrd16[[:space:]].*BOOTALT.*[[:space:]]*$" ${CustomGrubFile} | ${GREP} -vi rescue | ${SED} "s/.*initrd.*\///;s/.img.*//")
    do
        unset GZIP
        local initrd=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f1)
        local kernelRelease=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f2-6)
        ${MKINITRD} -f --fstab="${BOOTALT_WORKSPACE}${FSTAB}" /boot/${initrd}-${kernelRelease}.BOOTALT.img ${kernelRelease}
      #  ${MKINITRD} -f --fstab="${BOOTALT_WORKSPACE}${FSTAB}" ${bootwspace}/initrd-$(${UNAME} -r).BOOTALT.img $(${UNAME} -r) 
        ${CP} -a /boot/${initrd}-${kernelRelease}.BOOTALT.img ${BOOTALT_WORKSPACE}/boot/
    done

    for initrdfile in $(${GREP} "^[[:space:]]*initrd16[[:space:]]" ${CustomGrubFile} | ${GREP} -vI "BOOTALT.*[[:space:]]*$" | ${GREP} -vi rescue | ${SED} "s/.*initrd.*\///;s/.img.*//")
    do   
        unset GZIP
        local initrd=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f1)
        local kernelRelease=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f2-6)
        ${MKINITRD} -f --fstab="${BOOTALT_WORKSPACE}${FSTAB}" /boot/${initrd}-${kernelRelease}.img ${kernelRelease}
        ${CP} -a /boot/${initrd}-${kernelRelease}.img ${BOOTALT_WORKSPACE}/boot/        
    done

    ${CP} -f ${BOOTALT_WORKSPACE}${CustomGrubFile}{,"_${currdate}"} 
    ${CHMOD} a-x ${BOOTALT_WORKSPACE}${CustomGrubFile}_${currdate}
    ${CAT} ${templatefile0} ${templatefile1} ${CustomGrubFile} > ${CustomGrubFile}
    ${CAT} ${templatefile0} ${templatefile1} ${CustomGrubFile} > ${BOOTALT_WORKSPACE}${CustomGrubFile}
    if ${GREP} "^[[:space:]]*menuentry[[:space:]]*.*\[BOOTALT\]" ${templatefile1} >/dev/null 2>&1
    then
        ${CAT} ${templatefile0} ${CustomGrubFile} ${templatefile1} > ${BOOTALT_WORKSPACE}${CustomGrubFile}
        [ $(${GREP} "^[[:space:]]*menuentry[[:space:]]*.*" ${CustomGrubFile} 2>/dev/null | head -1 | ${GREP} -q "^[[:space:]]*menuentry[[:space:]]*.*\[BOOTALT\]") -eq 0 ] || \
        ${CAT} ${templatefile0} ${CustomGrubFile} ${templatefile1} > ${CustomGrubFile}
    fi
    ${AWK} -v usource="${srcBootUuid}" -v uclone="${tgtBootUuid}" '{ memfile [NR] = $0; }
    END {
        for ( i = 1 ; i <= NR ; i++ ) {
            if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+)/ ) {
                found_valid_entry = 0
                for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) { if ( memfile[j] ~ usource || memfile[j] ~ uclone ) { found_valid_entry = 1; } }
                if ( found_valid_entry == 1) { for ( k = i ; k <= j ; k++ ) { print memfile[k];} } i = j ;
            } else { if ( memfile[i] !~ /^$/ ) { print memfile[i];} }
        }
    }' ${CustomGrubFile} > temp && ${MV} temp ${CustomGrubFile}

    ${AWK} '{ memfile [NR] = $0 ;}

        END { for ( i = 1 ; i <= NR ; i++ ) {
                if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+.*(rescue|debugging|Rescue|Debugging).*)/ ) {
                    for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {} i = j;
                } else { if ( memfile[i] !~ /^$/ ) { print memfile[i] ; } }
            }
        }' ${CustomGrubFile} > temp && ${MV} temp ${CustomGrubFile}

    ${AWK} -v usource="${srcBootUuid}" -v uclone="${tgtBootUuid}" '{ memfile [NR] = $0; }
    END {
        for ( i = 1 ; i <= NR ; i++ ) {
            if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+)/ ) {
                found_valid_entry = 0
                for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) { if ( memfile[j] ~ usource || memfile[j] ~ uclone ) { found_valid_entry = 1; } }
                if ( found_valid_entry == 1) { for ( k = i ; k <= j ; k++ ) { print memfile[k];} } i = j ;
            } else { if ( memfile[i] !~ /^$/ ) { print memfile[i];} }
        }
    }' ${BOOTALT_WORKSPACE}${CustomGrubFile} > temp && ${MV} temp ${BOOTALT_WORKSPACE}${CustomGrubFile}
    ${AWK} '{ memfile [NR] = $0 ;}

        END { for ( i = 1 ; i <= NR ; i++ ) {
                if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+.*(rescue|debugging|Rescue|Debugging).*)/ ) {
                    for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {} i = j;
                } else { if ( memfile[i] !~ /^$/ ) { print memfile[i] ; } }
            }
        }' ${BOOTALT_WORKSPACE}${CustomGrubFile} > temp && ${MV} temp ${BOOTALT_WORKSPACE}${CustomGrubFile}
    ${CHMOD} a+x ${CustomGrubFile}
    ${CHMOD} a-x ${CustomGrubFile}_${currdate}
    ${CHMOD} a+x ${BOOTALT_WORKSPACE}${CustomGrubFile}    
    ${CHMOD} a-x ${BOOTALT_WORKSPACE}${CustomGrubFile}_${currdate}
    ${RM} -f ${templatefile1} ${CustomGrubFile} ${alt_templatefile1} ${alt_templatefile2}
    unset ${templatefile1} ${CustomGrubFile}

    isAlternateEnv && local msgInfo="Installation du grub sur le disque alterné HD1" || local msgInfo="Installation du grub sur le disque nominal HD0"
    writeLog "${msgInfo}" "info"
    writeLog "Sauvegarde de la version actuelle du fichier de configuration du GRUB" "info"
    ${CP} -f -p ${CustomGrubFile}{,".old"} 
    ${CP} -f -p ${BOOTALT_WORKSPACE}${CustomGrubFile}{,".old"} 
    writeLog "(Re-)Installation du bootloader sur le disque ${envtypemsg}" "info"
    ${GRUBINSTALL} "${srcdisk}"
    writeLog "(Re-)Installation du bootloader sur le disque ${envtypealtmsg}" "info"
    ${GRUBINSTALL} "${tgtdisk}"

    ${SED} -i "s/${tgtbiosdevname}/${srcbiosdevname}/g;s/${tgtbiosdevahci}/${srcbiosdevahci}/g" ${CustomGrubFile}
    ${SED} -i "s/${srcbiosdevname}/${tgtbiosdevname}/g;s/${srcbiosdevahci}/${tgtbiosdevahci}/g" ${BOOTALT_WORKSPACE}${CustomGrubFile} 

    writeLog "Mise a jour du bootloader ${CONFGRUBFILE}" "info"
    ${GRUBMKCONFIG} -o ${CONFGRUBFILE}
    ${WAIT}
    
    writeLog "Copie et modification du fichier ${CONFGRUBFILE} sur le systeme alterne" "info"
    ${CP} -p ${CONFGRUBFILE} ${BOOTALT_WORKSPACE}${CONFGRUBFILE}
    ${SED} -i "s/${srcbiosdevname}/${tgtbiosdevname}/g;s/${srcbiosdevahci}/${tgtbiosdevahci}/g" ${BOOTALT_WORKSPACE}${CONFGRUBFILE}

    writeLog "Mise a jour du bootloader ${BOOTALT_WORKSPACE}${CONFGRUBFILE} sur le systeme alterne" "info"
    
    ${MOUNT} --bind /dev ${BOOTALT_WORKSPACE}/dev
    ${MOUNT} -t proc /proc ${BOOTALT_WORKSPACE}/proc
    ${MOUNT} -t sysfs /sys ${BOOTALT_WORKSPACE}/sys
    ${MOUNT} --bind /run ${BOOTALT_WORKSPACE}/run
    ${CHROOT} ${BOOTALT_WORKSPACE} && ${GRUBMKCONFIG} -o ${CONFGRUBFILE}
    ${WAIT}
    ${SLEEP} 5
    ${UMOUNT} ${BOOTALT_WORKSPACE}/run >/dev/null 2>&1 
    ${UMOUNT} ${BOOTALT_WORKSPACE}/sys >/dev/null 2>&1 
    ${UMOUNT} ${BOOTALT_WORKSPACE}/proc >/dev/null 2>&1    
    ${UMOUNT} ${BOOTALT_WORKSPACE}/dev >/dev/null 2>&1 
}


function rebuildSysvinitMenuentry(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local suffix="${3:-_alt}"   
    local osversion=$(getOSVersion)
    local CustomGrubFile=$(RuntimeGrubFile)
    local currdate=$(date "+%Y%m%d%H%M%S")
    local templatefile0="/tmp/bootalt_grub0.txt" 
    local templatefile1="/tmp/bootalt_grub1.txt" 
    local templatefile2="/tmp/bootalt_grub2.txt" 
    local alt_templatefile1="/tmp/bootalt_grub01.txt" 
    local alt_templatefile2="/tmp/bootalt_grub02.txt" 
    [ "${osversion}" -gt 6 ] && writeLog "Cette function n'est pas compatible avec votre version d'OS: $?"
    if isAlternateEnv "${suffix}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
        local srcbiosdevname="hd1"
        local tgtbiosdevname="hd0"
        local srcbiosdevahci="ahci1"
        local tgtbiosdevahci="ahci0"          
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
        local srcbiosdevname="hd0"
        local tgtbiosdevname="hd1"
        local srcbiosdevahci="ahci0"
        local tgtbiosdevahci="ahci1"         
    fi
    diskexists "${srcdisk}" || writeLog "Le disque systeme ${envtypemsg}: ${srcdisk} n'existe pas: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} n'existe pas: $?"

    writeLog "Sauvegarde du fichier ${CustomGrubFile} en ${CustomGrubFile}_${currdate}" "info"
    ${FIND} ${CustomGrubFile}_* -mtime +15 -exec ${RM} {} \;
    ${CHMOD} a+x ${CustomGrubFile}
    ${CP} -f ${CustomGrubFile}{,"_${currdate}"}
    ${CHMOD} a-x ${CustomGrubFile}_*

    writeLog "Ajout eventuel des entrees [BOOTALT] dans le fichier : ${CustomGrubFile}" "info"

    ${GREP} -v "^#" ${CustomGrubFile} | \
    ${AWK} -v var=${srcbiosdevname} '{
        if ( $1 == "title" ) titleLine=$0
        if ( $1 == "root"   ) rootLine=$0
        if ( $1 == "kernel" ) kernelLine=$0
        if ( $1 == "initrd" ) initrdLine=$0

        if ( $1 == "initrd" )
        {
          if ( index(rootLine,var) != 0 )
          {
            print titleLine
            print rootLine
            print kernelLine
            print initrdLine
          }
        }
    }' > ${templatefile1}
    ${SED} -e 's/hd0/hd1/'  ${templatefile1} > ${alt_templatefile1}

    ${SED} -e "s/${srcbiosdevname}/${tgtbiosdevname}/g" ${templatefile1} > ${CustomGrubFile}

    local srcRootFS=$(getFilesystem "/")
    local tgtRootFS=$(getPartnerFilesystem "${srcRootFS}" "${tgtdisk}" "${suffix}")

    local srcRootUuid=$(getBlkid "${srcRootFS}")
    local tgtRootUuid=$(getBlkid "${tgtRootFS}") 

    ${SED} -e "s/${srcBootUuid}/${tgtBootUuid}/g" ${templatefile1} > ${CustomGrubFile}
    ${SED} -i -e "s/${srcRootUuid}/${tgtRootUuid}/g" ${CustomGrubFile}
    local dmcheck=$(${GREP} "/dev/mapper/" ${CustomGrubFile})
    if [ ! -z "${dmcheck}" ]; then
        local srcRootvg=$(trim "$(${LVS} -o vg_name --noheadings ${srcRootFS})"| ${TR} -d '[[:space:]]')
        local tgtRootvg=$(alternateEntityName "${srcRootvg}" "${suffix}") 
        ${SED} -i -e "s/${srcRootvg}/${tgtRootvg}/g" ${CustomGrubFile}
    fi

    if grep "^[[:space:]]*title[[:space:]].*\[BOOTALT\]" ${CustomGrubFile} >/dev/null 2>&1
    then
        sed -i -e 's/^\([[:space:]]*title[[:space:]].*\)[[:space:]]*\[Systeme Alterne\]/\1/' ${CustomGrubFile}
        sed -i -e 's/\(root=LABEL=[^[:space:]]*\)_alt/\1/' ${CustomGrubFile}
        sed -i -e 's#rd_LVM_LV=\([^[:space:]]*\)_alt/\([^[:space:]]*\)_alt#rd_LVM_LV=\1/\2#g' ${CustomGrubFile}
        sed -i -e 's/\(initrd\)[[:space:]]*\(.*\)_ALT/\1 \2/' ${CustomGrubFile}
    else
        awk '{ if ( $1 == "title" ) { print $0 " [BOOTALT]" } else { print $0 } }' ${CustomGrubFile} > temp && mv temp ${CustomGrubFile}
        sed -i -e 's/\(root=LABEL=[^[:space:]]*\)/\1_alt/' ${CustomGrubFile}
        sed -i -e 's#rd_LVM_LV=\([^[:space:]]*\)/\([^[:space:]]*\)#rd_LVM_LV=\1_alt/\2_alt#' ${CustomGrubFile}
        sed -i -e 's/\(initrd[^ \\t]*\)\(.*\)[^ \\t]*$/\1 \2_ALT/' ${CustomGrubFile}
    fi

sed -e 's/hd1/hd0/'  ${CustomGrubFile} > ${alt_templatefile2}

for INITRDFILE in `grep "^[[:space:]]*initrd[[:space:]].*_ALT[[:space:]]*$" ${CustomGrubFile} | sed "s/.*initrd.*\///;s/.img.*//"
`
do
        # la variable d'environnement GZIP gene la compression
        # (declare dans /outillage/glob_par/config_systeme.env)
        unset GZIP
        INITR=`echo $INITRDFILE    | cut  -d'-' -f1`
        KERNEL=`echo $INITRDFILE    | cut  -d'-' -f2-6`
        mkinitrd -f /boot/${INITR}-${KERNEL}.img_ALT ${KERNEL} --fstab="${BOOTALT_WORKSPACE}${FSTAB}"
        cp -a /boot/${INITR}-${KERNEL}.BOOTALT.img ${BOOTALT_WORKSPACE}/boot/
    
done

for INITRDFILE in `grep "^[[:space:]]*initrd[[:space:]]" ${CustomGrubFile} | grep -v "_ALT[[:space:]]*$" | sed "s/.*initrd.*\///;s/.img.*//"
`
do
        # la variable d'environnement GZIP gene la compression
        # (declare dans /outillage/glob_par/config_systeme.env)
        unset GZIP
        INITR=`echo $INITRDFILE    | cut  -d'-' -f1`
        KERNEL=`echo $INITRDFILE    | cut  -d'-' -f2-6`
        mkinitrd -f /boot/${INITR}-${KERNEL}.img ${KERNEL} --fstab="${BOOTALT_WORKSPACE}${FSTAB}"
        cp -a /boot/${INITR}-${KERNEL}.img ${BOOTALT_WORKSPACE}/boot/
    
done

for lig in $(grep title ${CustomGrubFile}| sed 's/ /_/g')
do
    writeLog "Ajout entree '${lig}'" "info"
done

if grep "^[[:space:]]*title[[:space:]].*\[BOOTALT\]" ${templatefile1} >/dev/null 2>&1
then
  cat ${templatefile0} ${CustomGrubFile} ${templatefile1} > ${CustomGrubFile}
  cat  ${templatefile0} ${alt_templatefile2} ${alt_templatefile1} > ${BOOTALT_WORKSPACE}${CustomGrubFile}
else
  cat ${templatefile0} ${templatefile1} ${CustomGrubFile} > ${CustomGrubFile}
  cat ${templatefile0} ${alt_templatefile1} ${alt_templatefile2} > ${BOOTALT_WORKSPACE}${CustomGrubFile}
fi
chmod 0644 ${CustomGrubFile}
chmod 0644 ${BOOTALT_WORKSPACE}${CustomGrubFile}

rm -f ${templatefile1} ${CustomGrubFile} ${alt_templatefile2} ${alt_templatefile1}
unset ${templatefile1} ${CustomGrubFile} lig  

hdalt="hd0"
${GRUB} --batch --no-floppy --device-map=/boot/grub/device.map  >/dev/null 2>&1 << EOF
root ($hdalt,0)
setup ($hdalt)
quit
EOF

}

function RuntimeGrubFile(){
    local osversion=$(getOSVersion)
    local grubcustomfile=
    case "${osversion}" in
      3|4|5|6)  grubcustomfile="/boot/grub/grub.conf" ;;
      *)   grubcustomfile="/etc/grub.d/40_custom" ;;
    esac
     [ -f "${grubcustomfile}" ] || writeLog "Le fichier contenant le menuentry personnalisé du grub est introuvable"
    ${ECHO} "${grubcustomfile}"
}

function generateCustomMenuTemplate(){
    local srcdisk=$(normalizeDeviceName "${1}")
    local tgtdisk=$(normalizeDeviceName "${2}")
    local suffix="${3:-_alt}"  
    local osversion=$(getOSVersion)
    local currdate=$(date "+%Y%m%d%H%M%S") 
    local CustomGrubFile=$(RuntimeGrubFile)   
    local templatefile="/tmp/bootaltgrub.cfg.tpl"   
    [ "${osversion}" -lt 7 ] && writeLog "Cette function n'est pas compatible avec votre version d'OS: $?" 
    if isAlternateEnv "${suffix}"; then
        local envtypemsg='alterné'; 
        local envtypealtmsg='nominal'; 
        local srcbiosdevname="hd1"
        local tgtbiosdevname="hd0"
        local srcbiosdevahci="ahci1"
        local tgtbiosdevahci="ahci0"          
    else
        local envtypemsg='nominal'; 
        local envtypealtmsg='alterné';
        local srcbiosdevname="hd0"
        local tgtbiosdevname="hd1"
        local srcbiosdevahci="ahci0"
        local tgtbiosdevahci="ahci1"         
    fi
    diskexists "${srcdisk}" || writeLog "Le disque systeme ${envtypemsg}: ${srcdisk} n'existe pas: $?"
    diskexists "${tgtdisk}" || writeLog "Le disque systeme ${envtypealtmsg}: ${tgtdisk} n'existe pas: $?"   
  
    case ${osversion} in
        3|4|5|6 )
            ;;
            *) 
            ${RM} -f $(${DIRNAME} "${CustomGrubFile}")/{20_*,30_*}
            ${RM} -f $(${DIRNAME} "${BOOTALT_WORKSPACE}${CustomGrubFile}")/{20_*,30_*}
            ${SED} -i '/^$/d' "${CustomGrubFile}"
            ${SED} -i '/^$/d' "${BOOTALT_WORKSPACE}${CustomGrubFile}"

            ${CAT} <<EOF > "${templatefile}" 
            #!/bin/sh
            exec tail -n +3 \$0
            # This file provides an easy way to add custom menu entries.  Simply type the
            # menu entries you want to add after this comment.  Be careful not to change
            # the 'exec tail' line above.
EOF
            ${AWK} '/BEGIN \/etc\/grub.d\/10_linux/ {flag=1;next} /END \/etc\/grub.d\/10_linux/{flag=0} flag {print}' ${CONFGRUBFILE} >temp
            local tempcontentlength=$(${CAT}  temp| ${SED} '/^[[:space:]]*$/d' | ${WC} -l)
            if [ "${tempcontentlength}" -eq 0 ]; 
                ${AWK} '/BEGIN \/etc\/grub.d\/40_custom/ {flag=1;next} /END \/etc\/grub.d\/40_custom/{flag=0} flag {print}' ${CONFGRUBFILE} | ${GREP} -v "^#" >temp
                local tempcontentlength=$(${CAT}  temp|${WC} -l)
                [ "${tempcontentlength}" -eq 0 ] && writeLog "Aucune entrée de boot n'a été trouvée dans ${CONFGRUBFILE}: $?"
            fi 
            removeTextBetweenMarkers "menuentry" "}" "${CONFGRUBFILE}"
            removeTextBetweenMarkers "menuentry" "}" "${BOOTALT_WORKSPACE}${CONFGRUBFILE}"
            ${CAT}  temp >> ${templatefile}
            ${RM} -f temp
            ${AWK} '{ memfile [NR] = $0 ;}
            END { for ( i = 1 ; i <= NR ; i++ ) {
                    if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+.*(rescue|debugging|Rescue|Debugging).*)/ ) {
                        for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {} i = j;
                    } else { if ( memfile[i] !~ /^$/ ) { print memfile[i] ; } }
                }
            }' ${templatefile} > ${CustomGrubFile}
            
            ${RM} -f ${templatefile}  
            ${SED} -i "s/${srcbiosdevname}/${tgtbiosdevname}/g;s/${srcbiosdevahci}/${tgtbiosdevahci}/g" ${CustomGrubFile} 

            local srcBootPartitionId=$(bootPartitionIndex "${srcdisk}") 
            local tgtBootPartitionId=$(bootPartitionIndex "${tgtdisk}") 

            local srcBootPartition="${srcdisk}${srcBootPartitionId}" 
            local tgtBootPartition="${tgtdisk}${tgtBootPartitionId}" 

            local srcBootUuid=$(getBlkid "${srcBootPartition}")
            local tgtBootUuid=$(getBlkid "${tgtBootPartition}")   

            local srcRootFS=$(getFilesystem "/")
            local tgtRootFS=$(getPartnerFilesystem "${srcRootFS}" "${tgtdisk}" "${suffix}")

            local srcRootUuid=$(getBlkid "${srcRootFS}")
            local tgtRootUuid=$(getBlkid "${tgtRootFS}") 
            ${SED} -i "s/${srcBootUuid}/${tgtBootUuid}/g" ${CustomGrubFile} 
           

            local srcRootvg=$(trim "$(${LVS} -o vg_name --noheadings ${srcRootFS})"| ${TR} -d '[[:space:]]')
            local tgtRootvg=$(alternateEntityName "${srcRootvg}" "${suffix}") 

            ${SED} -i -e "s/${srcRootvg}\([\/-]\)\([^[:space:]]*\)[[:space:]]*/${tgtRootvg}\1\2 /g" ${CustomGrubFile} 
            ${SED} -i "s/${srcRootvg}/${tgtRootvg}/g" ${BOOTALT_WORKSPACE}${CONFGRUBFILE}
            
         
            if isAlternateEnv "${suffix}"; then  
                ${SED} -i -e "s#^[[:space:]]*menuentry[[:space:]]*'\[BOOTALT\][[:space:]]*\(.*\)#menuentry '\1#" ${CustomGrubFile}
                ${SED} -i -e "s/\(initrd16\)[[:space:]]*\([^[:space:]]*\).BOOTALT\(.*\)$/\1 \2\3/" ${CustomGrubFile}
                ${SED} -i -e "s#^[[:space:]]*\(.*\"x\$default\"\)[[:space:]]*=[[:space:]]*'\[BOOTALT\][[:space:]]*\(.*\)#\1 = '\2#" ${CustomGrubFile}
            else
                ${SED} -i -e "s#^[[:space:]]*menuentry[[:space:]]*'\(.*\)'\(.*\)#menuentry '\[BOOTALT\] \1'\2#" ${CustomGrubFile}
                ${SED} -i -e "s/\(initrd16\)[[:space:]]*\([^[:space:]]*\)\(.img.*\)$/\1 \2.BOOTALT\3/" ${CustomGrubFile}
                ${SED} -i -e "s#^[[:space:]]*\(.*\"x\$default\"\)[[:space:]]*=[[:space:]]*'\(.*\)#\1 = '\[BOOTALT\] \2#" ${CustomGrubFile}
            fi
            ${CP} -a ${CustomGrubFile} ${BOOTALT_WORKSPACE}${CustomGrubFile} >/dev/null 2>&1            
            ${SED} -i "s/${tgtBootUuid}/${srcBootUuid}/g" ${BOOTALT_WORKSPACE}${CustomGrubFile}
            ${SED} -i -e "s/${tgtRootvg}\([\/-]\)\([^[:space:]]*\)[[:space:]]*/${srcRootvg}\1\2 /g" ${BOOTALT_WORKSPACE}${CustomGrubFile}
            ${SED} -i "s/${tgtbiosdevname}/${srcbiosdevname}/g;s/${tgtbiosdevahci}/${srcbiosdevahci}/g" ${BOOTALT_WORKSPACE}${CustomGrubFile} 
            ${CHMOD} a+x ${CustomGrubFile}
            ${CHMOD} a+x ${BOOTALT_WORKSPACE}${CustomGrubFile}    
            ${RM} -f ${templatefile}
            for initrdfile in $(${GREP} "^[[:space:]]*initrd16[[:space:]].*BOOTALT.*[[:space:]]*$" ${CustomGrubFile} | ${GREP} -vi rescue | ${SED} "s/.*initrd.*\///;s/.img.*//")
            do
                unset GZIP
                local initrd=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f1)
                local kernelRelease=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f2-6)
                ${MKINITRD} -f --fstab="${BOOTALT_WORKSPACE}${FSTAB}" /boot/${initrd}-${kernelRelease}.BOOTALT.img ${kernelRelease}
                ${CP} -a /boot/${initrd}-${kernelRelease}.BOOTALT.img ${BOOTALT_WORKSPACE}/boot/
            done

            for initrdfile in $(${GREP} "^[[:space:]]*initrd16[[:space:]]" ${CustomGrubFile} | ${GREP} -vI "BOOTALT.*[[:space:]]*$" | ${GREP} -vi rescue | ${SED} "s/.*initrd.*\///;s/.img.*//")
            do   
                unset GZIP
                local initrd=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f1)
                local kernelRelease=$(${ECHO} ${initrdfile} | ${CUT} -d'-' -f2-6)
                ${MKINITRD} -f --fstab="${BOOTALT_WORKSPACE}${FSTAB}" /boot/${initrd}-${kernelRelease}.img ${kernelRelease}
                ${CP} -a /boot/${initrd}-${kernelRelease}.img ${BOOTALT_WORKSPACE}/boot/        
            done
            

        ;;
    esac
}


