#!/bin/bash
#set -x

##########################
# Systeme alterne V2.1.4 #
##########################



message () {
        ksh ${SYSALTPATH}/sysalt_message.ksh  $2 "$3"
}


# Fonction terminer_ko
terminer_ko() {
        message "*** FIN ECHEC"
        \rm /var/run/${PROG}.pid >/dev/null 2>&1
        exit 2
}

# FQT Fonction nom_clone
nom_clone() {
  if echo $1 | grep '_alt$' >/dev/null 2>&1; then
    echo $1 | sed 's/_alt$//'
  else
    echo ${1}_alt
  fi
}

# Fonction grub2_avec_sys_alt
# ---------------------------
grub2_avec_sys_alt()
{
  # ----------------------------------------------------------------------------
  # Dans le fichier de configuration GRUB2, recherche et duplique les 'entrees'
  # pointant vers le nom BIOS du disk source (${bios_disk_source}) en effectuant
  # les modifications suivantes sur les 'entrees' dupliquees :
  # - ajout de "[Systeme Alterne]" a la fin du titre
  # - remplacement du nom BIOS du disk source (${bios_disk_source}) par le
  #   nom BIOS du disk clone (${bios_disk_clone})
  # - remplacement de la chaine "root=LABEL=/" par la chaine
  #   "root=LABEL=/_alt"
  # ----------------------------------------------------------------------------

	flag_error=0

	fic_tempo0="/tmp/sys_alt.grub0"
	fic_tempo1="/tmp/sys_alt.grub1"
	fic_tempo1_alt="/tmp/sys_alt.grub1.alt"
	fic_tempo2="/tmp/sys_alt.grub2"
	fic_tempo2_alt="/tmp/sys_alt.grub2.alt"

	GRUB2_CUSTOM_FILE="/etc/grub.d/40_custom"

	DATE=$(date "+%Y%m%d%H%M%S")

	chmod 0755 ${GRUB2_CUSTOM_FILE}
	\cp -f ${GRUB2_CUSTOM_FILE} ${GRUB2_CUSTOM_FILE}_${DATE}
		# Il faut surtout que le fichier ne soit pas executable sinon il se retrouvera dans le boot
	chmod a-x ${GRUB2_CUSTOM_FILE}_${DATE}
	message -m SYSTEME_ALTERNE_I "Sauvegarde du fichier ${GRUB2_CUSTOM_FILE} en ${GRUB2_CUSTOM_FILE}_${DATE}"

	# Grub a-t'il deja ete modifie sur le systeme source ?
	# ----------------------------------------------------
	if [ -f /etc/grub.d/00_tuned ]; then
		cp -Rp /etc/grub.d /etc/grub.d_$(date "+%Y%m%d%H%M%S")

			# Efface tous les fichiers dans /etc/grub.d sauf 00_header 40_custom 01_users et README
			# https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/7/html/System_Administrators_Guide/sec-Customizing_GRUB_2_Menu.html#sec-Editing_an_Entry

		find /etc/grub.d -maxdepth 1 -type f ! -name 00_header ! -name 40_custom ! -name 01_users ! -name README -exec rm -f {} \; 2>/dev/null
	fi

	# Grub a-t'il deja ete modifie sur le systeme clone ?
	# ---------------------------------------------------
	if [ -f /sys_alt/etc/grub.d/00_tuned ]; then
		cp -Rp /sys_alt/etc/grub.d /sys_alt/etc/grub.d_$(date "+%Y%m%d%H%M%S")

			# Efface tous les fichiers dans /sys_alt/etc/grub.d sauf 00_header 40_custom 01_users et README
		find /sys_alt/etc/grub.d -maxdepth 1 -type f ! -name 00_header ! -name 40_custom ! -name 01_users ! -name README -exec rm -f {} \; 2>/dev/null
	fi

	# Nombre de partitions
	# --------------------
	nb_part=$($SFDISK -l ${disk_source} 2>/dev/null | grep "^${disk_source}" | wc -l)

	# Determine la partition du disque source ou est installe grub
	# ------------------------------------------------------------
	grub_index_part=0
	i=0
	while [ ${i} -lt ${nb_part} ]
	do
  	i=$(expr $i + 1)
		if [ $($SFDISK --print-id ${disk_source} ${i}) = 83 ]; then
			grub_index_part=$i
			break
		fi
	done

	if [ $grub_index_part -eq 0 ]
	then
		message  -m SYSTEME_ALTERNE_E "Erreur pour trouver une partition de type 83 sur le disque source ${disk_source}"
  	terminer_ko
	fi

	# Verifie que la partition clone d'index $grub_index_part est bien du type 83
	# ---------------------------------------------------------------------------
	if [ $($SFDISK --print-id ${disk_clone}${grub_index_part}) != 83 ]; then
		message  -m SYSTEME_ALTERNE_E "Erreur la partition clone ${disk_clone}${grub_index_part} n'est pas du type 83"
  	terminer_ko
	fi

	# Recupere l'UUID de la partition grub du disque source
	# -----------------------------------------------------
	UUID_source=$(xfs_admin -u ${disk_source}${grub_index_part} 2>/dev/null | awk '{print $NF }')
	if [ -z "$UUID_source" ]; then
		message  -m SYSTEME_ALTERNE_E "Erreur d'obtention de l'UUID de la partition source ${disk_source}${grub_index_part}"
  	terminer_ko
	fi
  message -m SYSTEME_ALTERNE_I "UUID de la partition source ${disk_source}${grub_index_part} = $UUID_source"

	# Recupere l'UUID de la partition grub du disque clone
	# -----------------------------------------------------
	UUID_clone=$(xfs_admin -u ${disk_clone}${grub_index_part} 2>/dev/null | awk '{print $NF }')
	if [ -z "$UUID_clone" ]; then
		message  -m SYSTEME_ALTERNE_E "Erreur d'obtention de l'UUID de la partition clone ${disk_clone}${grub_index_part}"
		terminer_ko
	fi
  message -m SYSTEME_ALTERNE_I "UUID de la partition clone ${disk_clone}${grub_index_part} = $UUID_clone"

	# Creation du fichier ${fic_tempo0} dans qui contient la base du fichier /etc/grub.d/40_custom
	# --------------------------------------------------------------------------------------------
	cat > "${fic_tempo0}" <<EOF
#!/bin/sh
exec tail -n +3 \$0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.
EOF

	# Lors du premier appel du script sysalt (grub2 est configure par le systeme), les
	# entrees de boot n'apparaissent pas dans /etc/grub.d/40_custom mais dans ${FIC_CONFGRUB2}
	# entre les lignes ### BEGIN /etc/grub.d/10_linux ### et ### END /etc/grub.d/10_linux ###
	# Ajoute les entrees de boot principales de ${FIC_CONFGRUB2} dans ${fic_tempo1}
	awk '/BEGIN \/etc\/grub.d\/10_linux/ {flag=1;next} /END \/etc\/grub.d\/10_linux/{flag=0} flag {print}' ${FIC_CONFGRUB2} >${fic_tempo1}

	if [ "$(cat ${fic_tempo1} | sed '/^[[:space:]]*$/d' | wc -l)" = 0 ]; then

		# Si le fichier ${fic_tempo1} est vide c'est qu'il y a eu des entrees via
		# /etc/grub.d/40_custom, on les recherche dans ${FIC_CONFGRUB2} et les copie dans ${fic_tempo1}

		awk '/BEGIN \/etc\/grub.d\/40_custom/ {flag=1;next} /END \/etc\/grub.d\/40_custom/{flag=0} flag {print}' ${FIC_CONFGRUB2} | grep -v "^#" >${fic_tempo1}

			# Si le fichier ${fic_tempo1} est toujours vide c'est qu'il n'y a pas eu
			# non plus d'entrees de boot par /etc/grub.d/40_custom alors on sort
		if [ "$(cat ${fic_tempo1} | wc -l)" = 0 ]; then
			message  -m SYSTEME_ALTERNE_E "Erreur pour trouver des entrees de boot dans ${FIC_CONFGRUB2}"
			terminer_ko
		fi
	fi

  message -m SYSTEME_ALTERNE_I "Ajout eventuel des entrees [Systeme Alterne] dans le fichier : ${FIC_CONFGRUB2}"

  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "Contenu du fichier travail genere (${fic_tempo1}) contenant les 'entrees' du disk source ${bios_disk_source} a dupliquer :"
    cat "${fic_tempo1}"
    echo "---------------------------------------------------"
  fi

	sed -e 's/hd0/hd1/g' -e 's/ahci0/ahci1/g' $fic_tempo1 >$fic_tempo1_alt

	# Le disque source est-il le systeme alterne ?
	# --------------------------------------------
  args_pour_le_sed='s/'"$UUID_source"'/'"$UUID_clone"'/g'
	#if grep "^[[:space:]]*menuentry[[:space:]]*.*\[Systeme Alterne\]" ${fic_tempo1} >/dev/null 2>&1
	if [ "$CLONE_SOURCE" != 0 ]
  then
			# Le disque source est le systeme alterne
				#-e "s#^[[:space:]]*menuentry[[:space:]]*'\(.*\)\[Systeme Alterne\][[:space:]]\(.*\)#menuentry '\1\2#" \
    sed -e "${args_pour_le_sed}" \
			-e "s#^[[:space:]]*menuentry[[:space:]]*'\(.*\)\[Systeme Alterne\]\(.*\)#menuentry '\1\2#" \
			-e "s#root=/dev/mapper/\([^[:space:]]*\)_alt\([^[:space:]]*\)_alt#root=/dev/mapper/\1\2#" \
			-e "s#rd.lvm.lv=\([^[:space:]]*\)_alt\([^[:space:]]*\)_alt#rd.lvm.lv=\1\2#g" \
			-e "s/\(initrd16\)[[:space:]]*\(.*\)_ALT/\1 \2/" ${fic_tempo1} > ${fic_tempo2}
    cr2=$?
  else
			# Le disque source n'est pas le systeme alterne
				#-e "s#^[[:space:]]*menuentry[[:space:]]*'\(.*\),[[:space:]]*\(.*\)#menuentry '\1, \[Systeme Alterne\] \2#" \
		sed -e "${args_pour_le_sed}" \
			-e "s#^[[:space:]]*menuentry[[:space:]]*'\(.*\)'\(.*\)#menuentry '\[Systeme Alterne\] \1'\2#" \
			-e "s#root=/dev/mapper/\([^[:space:]]*\)-\([^[:space:]]*\)#root=/dev/mapper/\1_alt-\2_alt#" \
			-e "s#rd.lvm.lv=\([^[:space:]]*\)/\([^[:space:]]*\)#rd.lvm.lv=\1_alt/\2_alt#g" \
			-e "s/\(initrd16\)[[:space:]]*\(.*\)$/\1 \2_ALT/" ${fic_tempo1} > ${fic_tempo2}
    cr2=$?
  fi

	sed -e 's/hd1/hd0/g' -e 's/ahci1/ahci0/g' ${fic_tempo2} >${fic_tempo2_alt}

	for INITRDFILE in `grep "^[[:space:]]*initrd16[[:space:]].*_ALT[[:space:]]*$" ${fic_tempo2} | grep -vi rescue | sed "s/.*initrd.*\///;s/.img.*//"`
	do
		# la variable d'environnement GZIP gene la compression
		# (declare dans /outillage/glob_par/config_systeme.env)
		unset GZIP
		INITR=`echo $INITRDFILE | cut -d'-' -f1`
		KERNEL=`echo $INITRDFILE | cut -d'-' -f2-6`
		mkinitrd -f /boot/${INITR}-${KERNEL}.img_ALT ${KERNEL} --fstab="${RACINE_SYS_ALT}${FIC_FSTAB}"
		cp -a /boot/${INITR}-${KERNEL}.img_ALT ${RACINE_SYS_ALT}/boot/
	done

	for INITRDFILE in `grep "^[[:space:]]*initrd16[[:space:]]" ${fic_tempo2} | grep -v "_ALT[[:space:]]*$" | grep -vi rescue | sed "s/.*initrd.*\///;s/.img.*//"`
	do
		# la variable d'environnement GZIP gene la compression
		# (declare dans /outillage/glob_par/config_systeme.env)
		unset GZIP
		INITR=`echo $INITRDFILE | cut  -d'-' -f1`
		KERNEL=`echo $INITRDFILE | cut  -d'-' -f2-6`
		mkinitrd -f /boot/${INITR}-${KERNEL}.img ${KERNEL} --fstab="${RACINE_SYS_ALT}${FIC_FSTAB}"
		cp -a /boot/${INITR}-${KERNEL}.img ${RACINE_SYS_ALT}/boot/
	done
	
  if [ ${cr2} -ne 0 ]
  then
    message  -m SYSTEME_ALTERNE_E "Erreur lors de la preparation des modifications dans ${FIC_CONFGRUB2}"
    flag_error=1
  else

		# Le contenu du fichier fic_tempo2 doit etre avant celui de fic_tempo1
		# si fic_tempo1 contient une ligne concernant le systeme alterne
		# ET que la premiere ligne menuentry de fic_tempo2 ne contient pas Systeme Alterne
		# --------------------------------------------------------------------
		if grep "^[[:space:]]*menuentry[[:space:]]*.*\[Systeme Alterne\]" ${fic_tempo1} >/dev/null 2>&1
		then
			if grep "^[[:space:]]*menuentry[[:space:]]*.*" ${fic_tempo2} 2>/dev/null | head -1 | grep -q "^[[:space:]]*menuentry[[:space:]]*.*\[Systeme Alterne\]"
			then
				cat ${fic_tempo0} ${fic_tempo1} ${fic_tempo2} > ${GRUB2_CUSTOM_FILE}
			else
				cat ${fic_tempo0} ${fic_tempo2} ${fic_tempo1} > ${GRUB2_CUSTOM_FILE}
			fi
		else
			cat ${fic_tempo0} ${fic_tempo1} ${fic_tempo2} > ${GRUB2_CUSTOM_FILE}
		fi

		if [ $? -ne 0 ]; then
			message -m SYSTEME_ALTERNE_E  "Erreur lors de l'ajout des 'entrees' dans ${GRUB2_CUSTOM_FILE}"
			flag_error=1
		fi

		# Ne pas oublier de mettre a jour le fichier ${GRUB2_CUSTOM_FILE} sur le disque clone
		# D'abord on fait une sauvegarde
		chmod 0755 ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
		\cp -f ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE} ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}_${DATE}
			# Il faut surtout que le fichier ne soit pas executable sinon il se retrouvera dans le boot
		chmod a-x ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}_${DATE}
		message -m SYSTEME_ALTERNE_I "Sauvegarde du fichier ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE} en ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}_${DATE}"

		if grep "^[[:space:]]*menuentry[[:space:]]*.*\[Systeme Alterne\]" ${fic_tempo1} >/dev/null 2>&1
		then
			cat ${fic_tempo0} ${fic_tempo2} ${fic_tempo1} > ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
		else
			cat ${fic_tempo0} ${fic_tempo1} ${fic_tempo2} > ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
		fi

		if [ $? -ne 0 ]; then
			message -m SYSTEME_ALTERNE_E  "Erreur lors de l'ajout des 'entrees' dans ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}"
			flag_error=1
		fi
		
  	if [ "${DEBUG}" = "1" ]
  	then
    	echo "---------------------------------------------------"
    	echo "Contenu du fichier ${GRUB2_CUSTOM_FILE} :"
    	cat ${GRUB2_CUSTOM_FILE}
    	echo "---------------------------------------------------"
  	fi

	fi

	rm -f ${fic_tempo1} ${fic_tempo2} ${fic_tempo1_alt} ${fic_tempo2_alt}
	unset fic_tempo1 fic_tempo2 cr2 args_pour_le_sed lig

	if [ $CLONE_SOURCE == 0 ]
	then
		hdalt="hd0"
		message -m SYSTEME_ALTERNE_I  "systeme original, install grub sur HD1"
	else
		hdalt="hd0"
		message -m SYSTEME_ALTERNE_I  "systeme alterne, install grub sur HD0"
	fi


	# Nettoyage des anciennes entrees dans ${GRUB2_CUSTOM_FILE}
	# Si il y avait des entrees grub2 sur une partition xfs qui vient
	# d'etre reformatee, l'UUID a change et il faut supprimer les entrees
	# qui restent avec l'ancien UUID
	# On supprime aussi les entrees rescue et debugging qui n'ont pas vraiment d'utilite sur un systeme alterne
	fic_tempo_f="/tmp/sys_alt.grubf"
	awk -v usource="${UUID_source}" -v uclone="${UUID_clone}" '
		{
			memfile [NR] = $0
		}

		END {
			for ( i = 1 ; i <= NR ; i++ ) {
				if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+)/ ) {
					found_valid_entry = 0
					for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {
						if ( memfile[j] ~ usource || memfile[j] ~ uclone ) { found_valid_entry = 1 }
					}
					if ( found_valid_entry == 1) {
						for ( k = i ; k <= j ; k++ ) {
							print memfile[k]
						}
						i = j
					} else { i = j }
				} else {
						if ( memfile[i] !~ /^$/ ) {
							print memfile[i]
						}
					}
			}
		}
	' ${GRUB2_CUSTOM_FILE} > ${fic_tempo_f}

	
	# Nettoyage des entrees rescue et debugging dans ${GRUB2_CUSTOM_FILE}
	# Les entrees rescue et debugging n'ont pas vraiment d'utilite sur un systeme alterne
	awk '
		{
			memfile [NR] = $0
		}

		END {
			for ( i = 1 ; i <= NR ; i++ ) {
				if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+.*(rescue|debugging|Rescue|Debugging).*)/ ) {
					for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {
					}
					i = j
				} else {
						if ( memfile[i] !~ /^$/ ) {
							print memfile[i]
						}
					}
			}
		}
	' ${fic_tempo_f} > ${GRUB2_CUSTOM_FILE}
	
	chmod 0755 ${GRUB2_CUSTOM_FILE}

	# Nettoie de la meme maniere ${GRUB2_CUSTOM_FILE} sur le systeme alterne
	fic_tempo_f="/tmp/sys_alt.grubf.alt"
	awk -v usource="${UUID_source}" -v uclone="${UUID_clone}" '
		{
			memfile [NR] = $0
		}

		END {
			for ( i = 1 ; i <= NR ; i++ ) {
				if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+)/ ) {
					found_valid_entry = 0
					for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {
						if ( memfile[j] ~ usource || memfile[j] ~ uclone ) { found_valid_entry = 1 }
					}
					if ( found_valid_entry == 1) {
						for ( k = i ; k <= j ; k++ ) {
							print memfile[k]
						}
						i = j
					} else { i = j }
				} else {
						if ( memfile[i] !~ /^$/ ) {
							print memfile[i]
						}
					}
			}
		}
	' ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE} > ${fic_tempo_f}

	# De la meme maniere, nettoyage des entrees rescue et debugging dans ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
	awk '
		{
			memfile [NR] = $0
		}

		END {
			for ( i = 1 ; i <= NR ; i++ ) {
				if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+.*(rescue|debugging|Rescue|Debugging).*)/ ) {
					for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {
					}
					i = j
				} else {
						if ( memfile[i] !~ /^$/ ) {
							print memfile[i]
						}
					}
			}
		}
	' ${fic_tempo_f} > ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
	
	chmod 0755 ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
	
	# Sauvegarde de la version actuelle de ${FIC_CONFGRUB2}
	\cp -p ${FIC_CONFGRUB2} ${FIC_CONFGRUB2}_${DATE}
	message -m SYSTEME_ALTERNE_I "Sauvegarde du fichier ${FIC_CONFGRUB2} en ${FIC_CONFGRUB2}_${DATE}"

	# Sauvegarde du fichier ${FIC_CONFGRUB2} sur le systeme alterne
	\cp -p ${RACINE_SYS_ALT}${FIC_CONFGRUB2} ${RACINE_SYS_ALT}${FIC_CONFGRUB2}_${DATE}
	message -m SYSTEME_ALTERNE_I "Sauvegarde du fichier ${RACINE_SYS_ALT}${FIC_CONFGRUB2} en ${RACINE_SYS_ALT}${FIC_CONFGRUB2}_${DATE}"
  
	# Installation du bootloader sur le systeme source
	message -m SYSTEME_ALTERNE_I "Installation du bootloader sur ${disk_source}"
	grub2-install ${disk_source}

	# Installation du bootloader sur le systeme clone
	message -m SYSTEME_ALTERNE_I "Installation du bootloader sur ${disk_clone}"
	grub2-install ${disk_clone}

	if [ "${bios_disk_source}" = "hd0" ]; then
		sed -i -e 's/hd1/hd0/g' -e 's/ahci1/ahci0/g' ${GRUB2_CUSTOM_FILE}
		sed -i -e 's/hd0/hd1/g' -e 's/ahci0/ahci1/g' ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
	else
		sed -i -e 's/hd0/hd1/g' -e 's/ahci0/ahci1/g' ${GRUB2_CUSTOM_FILE}
		sed -i -e 's/hd1/hd0/g' -e 's/ahci1/ahci0/g' ${RACINE_SYS_ALT}${GRUB2_CUSTOM_FILE}
	fi

	# Mise a jour du bootloader sur le systeme source
	message -m SYSTEME_ALTERNE_I "Mise a jour du bootloader ${FIC_CONFGRUB2}"
	grub2-mkconfig -o ${FIC_CONFGRUB2}

	# Copie et modification de ${FIC_CONFGRUB2} sur le systeme alterne
	\cp -p ${FIC_CONFGRUB2} ${RACINE_SYS_ALT}${FIC_CONFGRUB2}
	message -m SYSTEME_ALTERNE_I "Copie et modification du fichier ${FIC_CONFGRUB2} sur le systeme alterne"
	if [ "${bios_disk_source}" = "hd0" ]; then
		sed -i -e 's/hd0/hd1/g' -e 's/ahci0/ahci1/g' ${RACINE_SYS_ALT}${FIC_CONFGRUB2}
	else
		sed -i -e 's/hd1/hd0/g' -e 's/ahci1/ahci0/g' ${RACINE_SYS_ALT}${FIC_CONFGRUB2}
	fi

	# Mise a jour du bootloader sur le systeme alterne
	message -m SYSTEME_ALTERNE_I "Mise a jour du bootloader ${RACINE_SYS_ALT}${FIC_CONFGRUB2} sur le systeme alterne"
	
	mount --bind /dev /sys_alt/dev
	mount -t proc /proc /sys_alt/proc
	mount -t sysfs /sys /sys_alt/sys
	mount --bind /run /sys_alt/run
	chroot /sys_alt grub2-mkconfig -o ${FIC_CONFGRUB2}
	sleep 5
	umount /sys_alt/run >/dev/null 2>&1	
	umount /sys_alt/sys >/dev/null 2>&1	
	umount /sys_alt/proc >/dev/null 2>&1	
	umount /sys_alt/dev >/dev/null 2>&1	
}

