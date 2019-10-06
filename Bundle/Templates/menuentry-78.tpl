menuentry 'Red Hat Enterprise Linux Server RELEASEVERSION (KERNELVERSION BOOTALT)' --class red --class gnu-linux --class gnu --class os --unrestricted $menuentry_id_option 'gnulinux-KERNELVERSION-advanced-ROOTALTBLKID' {
        load_video
        set gfxpayload=keep
        insmod gzio
        insmod part_msdos
        insmod ext2
        set root='hd1,msdos1'
        if [ x$feature_platform_search_hint = xy ]; then
          search --no-floppy --fs-uuid --set=root --hint-bios=hd1,msdos1 --hint-efi=hd1,msdos1 --hint-baremetal=ahci1,msdos1 --hint='hd1,msdos1'  BOOTALTBLKID
        else
          search --no-floppy --fs-uuid --set=root BOOTALTBLKID
        fi
        linux16 /vmlinuz-KERNELVERSION root=ROOTALTFILESYSTEM ro transparent_hugepage=never ipv6.disable=1 scsi_mod.max_luns=65535 scsi_mod.max_report_luns=65535 rd_NO_PLYMOUTH mce=dont_log_ce crashkernel=auto rd.lvm.lv=ROOTALTVG/ROOTALTLV biosdevname=0 rd.shell=0 
        initrd16 /initramfs-KERNELVERSION.BOOTALT.img
}

