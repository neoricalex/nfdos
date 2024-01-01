#!/bin/bash
# use case ./build.sh

#Variables
ARCH="amd64"
RELEASE="bionic"
STARTDIR=$(dirname "$0") 
UBUNTUDIR=${STARTDIR}/..
TMPDIR="${STARTDIR}/work"
WKDIR="${TMPDIR}/chroot"
BLDFL="${STARTDIR}/buildfiles"

function cleanup() {
    # clean up our temp folder
    sudo rm -rf ./work
    #sudo rm -rf ./buildfiles
}

#Functions for progress Spinner for long running commands
    function shutdown() {
        tput cnorm # reset cursor
    }
        trap shutdown EXIT

    function cursorBack() {
        echo -en "\033[$1D"
    }    
    function spinner() {
        # make sure we use non-unicode character type locale 
        # (that way it works for any locale as long as the font supports the characters)
        local LC_CTYPE=C

        local pid=$1 # Process Id of the previous running command

        case $(($RANDOM % 1)) in
        0)
            local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
            local charwidth=3
            ;;
        esac

        local i=0
        tput civis # cursor invisible
        while kill -0 $pid 2>/dev/null; do
            local i=$(((i + $charwidth) % ${#spin}))
            echo -n "   "
            printf "\e[1;33m%-6s\e[m" "${spin:$i:$charwidth}"
            echo -n ""

            cursorBack 7
            sleep .1
        done
        tput cnorm
        wait $pid # capture exit code
        return $?
    }

function buildfiles() {
    # create our working folders
    mkdir -p buildfiles

    cat << EOF > buildfiles/autologin.conf
    [Service]
    ExecStart=
    ExecStart=-/sbin/agetty --autologin ubuntu --noclear %I 38400 linux
EOF

    cat << EOF > buildfiles/grub.cfg
    search --set=root --file /ubuntu

    insmod all_video

    set default="0"
    set timeout="-1"

    menuentry "Start Ubuntu-Live" {
    linux /casper/vmlinuz boot=casper toram noprompt quiet splash ip=frommedia --
    initrd /casper/initrd.lz
    }

    menuentry "Reboot to configure legacy boot" {
    halt
    }
EOF

    cat << EOF > buildfiles/isolinux.cfg
    # Use the high-colour menu system.
    UI vesamenu.c32

    # Prompt the user. Set to '1' to automatically choose the default option. This
    # is really meant for files matched to MAC addresses.
    PROMPT 1

    # Set the boot menu to be 1024x768 with a nice background image. Be careful to
    # ensure that all your user's can see this resolution! Default is 640x480.
    MENU RESOLUTION 640 480

    # These do not need to be set. I set them here to show how you can customize or
    # localize your PXE server's dialogue.
    MENU TITLE    UBUNTU


    # Below, the hash (#) character is replaced with the countdown timer. The
    # '{,s}' allows for pluralizing a word and is used when the value is >= '2'.
    MENU AUTOBOOT Will boot the next device as configured in your BIOS in # second{,s}.
    MENU NOTABMSG Editing of this option is disabled.


    # The following options set the various colours used in the menu. All possible
    # options are specified except for F# help options. The colour is expressed as
    # two hex characters between '00' and 'ff' for alpha, red, green and blue
    # respectively (#AARRGGBB).
    # Format is: MENU COLOR <Item> <ANSI Seq.> <foreground> <background> <shadow type>
    menu color screen  	  37;40      #80000000 #00000000 std
    menu color border  	  30;44      #40ff0000 #00000000 std
    menu color title   	  1;36;44    #c0ffffff #00000000 std
    menu color unsel	      37;44      #90ffffff #00000000 std
    menu color hotkey	    1;37;44    #e0ffffff #00000000 std
    menu color sel  	      7;37;40    #e0ffffff #20ffffff all
    menu color hotsel	    1;7;37;40  #e0ffffff #20ff8000 all
    menu color disabled	  1;30;44    #60cccccc #00000000 std
    menu color scrollbar	  30;44      #40000000 #00000000 std
    menu color tabmsg	    31;40      #90ffffff #00000000 std
    menu color cmdmark	    1;36;40    #c000ffff #00000000 std
    menu color cmdline	    37;40      #c0ffffff #00000000 std
    menu color pwdborder	  30;47      #80ffffff #20ffffff std
    menu color pwdheader	  31;47      #80ffffff #20ffffff std
    menu color pwdentry	  30;47      #80ffffff #20ffffff std
    menu color timeout_msg	37;40      #80ffffff #00000000 std
    menu color timeout	    1;37;40    #c0ffffff #00000000 std
    menu color help 	      37;40      #c0ffffff #00000000 std
    menu color msg07	      37;40      #90ffffff #00000000 std

    ### Now define the menu options
    DEFAULT ubuntu
    LABEL ubuntu
    menu label ^Start Ubuntu
    kernel /casper/vmlinuz
    append boot=casper initrd=/casper/initrd.lz toram noprompt quiet ip=frommedia --
    LABEL memtest
    menu label ^Start Memtest
    kernel /install/memtest
    append -



    #prompt flag_val
    #
    # If flag_val is 0, display the "boot:" prompt
    # only if the Shift or Alt key is pressed,
    # or Caps Lock or Scroll lock is set (this is the default).
    # If  flag_val is 1, always display the "boot:" prompt.
    #  http://linux.die.net/man/1/syslinux   syslinux manpage
EOF

    cat << EOF > buildfiles/README.diskdefines
    #define DISKNAME  ubuntu
    #define TYPE  binary
    #define TYPEbinary  1
    #define ARCH  x64_86
    #define ARCHx64_86  1
    #define DISKNUM  1
    #define DISKNUM1  1
    #define TOTALNUM  0
    #define TOTALNUM0  1
EOF

    cat << EOF > buildfiles/setup.sh
    #!/bin/bash


    #function to install apps with a clean display
    function retryinstall
    {
    echo -e "[\033[33m-\e[0m] Retrying..."
    DEBIAN_FRONTEND=noninteractive apt-get --fix-broken install -yq -o  Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >/dev/null 2>/dev/nul
    DEBIAN_FRONTEND=noninteractive apt-get install --fix-missing -yq -o  Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" >/dev/null 2>/dev/nul
    DEBIAN_FRONTEND=noninteractive apt-get install -yq -o  Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $1 >/dev/null 2>/dev/null && echo -e "[\033[32m*\e[0m]OK" || echo -e "[\033[31m-\e[0m] FAILED"
    }
    function install
    {
    echo -n "installing:$1 "
    DEBIAN_FRONTEND=noninteractive apt-get install -yq -o  Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" $1 >/dev/null 2>/dev/null && echo -e "[\033[32m*\e[0m]OK" || retryinstall $1
    }

    #function to install with no dependencies
    function installnodep
    {
    echo -n "installing:$1 "
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -yq -o  Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"  $1 >/dev/null 2>/dev/null && echo -e "[\033[32m*\e[0m]OK" || retryinstall $1
    }

    function exitcheck ()
    {
        #Function to check exit codes
        if [[ $1 -ne 0 ]]; then
        echo -e "[\033[31m-\e[0m] FAILED"
        echo -e "[\033[31m-\e[0m] Exiting now"
        exit 1
        else
            echo -e "[\033[32m*\e[0m]OK"
        fi 
    }


    #Updates apt and include i386 support (Cannot capture APT Exit code... due to 2 exit code (APT Unstable on CLI Warning...))
    echo -n "adding:32 bit support "
    dpkg --add-architecture i386 1>/dev/null
    exitcheck "$?"
    echo -n "updating:Ubuntu package lists "
    apt update >/dev/null 2>&1 
    exitcheck "$?"
    install software-properties-common
    echo -n "adding:Software Properties Common PPA "
    add-apt-repository --yes ppa:graphics-drivers/ppa >/dev/null 2>&1
    exitcheck "$?"
    echo -n "updating:APT config "
    apt update >/dev/null 2>&1
    exitcheck "$?"

    #Install Live environment
    install ubuntu-standard 
    install casper 
    install lupin-casper
    install discover 
    install laptop-detect 
    install os-prober
    install linux-firmware
    install linux-generic 
    install xserver-xorg 
    install xserver-xorg-video-all 
    install xinit 
    install gdm3

    # Install nvidia drivers if required. Only one NVIDIA driver can be installed at a time, so comment out change to NVIDIA390 or 340 for older cards

    installnodep nvidia-driver-410 
    installnodep libnvidia-gl-410
    installnodep nvidia-utils-410 
    installnodep xserver-xorg-video-nvidia-410 
    installnodep libnvidia-cfg1-410 libnvidia-ifr1-410 
    installnodep libnvidia-decode-410 
    installnodep libnvidia-encode-410

    #Customise Ubuntu and bootscreen
    sudo chmod -x /etc/update-motd.d/*
    sudo chmod +x /etc/update-motd.d/01-custom


    #Cleanup old Kernel Files
    current_kernel="$(uname -r | sed 's/\(.*\)-\([^0-9]\+\)/\1/')"
    current_ver=${current_kernel/%-generic}

    echo "Running kernel version is: ${current_kernel}"
    # uname -a

    function xpkg_list() {
    dpkg -l 'linux-*' | sed '/^ii/!d;/linux-libc-dev/d;/'${current_ver}'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d'
    }

    echo "The following (unused) KERNEL packages will be removed:"
    xpkg_list

    xpkg_list | xargs sudo apt-get -y purge 1>/dev/null && echo -e "[\033[32m*\e[0m]Removed"
EOF

    cat << EOF > buildfiles/sources.list
    deb http://au.archive.ubuntu.com/ubuntu/ bionic main release multiverse universe
    deb http://au.archive.ubuntu.com/ubuntu/ bionic-security main release multiverse universe
    deb http://au.archive.ubuntu.com/ubuntu/ bionic-backports release multiverse universe
    deb http://au.archive.ubuntu.com/ubuntu/ bionic-updates main release multiverse universe
EOF


}

function instalar-requerimentos() {
    sudo apt install -y \
        debootstrap
}

function buildubuntu() {
    # create our working folders
    mkdir work
    TMPDIR=work
    #End Temp
    chmod 755 "${TMPDIR}"
   
    
    #Downloads and creates custom ubuntu distro
    echo -n "Downloading and installing ubuntu base chroot, this may take some time"
    debootstrap --arch=$ARCH $RELEASE $TMPDIR/chroot 1>/dev/null & pid=$!
    spinner $pid
    if [[ $? -ne 0 ]]; then
        echo -e "[\033[31m-\e[0m] FAILED"
        echo "Exiting now"
        exit 1
    else
        echo -e "[\033[32m*\e[0m]OK"
    fi 
  
    
    #Copies System Files so you can get internet within chroot sed is used for futureproofing
    cp  /etc/hosts ${WKDIR}/etc/hosts
    cp  -r /etc/resolvconf/* ${WKDIR}/etc/resolvconf/
    sudo cp  /etc/resolv.conf ${WKDIR}/etc/resolv.conf
    
    #Copies binaries and scripts into the chroot environment
    cp ${UBUNTUDIR}/ubuntu-live ${WKDIR}/usr/bin/ubuntu-live
    chmod 755 ${WKDIR}/usr/bin/ubuntu-live
    cp ${BLDFL}/setup.sh ${WKDIR}/tmp/
    chmod 775 ${WKDIR}/tmp/setup.sh
 
              
    # Set hostname
    echo "ubuntu-live-live" | sudo tee ${WKDIR}/etc/hostname 
    echo "127.0.0.1 ubuntu-live-live" | sudo tee ${WKDIR}/etc/hosts
    sleep 5
}

function buildenv() {
    #Chroot into build environment (Output cannot be suppressed)
    sudo chroot ${WKDIR} << "EOT"
    mount none -t proc /proc
    mount none -t sysfs /sys
    mount none -t devpts /dev/pts
    export HOME=/root
    export LC_ALL=C

    #Run setup script

    /tmp/setup.sh

    #Cleanup chroot environment and remove desktop
    apt-get autoremove
    apt-get clean
    rm -rf /tmp/*
    rm /etc/resolv.conf

    umount /proc
    umount /sys
    umount /dev
    #Sometimes the above umount is not working
    umount -lf /proc
    umount -lf /sys
    umount -lf /dev

    #exit the chroot environment
    exit
    #!!!!EOT CANNOT BE INDENTED!!!!
EOT
    
    #Ensure Dev/pts is unmounted
    
    umount ${WKDIR}/dev/pts
}

function mkboot() {
       
    #Sets Autologin
    #autologin.conf is a script to enable auto login on tty1 on boot
    sudo mkdir -pv ${WKDIR}/etc/systemd/system/getty@tty1.service.d
    sudo cp ${BLDFL}/autologin.conf ${WKDIR}/etc/systemd/system/getty@tty1.service.d/
   
}

function mkiso() {
    
    #Attempts to create new ISO Image
    mkdir -p ${TMPDIR}/image/{casper,isolinux,install}
    sudo cp ${WKDIR}/boot/vmlinuz-* ${TMPDIR}/image/casper/vmlinuz
    sudo cp ${WKDIR}/boot/initrd.img* ${TMPDIR}/image/casper/initrd.lz
    cp ${BLDFL}/grub.cfg ${TMPDIR}/image/isolinux/grub.cfg


    #Compressess the Source Ubuntu Chroot into the image/boot file
    echo -n "Compressing chroot filesystem: "
    sudo mksquashfs ${TMPDIR}/chroot ${TMPDIR}/image/casper/filesystem.squashfs -e ${WKDIR}/boot 1>/dev/null & pid=$!
    spinner $pid
    if [[ $? -ne 0 ]]; then
        echo -e "[\033[31m-\e[0m] FAILED"
        echo "Exiting now"
        exit 1
    else
        echo -e "[\033[32m*\e[0m]OK"
    fi 

    # Creates ISO and image directories
    mkdir -p ${TMPDIR}/image/{casper,isolinux,install}
    sudo cp ${WKDIR}/boot/vmlinuz-* ${TMPDIR}/image/casper/vmlinuz
    sudo cp ${WKDIR}/boot/initrd.img* ${TMPDIR}/image/casper/initrd.lz
    cp /usr/lib/ISOLINUX/isolinux.bin ${TMPDIR}/image/isolinux
    cp /usr/lib/syslinux/modules/bios/* ${TMPDIR}/image/isolinux
    cp ${BLDFL}/isolinux.cfg ${TMPDIR}/image/isolinux/isolinux.cfg

    # Attempts to create UEFI Image
    grub-mkstandalone \
   --format=x86_64-efi \
   --output=${TMPDIR}/image/isolinux/bootx64.efi \
   --locales="" \
   --fonts="" \
   "boot/grub/grub.cfg=${TMPDIR}/image/isolinux/grub.cfg"
       
    dd if=/dev/zero of=${TMPDIR}/image/isolinux/efiboot.img bs=1M count=10 && \
    sudo mkfs.vfat ${TMPDIR}/image/isolinux/efiboot.img && \
    mmd -i ${TMPDIR}/image/isolinux/efiboot.img efi efi/boot && \
    mcopy -i ${TMPDIR}/image/isolinux/efiboot.img ${TMPDIR}/image/isolinux/bootx64.efi ::efi/boot/

    #Copies the required files for future USB Builds if required and builds the ISO Image
    cp ${BLDFL}/README.diskdefines ${TMPDIR}/image/
    touch ${TMPDIR}/image/ubuntu
    mkdir ${TMPDIR}/image/.disk >/dev/null 2>&1
    touch ${TMPDIR}/image/.disk/base_installable
    echo "full_cd/single" > ${TMPDIR}/image/.disk/cd_type
    echo "ubuntu-live V2.0" > ${TMPDIR}/image/.disk/info
    echo "See Objective Build Documentation for Release Notes" > ${TMPDIR}/image/isolinux/release_notes_url
    
    #Makes the Source ISO File
    cd ${TMPDIR}/image/
    sudo xorriso \
    --stdio_sync on \
    -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -c isolinux/boot.cat -b isolinux/isolinux.bin \
    -volid "ubuntu-liveV2.0" \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --eltorito-catalog boot/grub/boot.cat \
    --grub2-boot-info \
    --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
    -eltorito-alt-boot \
    -e EFI/efiboot.img \
    -no-emul-boot \
    -append_partition 2 0xef isolinux/efiboot.img \
    -isohybrid-gpt-basdat \
    -output "../../../ubuntu-liveV2.0.iso" \
    -graft-points \
      "." \
      /boot/grub/bios.img=isolinux/bios.img \
      /EFI/efiboot.img=isolinux/efiboot.img 

    # Print Completion message
    echo -e "[\033[32mubuntu-live Build Complete\e[0m] "
 
}

main() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run with sudo" 
        exit 1
    fi

    if [ -f /var/run/reboot-required ]; then
        echo 'reboot required Please reboot prior to proceeding' && exit 0
        end
    else
	cleanup
    instalar-requerimentos
    #buildfiles
    buildubuntu
    buildenv
    mkboot
    mkiso
	cleanup	
    fi
}

main