# Fonction grub_avec_sys_alt
# --------------------------
grub_avec_sys_alt()
{
  # ----------------------------------------------------------------------------
  # Dans le fichier de configuration GRUB, recherche et duplique les 'entrees'
  # pointant vers le nom BIOS du disk source (${bios_disk_source}) en effectuant
  # les modifications suivantes sur les 'entrees' dupliquees :
  # - ajout de "[Systeme Alterne]" a la fin du titre
  # - remplacement du nom BIOS du disk source (${bios_disk_source}) par le
  #   nom BIOS du disk clone (${bios_disk_clone})
  # - remplacement de la chaine "root=LABEL=/" par la chaine
  #   "root=LABEL=/_alt"
  # ----------------------------------------------------------------------------

  flag_error=0
  # FQT fic_tempo0 contient les lignes de FIC_CONFGRUB a ne pas dupliquer
  fic_tempo0="/tmp/sys_alt.grub0"
  fic_tempo1="/tmp/sys_alt.grub1"
  fic_tempo2="/tmp/sys_alt.grub2"
  fic_tempo1_alt="/tmp/sys_alt.grub1.alt"
  fic_tempo2_alt="/tmp/sys_alt.grub2.alt"


  message -m SYSTEME_ALTERNE_I "Ajout eventuel des entrees [Systeme Alterne] dans le fichier : ${FIC_CONFGRUB}"

  # FQT Creation du fichier temporaire (${fic_tempo0))
  # --------------------------------------------------
  /bin/awk '
    $1 == "title"  { next }
    $1 == "root"   { next }
    $1 == "kernel" { next }
    $1 == "initrd" { next }
    { print }
    ' "${FIC_CONFGRUB}" > ${fic_tempo0}
  cr1=$?

  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "Contenu du fichier travail genere (${fic_tempo0}) contenant les 'entrees' a ne pas dupliquer :"
    cat "${fic_tempo0}"
    echo "---------------------------------------------------"
  fi

  # Creation 1er fichier temporaire (${fic_tempo1}) :
  # constitution des 'entrees' concernant ${bios_disk_source} que l'on va dupliquer
  # -------------------------------------------------------------------------------
  grep -v "^#" ${FIC_CONFGRUB} | \
  awk -v var=${bios_disk_source} '{
    if ( $1 == "title" ) lig_title=$0
    if ( $1 == "root"   ) lig_root=$0
    if ( $1 == "kernel" ) lig_kernel=$0
    if ( $1 == "initrd" ) lig_initrd=$0

    if ( $1 == "initrd" )
    {
      if ( index(lig_root,var) != 0 )
      {
        print lig_title
        print lig_root
        print lig_kernel
        print lig_initrd
      }
    }
    }' >${fic_tempo1}



  cr1=$?

  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "Contenu du fichier travail genere (${fic_tempo1}) contenant les 'entrees' a dupliquer :"
    cat ${fic_tempo1}
	echo ${bios_disk_source}
    echo "---------------------------------------------------"
  fi

# pour le le systeme clone
sed -e 's/hd0/hd1/'  ${fic_tempo1} > ${fic_tempo1_alt}


  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "Contenu du fichier travail genere (${fic_tempo1}) contenant les 'entrees' a dupliquer 2 :"
    cat ${fic_tempo1}
    echo "---------------------------------------------------"
  fi



  # Creation 2d fichier temporaire (${fic_tempo2}) :
  # modifications des 'entrees' retenues
  # ------------------------------------------------
  args_pour_le_sed="s/${bios_disk_source}/${bios_disk_clone}/"

  # FQT Le disque source est'il le disque alterne ?
  # le fichier $fic_tempo1 contient il la chaine
  # "title .* [Systeme Alterne]" ?
  # -----------------------------------------------
  if grep "^[[:space:]]*title[[:space:]].*\[Systeme Alterne\]" ${fic_tempo1} >/dev/null 2>&1
  then
    sed -e "${args_pour_le_sed}" \
        -e 's/^\([[:space:]]*title[[:space:]].*\)[[:space:]]*\[Systeme Alterne\]/\1/
            s/\(root=LABEL=[^[:space:]]*\)_alt/\1/
            s#root=/dev/\([^[:space:]]*\)_alt/\([^[:space:]]*\)_alt#root=/dev/\1/\2#
                s#rd_LVM_LV=\([^[:space:]]*\)_alt/\([^[:space:]]*\)_alt#rd_LVM_LV=\1/\2#g
                        s#root=/dev/mapper/\([^[:space:]]*\)_alt\([^[:space:]]*\)_alt#root=/dev/mapper/\1\2#
            s/\(initrd\)[[:space:]]*\(.*\)_ALT/\1 \2/' ${fic_tempo1} > ${fic_tempo2}
    cr2=$?
  else
    sed ${args_pour_le_sed} ${fic_tempo1} | \
    awk '{
      if ( $1 == "title" )
      {
        print $0 " [Systeme Alterne]"
      }
      else
      {
        print $0
      }
      }' | \
	sed -e 's/\(root=LABEL=[^[:space:]]*\)/\1_alt/
		s#root=/dev/\(.*\)/\([^ ]*\)#root=/dev/\1_alt/\2_alt#
		s#root=/dev/mapper/\([^[:space:]]*\)-\([^[:space:]]*\)#root=/dev/mapper/\1_alt-\2_alt#
		s#rd_LVM_LV=\([^[:space:]]*\)/\([^[:space:]]*\)#rd_LVM_LV=\1_alt/\2_alt#
		s/\(initrd[^ \\t]*\)\(.*\)[^ \\t]*$/\1 \2_ALT/'  >${fic_tempo2}

    cr2=$?
  fi

sed -e 's/hd1/hd0/'  ${fic_tempo2} > ${fic_tempo2_alt}


for INITRDFILE in `grep "^[[:space:]]*initrd[[:space:]].*_ALT[[:space:]]*$" ${fic_tempo2} | sed "s/.*initrd.*\///;s/.img.*//"
`
do
        # la variable d'environnement GZIP gene la compression
        # (declare dans /outillage/glob_par/config_systeme.env)
        unset GZIP
        INITR=`echo $INITRDFILE    | cut  -d'-' -f1`
        KERNEL=`echo $INITRDFILE    | cut  -d'-' -f2-6`
        mkinitrd -f /boot/${INITR}-${KERNEL}.img_ALT ${KERNEL} --fstab="${RACINE_SYS_ALT}${FIC_FSTAB}"
        cp -a /boot/${INITR}-${KERNEL}.img_ALT ${RACINE_SYS_ALT}/boot/
	
done

for INITRDFILE in `grep "^[[:space:]]*initrd[[:space:]]" ${fic_tempo2} | grep -v "_ALT[[:space:]]*$" | sed "s/.*initrd.*\///;s/.img.*//"
`
do
        # la variable d'environnement GZIP gene la compression
        # (declare dans /outillage/glob_par/config_systeme.env)
        unset GZIP
        INITR=`echo $INITRDFILE    | cut  -d'-' -f1`
        KERNEL=`echo $INITRDFILE    | cut  -d'-' -f2-6`
        mkinitrd -f /boot/${INITR}-${KERNEL}.img ${KERNEL} --fstab="${RACINE_SYS_ALT}${FIC_FSTAB}"
        cp -a /boot/${INITR}-${KERNEL}.img ${RACINE_SYS_ALT}/boot/
	
done




####

  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "Lignes a ajouter dans le fichier ${FIC_CONFGRUB} :"
    cat ${fic_tempo2}
    echo "---------------------------------------------------"
  fi

  if [ ${cr1} -ne 0 -o ${cr2} -ne 0 ]
  then
    message  -m SYSTEME_ALTERNE_E "Erreur lors de la preparation des modifications dans ${FIC_CONFGRUB}"
    flag_error=1
  else

    # Ajout des nouvelles 'entrees' dans le fichier de configuration GRUB
    # -------------------------------------------------------------------
    for lig in $(grep title ${fic_tempo2} | sed 's/ /_/g')
    do
      message -m SYSTEME_ALTERNE_I  "Ajout entree '${lig}'"
    done

    # FQT Le contenu du fichier fic_tempo2 doit etre avant celui de fic_tempo1
    # si fic_tempo1 contient une ligne concernant le systeme alterne
    # ------------------------------------------------------------------------
    if grep "^[[:space:]]*title[[:space:]].*\[Systeme Alterne\]" ${fic_tempo1} >/dev/null 2>&1
    then
      cat ${fic_tempo0} ${fic_tempo2} ${fic_tempo1} > ${FIC_CONFGRUB}
    else
      cat ${fic_tempo0} ${fic_tempo1} ${fic_tempo2} > ${FIC_CONFGRUB}
    fi

    if [ $? -ne 0 ]
    then
      message -m SYSTEME_ALTERNE_E  "Erreur lors de l'ajout des 'entrees' dans ${FIC_CONFGRUB}"
      flag_error=1
    fi

    # FQT Ne pas oublier de mettre a jour le fichier
    # de configuration GRUB sur le disque clone
    # ----------------------------------------------
    if grep "^[[:space:]]*title[[:space:]].*\[Systeme Alterne\]" ${fic_tempo1} >/dev/null 2>&1
    then
      cat ${fic_tempo0} ${fic_tempo2_alt} ${fic_tempo1_alt} > ${RACINE_SYS_ALT}${FIC_CONFGRUB}
    else
      cat ${fic_tempo0} ${fic_tempo1_alt} ${fic_tempo2_alt} > ${RACINE_SYS_ALT}${FIC_CONFGRUB}
    fi

    if [ $? -ne 0 ]
    then
      message -m SYSTEME_ALTERNE_E  "Erreur lors de la copie de ${FIC_CONFGRUB} dans ${RACINE_SYS_ALT}${FIC_CONFGRUB}"
      flag_error=1
    fi


  fi

  chmod 644 ${FIC_CONFGRUB}
  # FQT
  chmod 644 ${RACINE_SYS_ALT}${FIC_CONFGRUB}
  rm -f ${fic_tempo1} ${fic_tempo2} ${fic_tempo1_alt} ${fic_tempo2_alt}
  unset fic_tempo1 fic_tempo2 cr1 cr2 args_pour_le_sed lig



#echo "clone source est $CLONE_SOURCE"

# Nouvell methode d install de grub
if [ $CLONE_SOURCE == 0 ]
then
hdalt="hd0"
message -m SYSTEME_ALTERNE_I  "systeme original, install grub sur HD1"
else
hdalt="hd0"
message -m SYSTEME_ALTERNE_I  "systeme alterne, install grub sur HD0"
fi

/sbin/grub --batch --no-floppy --device-map=/boot/grub/device.map  >/dev/null 2>&1 << EOF
root ($hdalt,0)
setup ($hdalt)
quit
EOF

  return ${flag_error}
}


# Fonction grub2_sans_sys_alt
# --------------------------
grub2_sans_sys_alt()
{
  # --------------------------------------------------------------------
  # Dans le fichier de configuration GRUB2, supprime toutes les 'entrees'
  # pointant vers le nom BIOS du disk clone (${bios_disk_clone}).
  # --------------------------------------------------------------------

  flag_error=0
  fic_tempo1="/tmp/sys_alt.grub1"

  message  -m SYSTEME_ALTERNE_I "Suppression eventuelle des entrees [Systeme Alterne] dans le fichier : ${FIC_CONFGRUB2}"

	# Section principale : Toutes les lignes du fichier sont mises dans un tableau memfile[]
	# Section END :
		# Pour toutes les lignes du taleau
			# Si on trouve une entree menuentry
				# On parcours la section menuentry jusqu'au caractere de fin {
					# Si on trouve l'occurence du contenu de ${bios_disk_clone} ==> found_clone=1

				# Sinon (on n'a pas trouve de section menuentry qui utilise ${bios_disk_clone}
				# on affiche toutes les lignes et on repart de i=j

				# Si on a trouve une section menuentry qui utilise ${bios_disk_clone}
      	# on affiche rien et on repart de i=j
			# Sinon (la ligne n'est pas une ligne menuentry, on l'affiche


	awk -v var="${bios_disk_clone}" '

		{
			memfile [NR] = $0
		}

  	END {
			for ( i = 1 ; i <= NR ; i++ ) {
			if ( memfile[i] ~ /(^[[:space:]]*menuentry[[:space:]]+)/ ) {
					found_clone = 0
					for ( j = i+1 ; memfile[j] !~ /\}/ ; j++ ) {
						if ( memfile[j] ~ var ) { found_clone = 1 }
					}
					if ( found_clone == 0 ) {
						for ( k = i ; k <= j ; k++ ) {
							print memfile[k]
						}
						i = j
					} else { i = j }
				} else {
					print memfile[i]
					}
			}
		}
	' ${FIC_CONFGRUB2} >${fic_tempo1}

  cr=$?

  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "Contenu du fichier travail genere (${fic_tempo1}) qui va remplacer ${FIC_CONFGRUB2} :"
    echo "Suppression des entrees bios_disk_clone=${bios_disk_clone} dans ${FIC_CONFGRUB2} :"
    cat ${fic_tempo1}
    echo "---------------------------------------------------"
  fi

  if [ ${cr} -ne 0 ]
  then
    message  -m SYSTEME_ALTERNE_E  "Erreur lors de la preparation des modifications dans ${FIC_CONFGRUB2}"
    flag_error=1
  else
    \mv -f ${fic_tempo1} ${FIC_CONFGRUB2}
    if [ $? -ne 0 ]
    then
      message  -m SYSTEME_ALTERNE_E  "Erreur lors du renommage de ${fic_tempo1} en ${FIC_CONFGRUB}"
      flag_error=1
    fi
  fi

  chmod 644 ${FIC_CONFGRUB2}
  unset fic_tempo1 cr

  return ${flag_error}
}



# Fonction grub_sans_sys_alt
# --------------------------
grub_sans_sys_alt()
{
  # --------------------------------------------------------------------
  # Dans le fichier de configuration GRUB, supprime toutes les 'entrees'
  # pointant vers le nom BIOS du disk clone (${bios_disk_clone}).
  # --------------------------------------------------------------------

  flag_error=0
  fic_tempo1="/tmp/sys_alt.grub1"

  message  -m SYSTEME_ALTERNE_I "Suppression eventuelle des entrees [Systeme Alterne] dans le fichier : ${FIC_CONFGRUB}"

  awk -v var=${bios_disk_clone} '{
    if ( $1 == "title" )
    {
      lig_title=$0
    }
    else
    {
      if ( $1 == "root" )
      {
        lig_root=$0
      }
      else
      {
        if ( $1 == "kernel" )
        {
          lig_kernel=$0
        }
        else
        {
          if ( $1 == "initrd" )
          {
            lig_initrd=$0
          }
          else 
          {
            print $0
          }
        }
      }
    }
    if ( $1 == "initrd" )
    {
      if ( index(lig_root,var) == 0 )
      {
        print lig_title
        print lig_root
        print lig_kernel
        print lig_initrd
      }
    }
    }' ${FIC_CONFGRUB} >${fic_tempo1}
  cr=$?

  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "Contenu du fichier travail genere (${fic_tempo1}) qui va remplacer ${FIC_CONFGRUB} :"
    cat ${fic_tempo1}
    echo "---------------------------------------------------"
  fi

  if [ ${cr} -ne 0 ]
  then

    message  -m SYSTEME_ALTERNE_E  "Erreur lors de la preparation des modifications dans ${FIC_CONFGRUB}"
    flag_error=1

  else

    mv -f ${fic_tempo1} ${FIC_CONFGRUB}
    if [ $? -ne 0 ]
    then
      message  -m SYSTEME_ALTERNE_E  "Erreur lors du renommage de ${fic_tempo1} en ${FIC_CONFGRUB}"
      flag_error=1
    fi

  fi

  chmod 644 ${FIC_CONFGRUB}
  unset fic_tempo1 cr

  return ${flag_error}
}



update_clone_grub () {
# -------------------------------------------------------------------------------
# Pour etre sur que les 'entrees' vers le systeme alterne (c'est a dire celles
# pointant vers le nom BIOS du disk clone (${bios_disk_clone}) soient bien a jour
# par rapport a celles pointant vers le systeme source (c'est a dire celles
# pointant vers le nom BIOS du disk source (${bios_disk_source}),
# on commence par supprimer toutes les entrees vers le systeme alterne puis on
# les recree
# -------------------------------------------------------------------------------

	message  -m SYSTEME_ALTERNE_I  "MISE A JOUR DES ENTREES [Systeme Alterne] DANS LA CONFIGURATION DE GRUB"

	# Suppression des 'entrees' vers systeme alterne
	# ----------------------------------------------

		# A partir de EL 7 c'est grub2 qui est installe
	if [ $OSLEVELM -lt 7 ]; then
		grub_sans_sys_alt
		RC=$?
	else
		grub2_sans_sys_alt
		RC=$?
	fi

	if [ $RC -ne 0 ]
	then
		terminer_ko
	else

  	# Recreation des 'entrees' vers systeme alterne
  	# ---------------------------------------------
  
		# A partir de EL 7 c'est grub2 qui est installe
		if [ $OSLEVELM -lt 7 ]; then
			grub_avec_sys_alt
			RC=$?
		else
			grub2_avec_sys_alt
			RC=$?
		fi

  	if [ $RC -ne 0 ]
  	then
    	terminer_ko
  	fi
	fi
# ===============================================
# update_clone_grub
# ===============================================
}



create_clone_fstab () {

# Definition nom complet du fichier "/etc/fstab" sur le systeme alterne
# (il est donc localise sous ${RACINE_SYS_ALT})
# ---------------------------------------------------------------------
fstab_clone="${RACINE_SYS_ALT}${FIC_FSTAB}"

message  -m SYSTEME_ALTERNE_I "RECONSTRUCTION DE ${FIC_FSTAB} SUR LE SYSTEME ALTERNE"
message  -m SYSTEME_ALTERNE_I "Nom complet du fichier modifie : ${fstab_clone}"

if [ ! -s "${fstab_clone}" ]
then
	message  -m SYSTEME_ALTERNE_E  "Fichier ${fstab_clone} absent ou vide"

		# A partir de EL 7 c'est grub2 qui est installe
	if [ $OSLEVELM -lt 7 ]; then
		demontage_fs_clone
		grub_sans_sys_alt
	else
		demontage_fs_clone_el7
		grub2_sans_sys_alt
	fi
	terminer_ko
fi

i=0
if [ ! "${nb_lv}" ]; then
	nb_lv=${#lv_clone_name[*]}
fi

let nb_part_total=${nb_part}+${nb_lv}
while [ ${i} -lt ${nb_part_total} ]
do
	let i=$i+1
	case ${typ_part[$i]} in
		'82' )
			rename_fs_fstab_clone ${i}
		;;
		'83' )
			rename_fs_fstab_clone ${i}
		;;
		* )
			# Seules les partitions de type '82' ou '83' sont concernees par /etc/fstab
			# les autres partitions sont ignorees
			#
			#echo "==== typ_part[$i]=${typ_part[$i]} == part_src[$i]=${part_src[$i]} == part_clone[$i]=${part_clone[$i]} == label_part[$i]=${label_part[$i]}"
		;;
	esac
done

# remise en place des droits sur le fichier, par precaution
# ---------------------------------------------------------
chmod 644 ${fstab_clone}

unset fstab_clone cr1 cr2
#============================================================
#    fIN create_clone_fstab
# ===========================================================
}

rename_fs_fstab_clone () {
# Recherche du filesystem, par le nom de sa partition,
# et le cas echeant, remplacement par le nom de la partition clone
# ----------------------------------------------------------------

if [ ! "${vg_src}" ]
then
	vg_src=${vgroot}
fi
vg_clone="$(nom_clone $vg_src)"
#echo "typ_part[$i]=${typ_part[$i]} ===== part_src[$i]=${part_src[$i]} ===== typ_fs[$i]=${typ_fs[$i]} ==== ptm_fs[$i]=${ptm_fs[$i]}"
i=$1
case ${part_src[$i]} in
	/dev/${vg_src}/* )
		lv_name=$(echo ${part_src[$i]}|awk -F"/" '{print $NF }')
		lv_clonename="$(nom_clone $lv_name)"  
		TEMP_I=${i}
		message   -m SYSTEME_ALTERNE_I "Remplacement de /dev/mapper/${vg_src}-$lv_name par /dev/mapper/${vg_clone}-$lv_clonename"
		i=${TEMP_I}
		sed -e "s#\(^/dev/mapper/\)${vg_src}-\(${lv_name}.*$\)#\1${vg_clone}-\2#g;s#\(^/dev/\)${vg_src}/\(${lv_name}.*$\)#\1${vg_clone}/\2#g" ${fstab_clone} >${fstab_clone}.tmp
		sed -i -e "s#\(^/dev/.*${vg_clone}[/-]\)${lv_name}[[:space:]]\(.*$\)#\1${lv_clonename} \2#g" ${fstab_clone}.tmp
		cr1=$?
		mv -f ${fstab_clone}.tmp ${fstab_clone}
		cr2=$?
	;;
	${disk_source}* )
		if [ $(awk -v var=${part_src[$i]} '{ if ( $1 == var ) print $0 }' ${fstab_clone} | wc -l) -eq 1 ]
		then
			#MODIF KSH93 de rhel6
			TEMP_I=${i}
			message   -m SYSTEME_ALTERNE_I "Remplacement de ${part_src[$i]} par ${part_clone[$i]}"
			i=${TEMP_I}
			#set -x
			#echo "=========== 83 ps=${part_src[$i]} pc=${part_clone[$i]} ======================="
			awk -v ps="${part_src[$i]}" -v pc="${part_clone[$i]}" '{
				if ( $1 == ps )
				{
					a=( length($1) + 1 )
					printf("%s%s\n",pc,substr($0,a))
				}
				else
				{
					print $0
				}
				}' ${fstab_clone} >${fstab_clone}.tmp

			cr1=$?

			if [ "${DEBUG}" = "1" ]
			then
				echo "---------------------------------------------------"
				echo "Contenu du fichier ${fstab_clone} avant modification :"
				cat ${fstab_clone}
			fi

			mv -f ${fstab_clone}.tmp ${fstab_clone}
			cr2=$?

			if [ "${DEBUG}" = "1" ]
			then
				echo "---------------------------------------------------"
				echo "Contenu du fichier ${fstab_clone} apres modification :"
				cat ${fstab_clone}
				echo "---------------------------------------------------"
			fi

			if [ ${cr1} -ne 0 -o ${cr2} -ne 0 ]
			then
				message  -m SYSTEME_ALTERNE_E "Erreur lors de la modification du fichier ${fstab_clone}"

					# A partir de EL 7 c'est grub2 qui est installe
				if [ $OSLEVELM -lt 7 ]; then
					demontage_fs_clone
					grub_sans_sys_alt
				else
					demontage_fs_clone_el7
					grub2_sans_sys_alt
				fi
				terminer_ko
			fi
			#set +x
		else
			# Sinon, recherche du filesystem, par son LABEL,
			# et le cas echeant, remplacement par le LABEL de la partition clone
			# ("<label_partition_source>_alt")
			# 
			# ------------------------------------------------------------------  
			#part_src_mapper=$(echo "${part_src[$i]}"|sed "s#/dev/#/dev/mapper/#"|sed "s#/dev/mapper/\(.*\)/\(.*\)#/dev/mapper/\1-\2#")
			#echo "======== part_src[$i]=${part_src[$i]} ======== label_part[$i]=${label_part[$i]} ======= part_src_mapper=$part_src_mapper ====================="
			if [ $(awk -v var="${label_part[$i]}" '{ if ( $1 == "LABEL="var ) print $0 }' ${fstab_clone} | wc -l) -eq 1 ]
			then
				# FQT
				label_part_alt=$(nom_clone ${label_part[$i]})
				TEMP_I=${i}
				message   -m SYSTEME_ALTERNE_I "Remplacement de LABEL=${label_part[$i]} par LABEL=${label_part_alt}"
				i=${TEMP_I}

				# FQT
				#awk -v ls="${label_part[$i]}" '{
				awk -v ls="${label_part[$i]}" -v lc="${label_part_alt}" '{
					if ( $1 == "LABEL="ls )
					{
						a=( length($1) + 1 )
						# FQT
						#printf("LABEL=%s_alt%s\n", ls, substr($0,a))
						printf("LABEL=%s%s\n", lc, substr($0,a))
					}
					else
					{
						print $0
					}
				}' ${fstab_clone} >${fstab_clone}.tmp
				cr1=$?

				if [ "${DEBUG}" = "1" ]
				then
					echo "---------------------------------------------------"
					echo "Contenu du fichier ${fstab_clone} avant modification :"
					cat ${fstab_clone}
				fi

				mv -f ${fstab_clone}.tmp ${fstab_clone}
				cr2=$?

				if [ "${DEBUG}" = "1" ]
				then
					echo "---------------------------------------------------"
					echo "Contenu du fichier ${fstab_clone} apres modification :"
					cat ${fstab_clone}
					echo "---------------------------------------------------"
				fi

				if [ ${cr1} -ne 0 -o ${cr2} -ne 0 ]
				then
					message  -m SYSTEME_ALTERNE_E "Erreur lors de la modification du fichier ${fstab_clone}"

						# A partir de EL 7 c'est grub2 qui est installe
					if [ $OSLEVELM -lt 7 ]; then
						demontage_fs_clone
						grub_sans_sys_alt
					else
						demontage_fs_clone_el7
						grub2_sans_sys_alt
					fi
					terminer_ko
				fi

			else
				#MODIF RHEL6 partition de /boot utilise UUID du device
				if [ $($GREP "^UUID=" $FIC_FSTAB|wc -l) -eq 1 ]
				then
					TROUVE=$($AWK -v PTM=${ptm_fs[$i]} '$1~/^UUID=/ && $2==PTM' $FIC_FSTAB |wc -l)
					if [ $TROUVE -ge 1 ]
					then
							# A partir de EL 7 xfs est utilise
						if [ $OSLEVELM -lt 7 ]; then
							UUID_source=$(/sbin/tune2fs -l ${part_src[$i]}|awk 'NF==3 && $0~/^Filesystem UUID:/ { print $3 }')
							UUID_clone=$(/sbin/tune2fs -l ${part_clone[$i]}|awk 'NF==3 && $0~/^Filesystem UUID:/ { print $3 }')
						else
							UUID_source=$(xfs_admin -u ${part_src[$i]} | awk '$0~/UUID =/ { print $NF }')
							UUID_clone=$(xfs_admin -u ${part_clone[$i]} | awk '$0~/UUID =/ { print $NF }')
						fi

						TEMP_I=${i}
						message   -m SYSTEME_ALTERNE_I  "Remplacement de UUID_source=${UUID_source} par UUID_alt=${UUID_clone}"
						i=${TEMP_I}
						$AWK -v UUID_source=${UUID_source} -v UUID_clone=${UUID_clone} '
							$0~UUID_source {sub(UUID_source,UUID_clone,$0) ;print $0 ;next}
							{ print $0 }
							' ${fstab_clone} >${fstab_clone}.tmp
						mv -f ${fstab_clone}.tmp ${fstab_clone}
					else
						TEMP_I=${i}
						message  -m SYSTEME_ALTERNE_W  "ATTENTION: le filesystem correspondant a la partition ${part_src[$i]}"
						message  -m SYSTEME_ALTERNE_W  "n'a pas ete trouve dans ${fstab_clone}, pas de mise a jour sur le systeme alterne"
						i=${TEMP_I}
						FLAG_ERROR=1
					fi
				fi
			fi
		fi
	;;
	* )
		echo "Partition ${part_src[$i]} non trouve dans la fstab"
	;;
esac

}



copy_source_to_clone () {
	point_montage_alterne=$2
	racine_sys_alt=$1

	cd ${point_montage_alterne}
	if [ $? -ne 0 ]
	then
		message  -m SYSTEME_ALTERNE_E "Erreur lors du deplacement dans ${point_montage_alterne}"

			# A partir de EL 7 c'est grub2 qui est installe
		if [ $OSLEVELM -lt 7 ]; then
			demontage_fs_clone
			grub_sans_sys_alt
		else
			demontage_fs_clone_el7
			grub2_sans_sys_alt
		fi
		terminer_ko
	fi

  # Lancement de la copie des fichiers avec cpio
  # --------------------------------------------
  if [ "${DEBUG}" = "1" ]
  then
    echo "---------------------------------------------------"
    echo "COMMANDE EXECUTEE:"
    echo "find . -xdev | ( cpio -ocvB | ( cd ${racine_sys_alt}${point_montage_alterne} ; cpio -icvdumB ) )"
    echo "---------------------------------------------------"

    # CTE : la sortie de cette commande est redirigee vers /dev/null pour eviter un fichier de log
    # important lorsque, en mode debug, la sortie de systeme_alterne.ksh est redirige vers un
    # fichier de sortie
    # pour un mode debug complet, supprimer la redirection standard et erreur vers /dev/null
    # de la commande ci-dessous

    find . -xdev | ( cpio -ocvB | ( cd ${racine_sys_alt}${point_montage_alterne} ; cpio -icvdumB ) )
    cr=$?

  else

    find . -xdev | ( cpio -ocvB | ( cd ${racine_sys_alt}${point_montage_alterne} ; cpio -icvdumB ) ) >/dev/null 2>&1
    cr=$?

  fi
  # on garde les permissions originelles
  perm=`stat -c%a ${point_montage_alterne}`
  chmod $perm  ${racine_sys_alt}${point_montage_alterne}


  if [ ${cr} -ne 0 ]
  then
    message   -m SYSTEME_ALTERNE_E "Erreur lors de la copie des fichiers du filesystem sur ${point_montage_alterne}"
    message   -m SYSTEME_ALTERNE_E "Commande en echec: find . -xdev | ( cpio -ocvB | ( cd ${racine_sys_alt}${point_montage_alterne} ; cpio -icvdumB ) )"

			# A partir de EL 7 c'est grub2 qui est installe
		if [ $OSLEVELM -lt 7 ]; then
    	demontage_fs_clone
			grub_sans_sys_alt
		else
    	demontage_fs_clone_el7
			grub2_sans_sys_alt
		fi
    terminer_ko
  fi

  if [ "${DEBUG}" = "1" ]
  then
    echo "nbre de fichiers sur FS source ${point_montage_alterne}:"
    find ${point_montage_alterne} -xdev | wc -l

    echo "nbre de fichiers sur FS clone ${racine_sys_alt}${point_montage_alterne}:"
    find ${racine_sys_alt}${point_montage_alterne} -xdev | wc -l
    echo "---------------------------------------------------"
  fi



# ==================================================
# Fin copy_source_to_clone
# ==================================================
}



# Fonction controle_mount_point
controle_mount_point() {
  # --------------------------------------------------------------------------
  # Contole l'existance des points de montage:
  # Retoune une premiere chaine de caracteres constituee de la partie existante
  # du point de montage et une seconde constituee de la partie inexistante
  # du point de montage qui sera a creer.
  # --------------------------------------------------------------------------
  PATH_FULL=$1

  while echo ${PATH_FULL} | grep '//'>/dev/null 2>&1; do
    PATH_FULL=$( echo ${PATH_FULL} | sed 's/\/\//\//g' )
  done

  echo "${PATH_FULL}" | grep "^/" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo  -m SYSTEME_ALTERNE_E "Erreur le point de montage ${PATH_FULL} ne commence pas par '/' "
    return 1
  fi

  PATH_FULL=$( echo "${PATH_FULL}" | sed "s/\/[ \t]*$//" )

  IFS_SAV="$IFS"
  IFS="/"
  set -a PATH_PART $1
  IFS=${IFS_SAV}

  cd /
  PATH_PRESENT="/"
  PATH_LOST=""
  i=1
  while [ $i -lt ${#PATH_PART[*]} ]; do
    if [ ! -d ${PATH_PART[$i]} ]; then
      print "${PATH_PRESENT}" "${PATH_FULL#$PATH_PRESENT}"
      return 0
    fi
    cd ${PATH_PART[$i]}
    PATH_PRESENT=${PATH_PRESENT}${PATH_PART[$i]}"/"
    (( i++ ))
  done
  #echo ${PATH_PRESENT} ""
  return 0
}


demontage_fs_clone_el7() {
	message -m SYSTEME_ALTERNE_I "DEMONTAGE DES FS CLONES"

	fic_table="/tmp/table_fs.$(basename ${disk_clone}).$$"

	mount | grep "/sys_alt" | awk '{print length($3)":"$3":"$1}' >${fic_table}

	if [ -f ${fic_table} ]; then
		sort -t":" -n -r ${fic_table} | awk -F: '{print $2}' | while read umountpt
		do
			umount $umountpt >/dev/null 2>&1
			message -m SYSTEME_ALTERNE_I "Demontage de $umountpt"
		done
	fi

	rm -f ${fic_table} 
	unset fic_table umountpt
}

demontage_fs_clone() {
  # --------------------------------------------------------------------------
  # Pour tous les FS clones a demonter, et afin de les demonter du plus bas au
  # plus haut dans l'arborescence,
  # Constitution d'un fichier de travail temporaire avec les champs suivants :
  # - longueur de la chaine de caracteres correspondante au point de montage
  # - nom de la partition clone correspondante
  # Tri de ce fichier sur la longueur de la chaine (de la plus longue a la
  # plus courte).
  # Puis demontage de tous les FS presents dans ce fichier.
  # --------------------------------------------------------------------------
  #  set -x
  fic_table="/tmp/table_fs.$(basename ${disk_clone}).$$"
  >${fic_table}

typeset -i i
i=0
while [ ${i} -lt ${nb_part} ]
do
  i=$i+1
  if [ "${typ_part[$i]}" = "83" ]
  then
    if [ $(mount | egrep "^${part_src[$i]}[[:space:]]|^$(echo ${part_src[$i]} | sed "s/dev/dev\/mapper/;s/\/\([^\/]*\)$/-\\1/")[[:space:]]" | wc -l) -eq 1 ]
    then
      #
      # memo: ${#ptm_fs[n]} renvoi la longueur du 'n'ieme element du tableau 'ptm_fs'
      #
      # FQT
      # echo "${#ptm_fs[$i]}:/sys_alt${ptm_fs[$i]}:${part_clone[$i]}" >>${fic_table}
      echo "${#ptm_fs[$i]}:/sys_alt${ptm_fs[$i]}:${part_clone[$i]}:$i" >>${fic_table}
    fi
  fi
done

  if [ -s "${fic_table}" ]
  then
    sort -t":" -n -r ${fic_table} >${fic_table}.sort
    mv -f ${fic_table}.sort ${fic_table}

    message  -m SYSTEME_ALTERNE_I  "DEMONTAGE DES FS CLONES"

    if [ "${DEBUG}" = "1" ]
    then
      echo "---------------------------------------------------"
      echo "Contenu du fichier travail genere (${fic_table}) pour les FS clones a demonter :"
      echo "(longueur_point_montage_fs:nom_partition_clone)"
      cat ${fic_table}
      echo "---------------------------------------------------"
    fi

    # FQT
    # for part in $(cut -d":" -f2 ${fic_table})
    for lig in $(cat ${fic_table})
    do
      IFS_SAV="$IFS"
      IFS=":"
      set x $lig
      part=$3
      ind=$5
      IFS="${IFS_SAV}"
      # FQT fin

      message  -m SYSTEME_ALTERNE_I "Demontage de ${part}"

      umount ${part}
      if [ $? -ne 0 ]
      then
        message  -m SYSTEME_ALTERNE_E "Erreur lors du demontage de ${part}"
        FLAG_ERROR=1
      fi

      # FQT suppression de la partie du point 
      # de montage qui a due etre creee
      rep_perdu=${ptm_fs_perdu[$ind]}
      while [ "${rep_perdu}" ]; do
        rmdir ${ptm_fs_present[$ind]}${rep_perdu} >/dev/null 2>&1
        if [ $? -ne 0 ]; then
          message  -m SYSTEME_ALTERNE_E "Erreur rmdir ${ptm_fs_present[$ind]}${rep_perdu}"
          FLAG_ERROR=1
          break
        fi
        rep_perdu=$(echo ${rep_perdu} | sed 's/\/*[^\/]*[ \t]*$//')
      done
      # FQT fin
    done
  fi

  rm -f ${fic_table} 
  unset fic_table part mount_point
}

create_clone_mountpoint () {
# =========================================================================
message  -m SYSTEME_ALTERNE_I "MONTAGE DES FS CLONES ET RECOPIE DES DONNEES"
# =========================================================================
# ------------------------------------------------------------------------------
# Pour tous les FS a copier, et afin de les traiter du plus haut au plus bas
# dans l'arborescence,
# Constitution d'un fichier de travail temporaire avec les champs suivants :
# - longueur de la chaine de caracteres correspondante au point de montage du FS
# - point de montage du FS
# - nom de la partition clone
# Tri de ce fichier sur la longueur de la chaine (de la plus courte a la plus
# longue).
# Puis pour tous les FS presents dans ce fichier, FS apres FS, montage du FS
# clone et recopie des fichiers.
#
# ${RACINE_SYS_ALT} est utilise comme point de montage 'racine' du systeme
# alterne.
# ------------------------------------------------------------------------------

# Creation du repertoire 'racine' du systeme alterne, si necessaire 
# -----------------------------------------------------------------
[ ! -d ${RACINE_SYS_ALT} ] && mkdir ${RACINE_SYS_ALT}

# Constitution et tri du fichier temporaire
fic_table="/tmp/table_fs.$(basename ${disk_source}).$$"
>${fic_table}

typeset -i i
i=0
COUNTER=${nb_part}
while [ ${i} -lt $COUNTER ]
do
	i=$i+1
	if [ "${typ_part[$i]}" = "83" ]
	then
		#echo "
		if [ $(mount | sed "s#/dev/mapper/\([^-]*\)-\([^-]*\)#/dev/\1\/\2#" | egrep "^${part_src[$i]}[[:space:]]|^${part_src[$i]}[[:space:]]" | wc -l) -eq 1 ]
		then
			#
			# memo: ${#ptm_fs[n]} renvoi la longueur du 'n'ieme element du tableau 'ptm_fs'
			#
			# FQT
			echo "${#ptm_fs[$i]}:${ptm_fs[$i]}:${part_clone[$i]}:$i" >>${fic_table}
		else
			TEMP_I=${i}	
			message  -m SYSTEME_ALTERNE_I "Rappel: partition ${part_src[$i]} non montee, pas de recopie"
			i=${TEMP_I}
		fi
	fi
done

sort -t":" -n ${fic_table} >${fic_table}.sort
mv -f ${fic_table}.sort ${fic_table}

if [ "${DEBUG}" = "1" ]
then
	echo "---------------------------------------------------"
	echo "Contenu du fichier travail genere (${fic_table}) pour les FS a copier :"
	echo "(longueur_point_montage_fs:point_montage_fs:nom_partition_clone)"
	cat ${fic_table}
	echo "---------------------------------------------------"
fi

# Traitement des lignes du fichier temporaire
for lig in $(cat ${fic_table})
do
	lv_clone=$(echo $lig |cut -d":" -f3)
	mount_point=$(echo $lig |cut -d":" -f2)
	# FQT
	ind=$(echo $lig | cut -d ":" -f4)

	message  -m SYSTEME_ALTERNE_I "Recopie du filesystem ${mount_point}"

	# Montage de la partition clone ${lv_clone} sur ${RACINE_SYS_ALT}${mount_point}
	# ------------------------------------------------------------------------------
	[ "${DEBUG}" = "1" ] && echo "Montage de la partition ${lv_clone} sur ${RACINE_SYS_ALT}${mount_point}"
	# FQT
	# Controle de l'existance du point de montage
	ptm="$(controle_mount_point ${RACINE_SYS_ALT}$mount_point)"
	if [ $? -ne 0 ]; then

			# A partir de EL 7 c'est grub2 qui est installe
		if [ $OSLEVELM -lt 7 ]; then
			demontage_fs_clone
			grub_sans_sys_alt
		else
			demontage_fs_clone_el7
			grub2_sans_sys_alt
		fi
		terminer_ko
	fi

	set x $ptm
	ptm_fs_present[$ind]=$2
	ptm_fs_perdu[$ind]=$3

	# Creation de la partie du point de montage inexistante
	if [ "${ptm_fs_perdu[$ind]}" ]; then
		perm=`stat -c%a ${mount_point}`
		mkdir -p ${RACINE_SYS_ALT}${mount_point} > /dev/null 2>&1
		chmod $perm  ${RACINE_SYS_ALT}${mount_point}
		if [ $? -ne 0 ]; then
			message  -m SYSTEME_ALTERNE_E "Erreur creation repertoire ${RACINE_SYS_ALT}${mount_point}}"

				# A partir de EL 7 c'est grub2 qui est installe
			if [ $OSLEVELM -lt 7 ]; then
				demontage_fs_clone
				grub_sans_sys_alt
			else
				demontage_fs_clone_el7
				grub2_sans_sys_alt
			fi
			terminer_ko
		fi
	fi
	# FQT Fin

	mount ${lv_clone} ${RACINE_SYS_ALT}${mount_point}
	if [ $? -ne 0 ]
	then
		message  -m SYSTEME_ALTERNE_E "Erreur lors du montage de ${lv_clone} sur ${RACINE_SYS_ALT}${mount_point}"

			# A partir de EL 7 c'est grub2 qui est installe
		if [ $OSLEVELM -lt 7 ]; then
			demontage_fs_clone
			grub_sans_sys_alt
		else
			demontage_fs_clone_el7
			grub2_sans_sys_alt
		fi
		terminer_ko
	fi

	# Deplacement dans le point de montage du filesystem source
	# (car les noms de fichiers passes a la commande cpio doivent imperativement
	# etre en chemin relatif, c'est a dire commencer par un ".")
	# --------------------------------------------------------------------------
	[ "${DEBUG}" = "1" ] && echo "Deplacement dans ${mount_point}"

	copy_source_to_clone ${RACINE_SYS_ALT} ${mount_point}
	
done

rm -f ${fic_table}
unset fic_table cr lv_clone mount_point


# ========================================
# ======== Fin create_mountpoint =============
# ========================================
}


create_partition_table_clonedisk() {
	message  -m SYSTEME_ALTERNE_I "(RE-)CREATION DE LA TABLE DES PARTITIONS SUR LE DISQUE CLONE"

	# Recreation table de partition avec sfdisk (utilisation de l'option "-d")
	# ------------------------------------------------------------------------
	fic_table="/tmp/part_table.$(basename ${disk_source}).$$"

	######
	# Prise en charge de geometrie de disque differente
	$SFDISK -d ${disk_source} >${fic_table}
	if [ $OSLEVELM -lt 7 ]; then
		CHS_PARAM=$(fdisk -l ${disk_source} | sed -r '3!d;s#([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+).*#-H \1 -S \2 -C \3#')
	else
		CHS_PARAM=$(/sbin/fdisk -c=dos -u=cylinders -l ${disk_source} | sed -r '3!d;s#([0-9]+)[^0-9]+([0-9]+)[^0-9]+([0-9]+).*#-H \1 -S \2 -C \3#')
	fi

	RESULT=$($SFDISK --force ${CHS_PARAM} -L ${disk_clone} <${fic_table} 2>/dev/null)
	cr=$?

	fin=0

		# Update du 20/02/2014
		# Forces la MAJ de la table des partitions des disques
	sleep 10
	partprobe >/dev/null 2>&1
	sleep 10
	/usr/bin/rescan-scsi-bus.sh >/dev/null 2>&1


	while [ $fin -eq 0 ]; do
		fin=1
		for part in $($SFDISK -l ${disk_clone}| grep -v "Empty$" | grep "^${disk_clone}" | cut -d" " -f1); do
			ls $part > /dev/null 2>&1
			if [ $? -ne 0 ]; then
					# Ajout version 2.1.3. Il est parfois necessaire de refaire partprobe et rescan
					# pour que les devices des partitions soient visibles dans /dev
				partprobe >/dev/null 2>&1
				sleep 10
				/usr/bin/rescan-scsi-bus.sh >/dev/null 2>&1
				fin=0
			fi
		done
	done

	if [ ${cr} -ne 0 ]
	then
			# Si sfdisk a genere un code d'erreur mais que le message
			# successfully wrote est present on considere que c'est ok
		echo "$RESULT" | grep -iq "successfully wrote"
		if [ $? -ne 0 ]; then
			message  -m SYSTEME_ALTERNE_E "Erreur lors de la (re-)creation des partitions sur ${disk_clone}"
			message  -m SYSTEME_ALTERNE_E "Commande en echec: sfdisk ${disk_clone} <${fic_table}"

			##grub_sans_sys_alt
			terminer_ko
		fi
	fi


	rm -f ${fic_table}
	unset fic_table cr
}


format_partition_clonedisk () {
# ========================================================================
message  -m SYSTEME_ALTERNE_I  "CREATION DES PARTITIONS SUR LE DISQUE CLONE"
# ========================================================================
# ------------------------------------------------------------------------------
# Seules les partitions de type '82' et '83' sont traitees dans cette procedure.
# (pour l'integration de LVM, il faudra prendre en compte les partitions de type
# 8E (Linux LVM)).
# ------------------------------------------------------------------------------

typeset -i nb_lv
nb_lv=0
typeset -i i
i=0
while [ ${i} -lt ${nb_part} ]
do
	i=$i+1
	#echo "i=$i ==== {typ_part[i]}=${typ_part[$i]} ==== nb_part=${nb_part}"
	case ${typ_part[$i]} in
		'8e' )
			#MODIF KSH93 de rhel6
			TEMP_I=${i}
			message  -m SYSTEME_ALTERNE_I "Creation d'un PV sur ${part_clone[$i]}"
			i=${TEMP_I}
			pvcreate "${part_clone[$i]}" >/dev/null 2>&1

			vg_src=$($PVS -o pv_name,vg_name "${part_src[$i]}" 2>/dev/null|$AWK -v PART_SRC="${part_src[$i]}" '$1~PART_SRC { print $2 }')
			# FQT
			vg_clone=$(nom_clone $vg_src)
			#MODIF KSH93 de rhel6
			TEMP_I=${i}
			message  -m SYSTEME_ALTERNE_I "Creation du vg alterne : ${vg_clone}"
			i=${TEMP_I}
			#MODIF vg_src_PEsize="`vgdisplay ${vg_src} | grep "PE Size" | awk '{print $3$4}'`"
			vg_src_PEsize=$($VGS -o vg_extent_size ${vg_src} 2>/dev/null|$AWK '{print $1}')
			# FQT
			sleep 4	
			$VGCREATE -s "${vg_src_PEsize}" "$vg_clone" "${part_clone[$i]}" >/dev/null 2>&1

			#MODIF RHEL6 lv_src="`lvs ${vg_src} | tail -n +2 | awk '{print $1}'`"
			lv_src=$($LVS -o lv_name ${vg_src} 2>/dev/null|$AWK '{print $1}')

			for lv_act in ${lv_src}
			do
				# FQT
				lv_clone=$(nom_clone $lv_act)
				#MODIF KSH93 de rhel6
				TEMP_I=${i}
				message  -m SYSTEME_ALTERNE_I "Creation du lv alterne : /dev/${vg_clone}/${lv_clone}"
				i=${TEMP_I}
				# MODIF KSH93 lv_size="`lvdisplay /dev/${vg_src}/${lv_act} | grep "Current LE" | awk '{print $NF}'`"
				lv_size="$(lvdisplay /dev/${vg_src}/${lv_act} 2>/dev/null| awk '$0~/Current LE/ {print $NF}')"
					# FQT
				$LVCREATE -n ${lv_clone} -l ${lv_size} ${vg_clone} >/dev/null 2>&1
				# MODIF KSH93 lv_fs_label="`tune2fs -l "/dev/${vg_src}/${lv_act}" 2>/dev/null | grep "Filesystem volume name" | awk '{print $NF}'`"
					# A partir de EL 7 xfs est utilise
				if [ $OSLEVELM -lt 7 ]; then
					lv_fs_label="$(tune2fs -l "/dev/${vg_src}/${lv_act}" 2>/dev/null | awk '$0~/Filesystem volume name:/ { print $NF }')"
				else
					lv_fs_label=$(xfs_admin -l "/dev/${vg_src}/${lv_act}" 2>/dev/null | awk '$0~/label =/ { print $NF }')
				fi
				#MODIF KSH93 lv_fs_type="`grep "^/dev/mapper/${vg_src}-${lv_act}[[:space:]]" /etc/fstab | awk '{print $3}'`"
				lv_fs_type=$(grep "^/dev/mapper/${vg_src}-${lv_act}[[:space:]]" /etc/fstab | awk '{print $3}')
				#
				if [ "${lv_fs_type}" = "" ]
				then
					lv_fs_type="$(grep "^LABEL=${lv_fs_label}[[:space:]]" /etc/fstab | awk '{print $3}')"
				fi
				
				
				
			done
		;;
		'82' )
			# Creation espace de swap 
			# -----------------------
			# MODIF KSH93 pour rhel6
			TEMP_I=${i}
			message  -m SYSTEME_ALTERNE_I "Creation swap sur ${part_clone[$i]}"
			i=${TEMP_I}

			if [ "${DEBUG}" = "1" ]
			then
				echo "mkswap ${part_clone[$i]}"	
			fi
			mkswap -f ${part_clone[$i]} >/dev/null 2>&1
			cr=$?
				
			if [ ${cr} -ne 0 ]
			then
				message  -m SYSTEME_ALTERNE_E "Erreur lors de la creation de la swap sur ${part_clone[$i]}"
				message  -m SYSTEME_ALTERNE_I "Commande en echec: mkswap ${part_clone[$i]}"

					# A partir de EL 7 c'est grub2 qui est installe
				if [ $OSLEVELM -lt 7 ]; then
					grub_sans_sys_alt
				else
					grub2_avec_sys_alt
				fi
				terminer_ko
			fi
		;;
		'83' )
			# Creation filesystem
			# -------------------

			# si le type de filesystem n'a pu etre determine sur la partition source,
			# alors pas de creation de filesystem sur la partition clone
			#
			if [ "${typ_fs[$i]}" = '' ]
			then
				# MODIF KSH93 pour rhel6
				TEMP_I=${i}
				message  -m SYSTEME_ALTERNE_I "Rappel: Le type de filesystem pour la partition ${part_src[$i]} de type ${typ_part[$i]}" 
				message  -m SYSTEME_ALTERNE_I  "n'a pas ete determine, pas de creation de filesystem sur la partition ${part_clone[$i]}"
				i=${TEMP_I}
			else
				#MODIF KSH93 de rhel6
				TEMP_I=${i}
				message  -m SYSTEME_ALTERNE_I "Creation filesystem en ${typ_fs[$i]} sur ${part_clone[$i]}"
				i=${TEMP_I}
				# si le type du fs est "ext3", alors commande : "mkfs.ext2 -j"
				# sinon commande : "mkfs.<type_du_fs>"
				#
				#echo "{part_src[$i]}=${part_src[$i]} ====== {part_clone[$i]}=${part_clone[$i]}"
				if [ "${typ_fs[$i]}" = 'ext3' ]
				then
					typ="ext2"
					options="-j"
				elif [ "${typ_fs[$i]}" = 'ext4' ]
				then
					typ='ext4'
					options=""
				else
					typ="${typ_fs[$i]}"
					options=""
				fi
				if [ "${typ_fs[$i]}" = 'xfs' ]; then
					typ="xfs"
					options="-f"
				fi

				# si LABEL present sur la partition source, alors
				# le LABEL de la partition clone = "<label_partition_source>_alt"  
				#
				if [ -n "${label_part[$i]}" ]
				then
					# FQT
					#options="${options} -L ${label_part[$i]}_alt" 
					options="${options} -L $(nom_clone ${label_part[$i]})" 
				fi

					# Si ${part_clone[$i]} est vide c'est qu'elle a ete supprimee avant execution
					# du script sysalt. Le script sysalt a recree la partition mais n'a pas mis a jour
					# les tableaux de ce script pour la partition clone (type, nom ...)
					# On relance donc le script avec les memes arguments
				if [ "${part_clone[$i]}" = "" ]; then
					message -m SYSTEME_ALTERNE_I "Rappel du script $ARGS pour prise en compte partion clone"
					sleep 10
					partprobe >/dev/null 2>&1
					sleep 10
					/usr/bin/rescan-scsi-bus.sh >/dev/null 2>&1
					\rm /var/run/${PROG}.pid >/dev/null 2>&1
					bash $ARGS
					terminer_ok
				fi
				
				if [ "${DEBUG}" = "1" ]
				then
					echo "mkfs.${typ} ${options} ${part_clone[$i]}"
					mkfs.${typ} ${options} ${part_clone[$i]}
					cr=$?
				else
					# echo "mkfs.${typ} ${options} ${part_clone[$i]}"
					mkfs.${typ} ${options} ${part_clone[$i]} >/dev/null 2>&1
					cr=$?
				fi

				if [ ${cr} -ne 0 ]
				then
					message  -m SYSTEME_ALTERNE_E "Erreur lors de la creation du filesystem sur ${part_clone[$i]}"
					message  -m SYSTEME_ALTERNE_E "Commande en echec: mkfs.${typ} ${options} ${part_clone[$i]}"

						# A partir de EL 7 c'est grub2 qui est installe
					if [ $OSLEVELM -lt 7 ]; then
						grub_sans_sys_alt
					else
						grub2_avec_sys_alt
					fi
					terminer_ko
				fi
			fi
		;;
		'f'|' f' )
			# Le type de partition 'f' correspond a une partition etendue,
			# aucune action a mener
			#
		;;
		'0' )
			# Le type 0 est present sur les disques dos de moins de 4 partitions.
			# aucune action a mener
			#
		;;
		* )
			message  -m SYSTEME_ALTERNE_W "ATTENTION: la partition ${part_clone[$i]} de type ${typ_part[$i]} n'est pas traitee"
			FLAG_ERROR=1
		;;
	esac
done

unset typ options cr lv_clone vg_clone
#
# ====== Fin create_partition_clone_disk
# 
}


remove_lvm_device_clonedisk () {

######
# ajout LVM : Nettoyage du disk avant opération.
# TODO: vérif montage...
# MODIF RHEL6 VGNAME="`pvs | grep "^[[:space:]]*${disk_clone}" | awk '{print $2}'`"
VGNAME_clone=$($PVS -o pv_name,vg_name 2>/dev/null|$AWK -v DISK_CLONE=${disk_clone} '$1~DISK_CLONE { print $2 }')
PVNAME_clone=$($PVS -o pv_name,vg_name 2>/dev/null|$AWK -v DISK_CLONE=${disk_clone} '$1~DISK_CLONE { print $1 }')

if [ ! "${VGNAME_clone}" = "" ]
then
	$VGCHANGE -a n "${VGNAME_clone}" >/dev/null 2>&1
	for LVNAME in $($LVS "${VGNAME_clone}" 2>/dev/null| awk '{print $1}')
	do
		$LVREMOVE "/dev/${VGNAME_clone}/${LVNAME}" >/dev/null 2>&1
	done
	$VGREMOVE "${VGNAME_clone}" >/dev/null 2>&1
	$PVCHANGE -a n "${PVNAME_clone}" >/dev/null 2>&1
	$PVREMOVE "${PVNAME_clone}" >/dev/null 2>&1
	sleep 5
fi

}


recupere_infos_systeme_source () {
# ==============================================================================
message -m SYSTEME_ALTERNE_I "CONSTITUTION DES INFOS A PARTIR DU SYSTEME SOURCE"
# ==============================================================================

# nom des partitions sur le disque source
set -a part_src
# nom des partitions sur le disque clone
set -a part_clone
# type(id) des partitions
set -a typ_part
# label des partitions (pour les partitions de type '83')
set -a label_part
# type du filesystem (pour les partitions de type '83')
set -a typ_fs
# point de montage du filesystem (pour les partitions de type '83')
set -a ptm_fs
# FQT
# part du point de montage existant juste avant le montage du fs
set -a ptm_fs_present
# part du point de montage inexistant juste avant le montage du fs
# cas ou un fs a cloner est monte sur un fs non clone
set -a ptm_fs_perdu

#MODIF RHEL6
set -a dm_lv_src
set -a dm_lv_clone

# Nombre de partitions
# --------------------
nb_part=$($SFDISK -l ${disk_source} 2>/dev/null | grep "^${disk_source}" | wc -l)

# Constitution nom des partitions source
# --------------------------------------
i=0
for part in $($SFDISK -l ${disk_source} 2>/dev/null | grep "^${disk_source}" | cut -d" " -f1)
do
  i=$(expr $i + 1)
  part_src[$i]=$part
done

if [ "${DEBUG}" = "1" ]
then
  echo "---------------------------------------------------"
  i=0
  while [ ${i} -lt ${nb_part} ]
  do
    i=$(expr $i + 1)
    echo "partition source ${i} : ${part_src[$i]}"
  done
  echo "---------------------------------------------------"
fi


# Constitution nom des partitions clone
# -------------------------------------
i=0
for part in $($SFDISK -l ${disk_clone}  2>/dev/null | grep "^${disk_clone}" | cut -d" " -f1)
do
  i=$(expr $i + 1)
  part_clone[$i]=${part}
done

if [ "${DEBUG}" = "1" ]
then
  i=0
  while [ ${i} -lt ${nb_part} ]
  do
    i=$(expr $i + 1)
    echo "partition clone ${i} : ${part_clone[$i]}"
  done
  echo "---------------------------------------------------"
fi


# Constitution type des partitions
# --------------------------------
i=0
while [ ${i} -lt ${nb_part} ]
do
  i=$(expr $i + 1)
  typ_part[$i]=$($SFDISK --print-id ${disk_source} ${i})
done

if [ "${DEBUG}" = "1" ]
then
  i=0
  while [ ${i} -lt ${nb_part} ]
  do
    i=$(expr $i + 1)
    echo "type de la partition ${i} : ${typ_part[$i]}"
  done
  echo "---------------------------------------------------"
fi


# Constitution label des partitions (pour les partitions de type '83')
# --------------------------------------------------------------------
i=0
while [ ${i} -lt ${nb_part} ]
do
  i=$(expr $i + 1)
  if [ "${typ_part[$i]}" = "83" ]
  then
    label_part[$i]=$(${LABEL_CMD} ${part_src[i]})
  else
    label_part[$i]=""
  fi
done

if [ "${DEBUG}" = "1" ]
then
  i=0
  while [ ${i} -lt ${nb_part} ]
  do
    i=$(expr $i + 1)
    echo "LABEL de la partition ${i} : ${label_part[$i]}"
  done
  echo "---------------------------------------------------"
fi

# Constitution des LV de FS si presence partition LVM (8e)
#
i=${nb_part}
vg_clone=$(nom_clone ${vgroot})
part_lvm=$(echo ${typ_part[*]}|grep -q '8e' ;echo $?)
if [ $part_lvm -eq 0 ]
then
	#part_lvm=$($PVS -o pv_name 2>/dev/null|awk -v DISK_SOURCE="${disk_source}" '$1~DISK_SOURCE { print $1 }')
		# Correction 2.1.4
	part_lvm=$($PVS -o pv_name 2>/dev/null|awk -v DISK_SOURCE="${disk_source}" '$1~DISK_SOURCE"[0-9]*$" { print $1 }')
	for LV_NAME in $($LVS -o lv_name ${vgroot} 2>/dev/null|awk '{ print $1 }')
	do
		let i=${i}+1
		lv_src_name[$i]=${LV_NAME}
		lv_clone_name[$i]=$(nom_clone ${lv_src_name[$i]})
		part_src[$i]="/dev/${vgroot}/${lv_src_name[$i]}"
		part_clone[$i]="/dev/${vg_clone}/${lv_clone_name[$i]}"
		dm_lv_src[$i]="/dev/mapper/${vgroot}-${lv_src_name[$i]}"
		dm_lv_clone[$i]="/dev/mapper/${vg_clone}-${lv_clone_name[$i]}"
	

		#echo "informations : "
		#echo " ${lv_src_name[$i]}  ${lv_clone_name[$i]}  ${part_src[$i]}  ${part_clone[$i]}  ${dm_lv_src[$i]}  ${dm_lv_clone[$i]} "	
		typ_fs[$i]=$(awk -v var=${dm_lv_src[$i]} -v lv=${part_src[$i]} '$1==var || $1==lv { print $3 }' ${FIC_FSTAB})
		if [ "${typ_fs[$i]}" = 'swap' ]; then
			typ_part[$i]=82
			LV_SWAP="${vgroot}/${lv_src_name[$i]}"
		else
			typ_part[$i]=83
		fi

	done

fi

nb_part=${i}

# Constitution type du filesystem et point de montage du filesystem
# (pour les partitions de type '83')
# -----------------------------------------------------------------
i=0
while [ ${i} -lt ${nb_part} ]
do
	let i=${i}+1
	# MODIF 
	#echo "{typ_part[$i]}=${typ_part[$i]} === part_src[$i]=${part_src[$i]} === dm_lv_src[$i]=${dm_lv_src[$i]}" # DEBUG 
	if [ "${typ_part[$i]}" = "83" ]
	then
		if [ $(mount | awk -v var=${part_src[$i]} -v lv_device=${dm_lv_src[$i]} '$1 == var || $1==lv_device  { print $0 }' | wc -l) -eq 1 ]
		then
			typ_fs[$i]=$(mount | awk -v var=${part_src[$i]} -v lv_device=${dm_lv_src[$i]} '$1 == var || $1==lv_device { print $5 }')
			ptm_fs[$i]=$(mount | awk -v var=${part_src[$i]} -v lv_device=${dm_lv_src[$i]} '$1 == var || $1==lv_device { print $3 }')

		else
			TEMP_I=${i}
			message  -m SYSTEME_ALTERNE_W "ATTENTION: partition ${part_src[$i]} de type ${typ_part[$i]} non montee"
			message  -m SYSTEME_ALTERNE_I "Recherche du type et du point de montage du filesystem dans ${FIC_FSTAB}"
			i=${TEMP_I}
			FLAG_ERROR=1

			# on recherche le type de FS dans /etc/fstab par le nom de la partition
			if [ $(awk -v var=${part_src[$i]} '{ if ( $1 == var ) print $0 }' ${FIC_FSTAB} | wc -l) -eq 1 ]
			then
				typ_fs[$i]=$(awk -v var=${part_src[$i]} '{ if ( $1 == var ) print $3 }' ${FIC_FSTAB})
				ptm_fs[$i]=$(awk -v var=${part_src[$i]} '{ if ( $1 == var ) print $2 }' ${FIC_FSTAB})
				#echo "I=$i   part_src[$i]=${part_src[$i]}  typ_fs[$i]=${typ_fs[$i]}   ptm_fs[$i]=${ptm_fs[$i]}"
			else
				# on recherche le type de FS dans /etc/fstab par le LABEL de la partition
				if [ $(awk -v var=${label_part[$i]} '{ if ( $1 == "LABEL="var ) print $0 }' ${FIC_FSTAB} | wc -l) -eq 1 ]
				then
					typ_fs[$i]=$(awk -v var=${label_part[$i]} '{ if ( $1 == "LABEL="var ) print $3 }' ${FIC_FSTAB})
					ptm_fs[$i]=$(awk -v var=${label_part[$i]} '{ if ( $1 == "LABEL="var ) print $2 }' ${FIC_FSTAB})
					#echo "I=$i   part_src[$i]=${part_src[$i]}  typ_fs[$i]=${typ_fs[$i]}   ptm_fs[$i]=${ptm_fs[$i]}"
				else
					TEMP_I=${i}
					message  -m SYSTEME_ALTERNE_W "Type et point de montage du FS indeterminable pour la partition ${part_src[$i]}"
					i=${TEMP_I}
					typ_fs[$i]=""
					ptm_fs[$i]=""
				fi
			fi
		fi
		if [ "${ptm_fs[$i]}" = '/' ]; then
			LV_ROOT="${part_src[$i]}"
		fi
	else
		typ_fs[$i]=""
		ptm_fs[$i]=""
	fi
done

if [ "${DEBUG}" = "1" ]
then
  i=0
  while [ ${i} -lt ${nb_part} ]
  do
    i=$(expr $i + 1)
    echo "type FS pour la partition(id=83) ${i} : ${typ_fs[$i]}"
  done
  echo "---------------------------------------------------"
  i=0
  while [ ${i} -lt ${nb_part} ]
  do
    i=$(expr $i + 1)
    echo "point_de_montage du FS pour la partition(id=83) ${i} : ${ptm_fs[$i]}"
  done
  echo "---------------------------------------------------"
fi

# ==================================================
# ================ Fin recupere_infos_systeme_source =======
#====================================================
}



# Verification des pre-requis
check_prerequis() {

	disk_clone=$1

		# Verification existence du disk clone
	$SFDISK -s ${disk_clone} >/dev/null
	if [ $? -ne 0 ]; then
		message  -m SYSTEME_ALTERNE_E "Le disque ${disk_clone} n'existe pas"
		terminer_ko
	fi

		# Identification du disk source en recherchant ou est localise la partition "/"
	device=$(df -P / | tail -1 | awk '{ print $1 }' | sed "s/\/dev\/mapper\/\([^-]*\)-\([^-]*\)$/\/dev\/\\1\\/\\2/")

		# Recherche du pv en cas de / sur lv
	df -P / | tail -1 | awk '{ print $1 }' | grep "/dev/mapper" >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		vgroot=$(df -P / | tail -1 | awk '{ print $1 }' | sed "s/\/dev\/mapper\/\([^-]*\)-\([^-]*\)$/\\1/" )
		device=$($PVS 2>/dev/null| grep "[[:space:]]${vgroot}[[:space:]]" | awk '{ print $1 }')
	fi

		# verif si device de la partition "/" est de la forme 'c0d0p1' sinon de la forme 'sda1' ou 'hda1'
		# Update du 20/02/2014 pour prise en charge du multipath du Boot on SAN
		#echo ${device} | grep -e "c[[:digit:]]\+d[[:digit:]]\+p[[:digit:]]\+|mpath.*p[[:digit:]]\+$" -q
		#echo ${device} | grep -E 'c[[:digit:]]\+d[[:digit:]]\+p[[:digit:]]\+|mpath.*p[[:digit:]]' -q
	echo ${device} | grep -E 'c[[:digit:]]+d[[:digit:]]+p[[:digit:]]+|mpath.*p[[:digit:]]+' -q
	if [ $? -eq 0 ]; then
		disk_source=$(echo ${device} | sed 's/p[[:digit:]]\+$//')
	else
		disk_source=$(echo ${device} | sed 's/[[:digit:]]\+$//')
	fi

	unset device

		# Verification disk clone n'est pas disk source
		# ---------------------------------------------
	if [ "${disk_clone}" = "${disk_source}" ]; then
		message -m SYSTEME_ALTERNE_E "Le disque passe en argument correspond au disque source"
		terminer_ko
	fi

		# Verification 1 seul PV sur le disque source
		# ---------------------------------------------
	#pvnum=$(pvs -o pv_name 2>/dev/null|awk -v DISK_SOURCE=$disk_source '$1~DISK_SOURCE { print $1 }' | wc -l )
		# Correction 2.1.4
	pvnum=$(pvs -o pv_name 2>/dev/null|awk -v DISK_SOURCE=$disk_source '$1~DISK_SOURCE"[0-9]*$" { print $1 }' | wc -l )

	if [ $pvnum -gt 1 ]; then
		message   -m SYSTEME_ALTERNE_E  "$pvnum PV LVM  sur le disque source"
		message   -m SYSTEME_ALTERNE_E  "le disque source n'est pas correct"
		terminer_ko
	fi


		# Verification existence fichiers
		# -------------------------------
	if [ $OSLEVELM -lt 7 ]; then
			# EL < 7 (grub 0.9x)
		V_FIC_DEVMAP=$FIC_DEVMAP
		V_FIC_CONFGRUB=$FIC_CONFGRUB
	else
			# EL >= 7 (grub2)
		V_FIC_DEVMAP=$FIC_DEVMAP2
		V_FIC_CONFGRUB=$FIC_CONFGRUB2
	fi

	for file in "${V_FIC_DEVMAP}" "${V_FIC_CONFGRUB}" "${FIC_FSTAB}"
	do
		if [ ! -s "${file}" ]; then
			message  -m SYSTEME_ALTERNE_E "Fichier ${file} absent ou vide"
			terminer_ko
		fi
	done

		# Recherche du nom 'bios' utilise par GRUB du disk clone et du disk source
		# ------------------------------------------------------------------------
	bios_disk_clone=$(grep ${disk_clone} ${V_FIC_DEVMAP} | grep -v "^#" | awk '{ print $1 }'| sed 's/[()]//g')
	if [ -z "${bios_disk_clone}" ]; then
		message  -m SYSTEME_ALTERNE_E "Nom 'bios' du Disque_Clone ${disk_clone} non trouve dans ${V_FIC_DEVMAP}"
		message  -m SYSTEME_ALTERNE_E "Ajouter le manuellement dans ${V_FIC_DEVMAP} si necessaire"
		terminer_ko
	fi

	bios_disk_source=$(grep ${disk_source} ${V_FIC_DEVMAP} | grep -v "^#" | awk '{ print $1 }'| sed 's/[()]//g')
	if [ -z "${bios_disk_source}" ]; then
		message  -m SYSTEME_ALTERNE_E "Nom 'bios' du Disque_Source ${disk_source} non trouve dans ${V_FIC_DEVMAP}"
		message  -m SYSTEME_ALTERNE_E "Ajouter le manuellement dans ${V_FIC_DEVMAP} si necessaire"
		terminer_ko
	fi

	#bios_disk_source=hd0
	#bios_disk_clone=hd1

	message  -m SYSTEME_ALTERNE_I "Disque_Clone  : ${disk_clone} (nom 'bios' pour GRUB : ${bios_disk_clone})"
	message  -m SYSTEME_ALTERNE_I "Disque_Source : ${disk_source} (nom 'bios' pour GRUB : ${bios_disk_source})"


	#exit 0

	# FQT verification a supprimer pour permettre le clonage du disque alterne vers le source.
	# Utilisee pour savoir si c'est un clone du disque source ou du disque alterne.
	# Clonage du disque source: CLONE_SOURCE=0 sinon CLONE_SOURCE=""
	# Verification pas de "_alt" a la fin du LABEL des partitions type 83 sur le disk source
	# car il pourrait s'agir deja d'un systeme alterne et dans ce cas sortie en erreur
	# --------------------------------------------------------------------------------------
	i=0
	# FQT
	CLONE_SOURCE=0
	for part in $($SFDISK -l ${disk_source} 2>/dev/null| grep "^${disk_source}" | cut -d" " -f1)
	do
		i=$(expr $i + 1)
		if [ "$($SFDISK --print-id ${disk_source} ${i})" = "83" ]
		then
			if [ $(${LABEL_CMD} ${part} 2>/dev/null | grep "_alt$" | wc -l) -ne 0 ]
			then
				# FQT
				#message -m SYSTEME_ALTERNE_E "Presence de \"_alt\" a la fin du LABEL de la partition ${part}"
				#message -m SYSTEME_ALTERNE_E "il doit deja s'agir du systeme alterne"
				#terminer_ko
				CLONE_SOURCE=1
			fi
		fi
	done

		# Nouvelle methode de detection de sys alt
	old_IFS=$IFS     # sauvegarde du separateur de champ
	IFS=$'\n'     # nouveau separateur de champ, le caractere de fin de ligne

	for line in $(mount)
	do
		lv=$(echo $line |awk '{print $1}')
		mont=$(echo $line |awk '{print $3}')

		if [ $mont == '/' ]; then

			if [ $(echo $lv | grep "_alt$" | wc -l) -ne 0 ]; then
				CLONE_SOURCE=1
				break
			else
				CLONE_SOURCE=0
			fi
		fi
	done
	IFS=$old_IFS




# Verification presence d'une partition contenant un FS "/boot" sur le disk source
# et que celle-ci est montee sinon sortie en erreur
# ************************************************************************************** 
# SI IL N'Y A PAS DE PARTITION "/boot" SUR VOTRE SYSTEME ("/boot" DEVANT ETRE DANS CE
# CAS UN REPERTOIRE SUR LA PARTITION "/" SUPPRIMER LE CONTROLE CI-DESSOUS)
# SI LA PARTITION "/boot" EST LOCALISEE SUR UN AUTRE DISQUE ALORS CE SCRIPT NE DOIT PAS
# ETRE UTILISE CAR LE SYSTEME ALTERNE GENERE SERA INCOMPLET
# ************************************************************************************** 
# --------------------------------------------------------------------------------------
	flag_boot=0
	for part in $($SFDISK -l ${disk_source} 2>/dev/null | grep "^${disk_source}" | cut -d" " -f1)
	do
		if [ "$(df ${part} 2>/dev/null | grep ${part} | awk '{ print $NF }')" = "/boot" ]
		then
			flag_boot=1
		fi 
	done

	if [ ${flag_boot} -ne 1 ]; then
		message  -m SYSTEME_ALTERNE_E "Il faut une partition \"/\" et une partition \"/boot\" sur le disque source ${disk_source}"
		message  -m SYSTEME_ALTERNE_E "et qu'elles soient montees pour le bon fonctionnement de cette procedure"
		terminer_ko
	fi

	unset part flag_boot
}



update_clone_prompt () {
bashrc_clone="${RACINE_SYS_ALT}${FIC_BASHRC}"





old_IFS=$IFS     # sauvegarde du séparateur de champ  
IFS=$'\n'     # nouveau séparateur de champ, le caractère fin de ligne  

mountfs=`mount`
for line in $(mount)
do
	lv=$(echo $line |awk '{print $1}')
	mont=$(echo $line |awk '{print $3}')

	if [ $mont == '/' ]; then

		if [ $(echo $lv | grep "_alt$" | wc -l) -ne 0 ]
		then
        	CLONE_SOURCE=1
			break
		else
        	CLONE_SOURCE=0
	fi
fi

done
IFS=$old_IFS




if [ "$CLONE_SOURCE" -eq "1" ]; then
	# c est le CLONE
	sed 's/ PS1=\"(sys_alt)/ PS1=\"/' ${bashrc_clone} >${bashrc_clone}.tmp
else
	# c est pas le clone
	sed 's/ PS1=\"/ PS1=\"(sys_alt)/' ${bashrc_clone} >${bashrc_clone}.tmp
fi
mv -f ${bashrc_clone}.tmp ${bashrc_clone}
}


update_clone_prompt_orig () {
# ==============================================================================
message  -m SYSTEME_ALTERNE_I "MODIFICATION DU PROMPT PS1 SUR LE SYSTEME ALTERNE"
# ==============================================================================
# ----------------------------------------------------------------------------------------
# Normalement, "~<user>/.bash_profile" appelle "~<user>/.bashrc" qui appelle "/etc/bashrc"
# ----------------------------------------------------------------------------------------


# Definition nom complet du fichier "/etc/bashrc" sur le systeme alterne
# (il est donc localise sous ${RACINE_SYS_ALT})
# ----------------------------------------------------------------------
bashrc_clone="${RACINE_SYS_ALT}${FIC_BASHRC}"

message -m SYSTEME_ALTERNE_I "Nom complet du fichier modifie : ${bashrc_clone}"

if [ ! -s "${bashrc_clone}" ]
then
  message -m SYSTEME_ALTERNE_W "ATTENTION: Fichier ${bashrc_clone} absent ou vide"
  message -m SYSTEME_ALTERNE_W "Pas de mise a jour de PS1 sur le systeme alterne"
  FLAG_ERROR=1
else
  # cette procedure s'attend a trouver une seule fois, la definition de PS1 dans /etc/bashrc
  # comme c'est le cas lors d'une installation d'un serveur LINUX par souche EDFGDF.
  # (La chaine de caracteres recherchee est PS1=").
  # En cas d'evolution, il faudra adapter cette procedure.
  #
  # Si la chaine est trouvee, la procedure ajoute "(sys_alt)" au debut du prompt PS1
  #
  # MODIF KSH93
  if [ $(grep -v "^[[:space:]]*#" ${bashrc_clone} | grep "PS1=\"" | wc -l) -eq 1 ]
  then
    # FQT
    #if [ $(grep -v "^#" ${bashrc_clone} | grep "PS1=\"(sys_alt)" | wc -l) -eq 1 ]
    #then
    #  message -m SYSTEME_ALTERNE_W "Bizarre! la chaine de caracteres \"(sys_alt)\" est deja presente dans le prompt PS1"
    #  message -m SYSTEME_ALTERNE_W "Verifier la definition de PS1 sur le systeme source"
    #  FLAG_ERROR=1
    #else
    # MODIF KSH93	
	
        nb_occ=$(egrep -v "^[[:space:]]*#" ${bashrc_clone} | grep "PS1=\"(sys_alt)" | wc -l)
        #nb_occ=$(awk '$1!~/^#/ && $0!~/.*#.*PS1=\"/ && $0~/[[:space:]]PS1=\"/ ' ${bashrc_clone} |wc -l)
    if [[ "$CLONE_SOURCE" && $nb_occ -eq 0 ]] 
	#|| [[ ! "$CLONE_SOURCE" && $nb_occ -eq 1 ]]
    then
      message -m SYSTEME_ALTERNE_W "Verifier la definition de PS1 sur le systeme source"
      FLAG_ERROR=1
    else
      # FQT
      #sed 's/PS1=\"/PS1=\"(sys_alt)/' ${bashrc_clone} >${bashrc_clone}.tmp
      #cr1=$?
      if [ "$CLONE_SOURCE" ]
      then
                #sed 's/\(.*[^#].*&& PS1="\)\([.*$\)/\1#(sys_alt)\2' ${bashrc_clone} >${bashrc_clone}.tmp
        #sed 's/\sPS1=\"/\sPS1=\"(sys_alt)/' ${bashrc_clone} >${bashrc_clone}.tmp
                sed 's/ PS1=\"/ PS1=\"(sys_alt)/' ${bashrc_clone} >${bashrc_clone}.tmp
        cr1=$?
      else
        sed 's/ PS1=\"(sys_alt)/ PS1=\"/' ${bashrc_clone} >${bashrc_clone}.tmp
        cr1=$?
      fi

      if [ "${DEBUG}" = "1" ]
      then
        echo "---------------------------------------------------"
        echo "Contenu du fichier ${bashrc_clone} avant modification :"
        cat ${bashrc_clone}
      fi

      mv -f ${bashrc_clone}.tmp ${bashrc_clone}
      cr2=$?

      if [ "${DEBUG}" = "1" ]
      then
        echo "---------------------------------------------------"
        echo "Contenu du fichier ${bashrc_clone} apres modification :"
        cat ${bashrc_clone}
        echo "---------------------------------------------------"
      fi

      if [ ${cr1} -ne 0 -o ${cr2} -ne 0 ]
      then
        message -m SYSTEME_ALTERNE_E "Erreur lors de la modification de PS1 dans ${bashrc_clone}"
        FLAG_ERROR=1
      fi

    fi
  else
    message -m SYSTEME_ALTERNE_W "ATTENTION: la definition de PS1 n'a pas ete trouve (uniquement une fois)"
    message -m SYSTEME_ALTERNE_W "Pas de mise a jour de PS1 sur le systeme alterne"
    FLAG_ERROR=1
  fi
fi

# remise en place des droits sur le fichier, par precaution
# ---------------------------------------------------------
chmod 644 ${bashrc_clone}

unset bashrc_clone cr1 cr2

}

# Fonction terminer_ok
terminer_ok() {

  if [ ${FLAG_ERROR} = "1" ]
  then
    message -m SYSTEME_ALTERNE_I "*** FIN OK AVEC DES ERREURS"
        \rm /var/run/${PROG}.pid >/dev/null 2>&1
    exit 1
  fi
  message -m SYSTEME_ALTERNE_I "*** FIN OK"
  \rm /var/run/${PROG}.pid >/dev/null 2>&1
  exit 0
}

# Fonction terminer_ko
terminer_ko() {
        message -m SYSTEME_ALTERNE_E "*** FIN ECHEC"
        \rm /var/run/${PROG}.pid >/dev/null 2>&1
        exit 2
}




#---------------
# # Initialisation des variables et environnement
#---------------
#set -x
PROG=$(basename $0)
# La variable LANG est imposee pour eviter toute fluctuation dans les resultats de commandes
export LANG=C
	# Correction 2.1.4
export LC_ALL=C
# Definition repertoires et enrichissement de FPATH
export SYSALTPATH='/outillage/PraSys/bin'
export DOMAINE="PraSys"
export R_ROOTDIR="/outillage"
export FPATH="${R_ROOTDIR}/lib:${R_ROOTDIR}/${DOMAINE}/lib"
export PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin"
# Definition fichier catalogue des messages et fichier de log
export LIST_CATALOG="${R_ROOTDIR}/${DOMAINE}/messages/systeme_alterne.cat"
export MSGLOG="/var/${DOMAINE}/log/${PROG%%.*}.log"
# Chargement fichier d'environnement global
. /outillage/glob_par/config_systeme.env
####. config_systeme.env
# Flag pour le mode debug
DEBUG=0
# Flag pour indiquer en fin de procedure si des erreurs ont ete rencontre
FLAG_ERROR=0
# Point de montage 'racine' pour le systeme alterne
RACINE_SYS_ALT='/sys_alt'
# Fichier map des devices pour GRUB
FIC_DEVMAP='/boot/grub/device.map'
# Fichier de configuration GRUB
FIC_CONFGRUB='/boot/grub/grub.conf'

# Fichier de configuration GRUB2
FIC_CONFGRUB2=/boot/grub2/grub.cfg
# Fichier map des devices pour GRUB2
FIC_DEVMAP2=/boot/grub2/device.map

# Fichier "fstab" (table des FS)
FIC_FSTAB='/etc/fstab'
# Fichier "bashrc" (pour la modification du prompt PS1)
FIC_BASHRC='/etc/bashrc'
# Commandes utilisees avec les options
#PVS='/sbin/pvs --noheadings'
PVS='pvs --noheadings'
#VGS='/sbin/vgs --noheadings'
VGS='vgs --noheadings'
#LVS='/sbin/lvs --noheadings'
LVS='lvs --noheadings'
LVCREATE='lvcreate  --zero n '
VGCREATE='vgcreate'
PVREMOVE='pvremove -f '
VGREMOVE='vgremove -f '
LVREMOVE='lvremove -f '
VGCHANGE='vgchange'

#LVCREATE='/sbin/lvcreate'
#VGCREATE='/sbin/vgcreate'
#PVREMOVE='/sbin/pvremove -f '
#VGREMOVE='/sbin/vgremove -f '
#LVREMOVE='/sbin/lvremove -f '
SFDISK='/sbin/sfdisk'

# Version Majeur de l'OS
#OSLEVELM=$(awk '{print $1}' /etc/conf_machine/version_ref | sed -r 's/\.[0-9]+\.[0-9]+$//g')
OSLEVELM=$(sed "s/^[^0-9]*\([0-9]*\)\.[0-9]*.*/\1/g" /etc/conf_machine/version_ref)

typeset -i TEMP_I
typeset LV_ROOT
typeset LV_SWAP

	# A partir de EL 7 ont passe de ext2/3/4 a xfs
if [ $OSLEVELM -lt 7 ]; then
	LABEL_CMD=e2label
else
	LABEL_CMD='xfs_admin -l'
fi


# =======================CORPS PRINCIPAL DU SCRIPT=============================
#
# =============================================================================
message  -m SYSTEME_ALTERNE_I "*** DEBUT PROCEDURE"
# ===================================================================
message  -m SYSTEME_ALTERNE_I "PREPARATION ET VERIFICATIONS INITIALES"
# ===================================================================

# Verification execution par root
# -------------------------------
if [ $(whoami) != root ]
then
        message  -m SYSTEME_ALTERNE_E "Ce script doit etre execute sous root."
        terminer_ko
fi

ARGS="$0 $*"
echo "ARGS=$ARGS"

# Verification que le script n'est pas deja en cours d'execution
# -------------------------------
if [ -f /var/run/${PROG}.pid ]
then
    message  -m SYSTEME_ALTERNE_E "process en cours d'execution ou supprimier le fichier /var/run/${PROG}.pid"
    terminer_ko
else
        echo $$ >/var/run/${PROG}.pid
fi

# Verification mode debug
if [ "$1" = "-d" ]
then
        DEBUG=1
        shift
fi

# Verification syntaxe
if [ $# -ne 1 ]
then
        message  -m SYSTEME_ALTERNE_E "Syntaxe incorrecte (usage: $0 [-d] <nom_complet_du_fichier_device_du_disque_clone>)"
        terminer_ko
fi

FS_a_sauvegarder='/ /boot /home /tmp /var'



check_prerequis $1
recupere_infos_systeme_source
remove_lvm_device_clonedisk
create_partition_table_clonedisk
format_partition_clonedisk
create_clone_mountpoint
create_clone_fstab
update_clone_grub
update_clone_prompt
#install_grub_clonedisk

if [ $OSLEVELM -lt 7 ]; then
	demontage_fs_clone
else
	demontage_fs_clone_el7
fi

terminer_ok
#
# vim:ts=4:sw=4

## Changelog
# 2.0 ,summer 2014,  version initial
# 2.0.1, 21/11/2014  , mise a jour pour EL 6.6  (cause lvcreate: question sur signature swap )
# 2.0.2  27/11/2014  , mise a jour , (l 567 , un message d erreur est un message d info )
# 2.0.3  10/01/2015  , mise a jour , correction LOG dans le script message
# 2.1.0  03/04/2015  , mise a jour pour EL 7
# 2.1.2  19/01/2017  , EL 7 : changements pour prendre en compte un changement dans le label des nouveaux noyaux
# 2.1.3  02/02/2017  , corrections pour EL 7 (problemes sur certaines machines physiques)
# 2.1.4  09/02/2017  , corrections : LC_ALL=C ; prise en compte uniquement des disques /dev/sdX suivi de chiffres au cas ou il y a plusieurs PV sur le disque source, changement OSLEVELM car si il n'y avait pas 3 champs de version ca ne fonctionnait pas (vu sur 6.4)
