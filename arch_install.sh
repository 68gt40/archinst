#!/bin/bash

#	needs : add support for a swap dev


# This script will set up an Arch installation with a 100 MB /boot partition
# and an encrypted LVM partition with swap and / inside.  It also installs
# and configures systemd as the init system (removing sysvinit).
#
# You should read through this script before running it in case you want to
# make any modifications, in particular, the variables just below, and the
# following functions:
#
#    partition_drive - Customize to change partition sizes (/boot vs LVM)
#    setup_lvm - Customize for partitions inside LVM
#    install_packages - Customize packages installed in base system
#                       (desktop environment, etc.)
#    set_netcfg - Preload netcfg profiles

## CONFIGURE THESE VARIABLES

# Drive to install to.
DRIVE='/dev/sda'

# Hostname of the installed machine.
HOSTNAME='vbtest'

# Root password (leave blank to be prompted).
ROOT_PASSWORD='dt'

# Main user to create (by default, added to wheel group, and others).
USER_NAME='dtx'

# The main user's password (leave blank to be prompted).
USER_PASSWORD='dt'

# System timezone.
TIMEZONE='America/Chicago'

# Have /tmp on a tmpfs or not.  Leave blank to disable.
# Only leave this blank on systems with very little RAM.
TMP_ON_TMPFS='TRUE'

KEYMAP='us'

# Choose your video driver
# For Intel
VIDEO_DRIVER="i915"
# For nVidia
#VIDEO_DRIVER="nouveau"
# For ATI
#VIDEO_DRIVER="radeon"
# For generic stuff
VIDEO_DRIVER="vesa"

# Wireless device, leave blank to not use wireless and use DHCP instead.
WIRELESS_DEVICE=""
# For tc4200's
#WIRELESS_DEVICE="eth1"

setup() {

    pacman -S syslinux
    
    local boot_dev="$DRIVE"1
    local root_dev="$DRIVE"2

    echo 'Creating partitions'
    partition_drive "$DRIVE"

    echo 'Setting up filesystems'
    setup_filesystems

    echo 'Formatting filesystems'
    format_filesystems "$boot_dev"

    echo 'Mounting filesystems'
    mount_filesystems "$boot_dev"
   
    echo 'Build initial mirrorlist'
    echo 'Server = http://mirrors.kernel.org/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist
  
    echo 'Allow pacstrap for work its magic, before our chroot phase'
    pacstrap /mnt base linux-lts linux-firmware
       
    echo 'Chrooting into installed system to continue setup...'
    cp $0 /mnt/setup.sh
    arch-chroot /mnt ./setup.sh chroot

    if [ -f /mnt/setup.sh ]
    then
        echo 'ERROR: Something failed inside the chroot, not unmounting filesystems so you can investigate.'
        echo 'Make sure you unmount everything before you try to run this script again.'
    else
        echo 'Unmounting filesystems'
        unmount_filesystems
        echo 'Done! Reboot system.'
    fi
}

configure() {
    local boot_dev="$DRIVE"1
    local root_dev="$DRIVE"2  
    #lmv local lvm_dev="$DRIVE"2

    echo 'Installing additional packages'
    install_packages

    echo 'Clearing package tarballs'
    clean_packages

    echo 'Updating pkgfile database'
    update_pkgfile

    echo 'Setting hostname'
    set_hostname "$HOSTNAME"

    echo 'Setting timezone'
    set_timezone "$TIMEZONE"

    echo 'Setting locale'
    set_locale

    echo 'Setting console keymap'
    set_keymap

    echo 'Setting hosts file'
    set_hosts "$HOSTNAME"

    echo 'Setting fstab'
    set_fstab "$TMP_ON_TMPFS" "$boot_dev"

    echo 'Setting initial modules to load'
    set_modules_load

    echo 'Configuring initial ramdisk'
    set_initcpio

    echo 'Setting initial daemons'
    set_daemons "$TMP_ON_TMPFS"

    echo 'Configuring bootloader'
    set_syslinux "$root_dev"

    echo 'Configuring sudo'
    set_sudoers

    if [ -z "$ROOT_PASSWORD" ]
    then
        echo 'Enter the root password:'
        stty -echo
        read ROOT_PASSWORD
        stty echo
    fi
    echo 'Setting root password'
    set_root_password "$ROOT_PASSWORD"

    if [ -z "$USER_PASSWORD" ]
    then
        echo "Enter the password for user $USER_NAME"
        stty -echo
        read USER_PASSWORD
        stty echo
    fi
    echo 'Creating initial user'
    create_user "$USER_NAME" "$USER_PASSWORD"

    echo 'Building locate database'
    update_locate

    rm /setup.sh
}

partition_drive() {
    local dev="$1"; shift

    # 100 MB /boot partition, everything else under LVM
    parted -s "$dev" \
        mklabel msdos \
        mkpart primary ext2 1 100m \
        mkpart primary ext2 100m 100% \
        set 1 boot on \
        set 2 root on
}

format_filesystems() {
    local boot_dev="$1"; shift

    mkfs.ext2 -L boot "$boot_dev"1
    mkfs.ext4 -L root "$boot_dev"2
    #	mkswap "$boot_dev"2
}

mount_filesystems() {
    local boot_dev="$1"; shift

    mount /dev/root /mnt
    mkdir /mnt/boot
    mount "$boot_dev" /mnt/boot
    # swapon /dev/swap
}

unmount_filesystems() {
    umount /mnt/boot
    umount /mnt
    # swapoff /dev/vg00/swap
    vgchange -an
}

install_packages() {
    local packages=''

    # General utilities/libraries
    packages+=' vim alacritty alsa-utils aspell-en cpupower mlocate net-tools ntp openssh p7zip pkgfile powertop rfkill rsync sudo unzip wget zip systemd-sysvcompat '

    # Development packages
    packages+=' make gcc perl git '

    # Netcfg
    if [ -n "$WIRELESS_DEVICE" ]
    then
        packages+=' ifplugd dialog wireless_tools '
    fi

    # Java stuff
    #packages+=' icedtea-web-java7 jdk7-openjdk jre7-openjdk'

    # Libreoffice
    #packages+=' libreoffice-calc libreoffice-en-US libreoffice-gnome libreoffice-impress libreoffice-writer hunspell-en hyphen-en mythes-en'

    # Misc programs
    packages+=' xscreensaver gparted dosfstools ntfsprogs'

    # Xserver
    #packages+=' xorg-apps xorg-server xorg-xinit xterm'

    # Slim login manager
    #packages+=' slim archlinux-themes-slim'

    # Fonts
    #packages+=' ttf-dejavu ttf-liberation'

    # On Intel processors
    packages+=' intel-ucode'

    # For laptops
    #packages+=' xf86-input-synaptics'

    # Extra packages for tc4200 tablet
    #packages+=' ipw2200-fw xf86-input-wacom'

    if [ "$VIDEO_DRIVER" = "i915" ]
    then
        packages+=' xf86-video-intel libva-intel-driver'
    elif [ "$VIDEO_DRIVER" = "nouveau" ]
    then
        packages+=' xf86-video-nouveau'
    elif [ "$VIDEO_DRIVER" = "radeon" ]
    then
        packages+=' xf86-video-ati'
    elif [ "$VIDEO_DRIVER" = "vesa" ]
    then
        packages+=' xf86-video-vesa'
    fi

    pacman -Sy --noconfirm $packages
}

clean_packages() {
    yes | pacman -Scc
}

update_pkgfile() {
    pkgfile -u
}

set_hostname() {
    local hostname="$1"; shift

    echo "$hostname" > /etc/hostname
}

set_timezone() {
    local timezone="$1"; shift

    ln -sT "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
}

set_locale() {
    echo 'LANG="en_US.UTF-8"' >> /etc/locale.conf
    echo 'LC_COLLATE="C"' >> /etc/locale.conf
    echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    locale-gen
}

set_keymap() {
    echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
}

set_hosts() {
    local hostname="$1"; shift

    cat > /etc/hosts <<EOF
127.0.0.1 localhost.localdomain localhost $hostname
::1       localhost.localdomain localhost $hostname
EOF
}

set_fstab() {
    local tmp_on_tmpfs="$1"; shift
    local boot_dev="$1"; shift

    local boot_uuid=$(get_uuid "$boot_dev")

    cat > /etc/fstab <<EOF
#
# /etc/fstab: static file system information
#
# <file system> <dir>    <type> <options>    <dump> <pass>

/dev/vg00/swap none swap  sw                0 0
/dev/vg00/root /    ext4  defaults,relatime 0 1

UUID=$boot_uuid /boot ext2 defaults,relatime 0 2
EOF
}

set_modules_load() {
    echo 'microcode' > /etc/modules-load.d/intel-ucode.conf
}

set_initcpio() {
    local vid

    if [ "$VIDEO_DRIVER" = "i915" ]
    then
        vid='i915'
    elif [ "$VIDEO_DRIVER" = "nouveau" ]
    then
        vid='nouveau'
    elif [ "$VIDEO_DRIVER" = "radeon" ]
    then
        vid='radeon'
    fi

    local encrypt=""
    if [ -n "$ENCRYPT_DRIVE" ]
    then
        encrypt="encrypt"
    fi


    # Set MODULES with your video driver
    cat > /etc/cpio.conf <<EOF
# vim:set ft=sh
# MODULES
# The following modules are loaded before any boot hooks are
# run.  Advanced users may wish to specify all system modules
# in this array.  For instance:
#     MODULES="piix ide_disk reiserfs"
MODULES="ext4 $vid"

# BINARIES
# This setting includes any additional binaries a given user may
# wish into the CPIO image.  This is run last, so it may be used to
# override the actual binaries included by a given hook
# BINARIES are dependency parsed, so you may safely ignore libraries
BINARIES=""

# FILES
# This setting is similar to BINARIES above, however, files are added
# as-is and are not parsed in any way.  This is useful for config files.
# Some users may wish to include modprobe.conf for custom module options
# like so:
#    FILES="/etc/modprobe.d/modprobe.conf"
FILES=""

# HOOKS
# This is the most important setting in this file.  The HOOKS control the
# modules and scripts added to the image, and what happens at boot time.
# Order is important, and it is recommended that you do not change the
# order in which HOOKS are added.  Run 'mkinitcpio -H <hook name>' for
# help on a given hook.
# 'base' is _required_ unless you know precisely what you are doing.
# 'udev' is _required_ in order to automatically load modules
# 'filesystems' is _required_ unless you specify your fs modules in MODULES
# Examples:
##   This setup specifies all modules in the MODULES setting above.
##   No raid, lvm2, or encrypted root is needed.
#    HOOKS="base"
#
##   This setup will autodetect all modules for your system and should
##   work as a sane default
#    HOOKS="base udev autodetect pata scsi sata filesystems"
#
##   This is identical to the above, except the old ide subsystem is
##   used for IDE devices instead of the new pata subsystem.
#    HOOKS="base udev autodetect ide scsi sata filesystems"
#
##   This setup will generate a 'full' image which supports most systems.
##   No autodetection is done.
#    HOOKS="base udev pata scsi sata usb filesystems"
#
##   This setup assembles a pata mdadm array with an encrypted root FS.
##   Note: See 'mkinitcpio -H mdadm' for more information on raid devices.
#    HOOKS="base udev pata mdadm encrypt filesystems"
#
##   This setup loads an lvm2 volume group on a usb device.
#    HOOKS="base udev usb lvm2 filesystems"
#
##   NOTE: If you have /usr on a separate partition, you MUST include the
#    usr, fsck and shutdown hooks.
HOOKS="base udev autodetect modconf block keymap keyboard $encrypt lvm2 resume filesystems fsck"

# COMPRESSION
# Use this to compress the initramfs image. By default, gzip compression
# is used. Use 'cat' to create an uncompressed image.
#COMPRESSION="gzip"
#COMPRESSION="bzip2"
#COMPRESSION="lzma"
#COMPRESSION="xz"
#COMPRESSION="lzop"

# COMPRESSION_OPTIONS
# Additional options for the compressor
#COMPRESSION_OPTIONS=""
EOF

    mkinitcpio -P
}

set_daemons() {
    local tmp_on_tmpfs="$1"; shift

    #systemctl enable cronie.service slim.service
    systemctl enable cpupower.service ntpd.service


    #if [ -n "$WIRELESS_DEVICE" ]
    #then
    #    systemctl enable net-auto-wired.service net-auto-wireless.service
    #else
        systemctl enable dhcpcd@eth0.service
    #fi

    if [ -z "$tmp_on_tmpfs" ]
    then
        systemctl mask tmp.mount
    fi
}

set_syslinux() {
    local lvm_dev="$1"; shift

    local lvm_uuid=$(get_uuid "$lvm_dev")

    local crypt=""
    if [ -n "$ENCRYPT_DRIVE" ]
    then
        # Load in resources
        crypt="cryptdevice=/dev/disk/by-uuid/$lvm_uuid:lvm"
    fi

    cat > /boot/syslinux/syslinux.cfg <<EOF
# Config file for Syslinux -
# /boot/syslinux/syslinux.cfg
#
# Comboot modules:
#   * menu.c32 - provides a text menu
#   * vesamenu.c32 - provides a graphical menu
#   * chain.c32 - chainload MBRs, partition boot sectors, Windows bootloaders
#   * hdt.c32 - hardware detection tool
#   * reboot.c32 - reboots the system
#   * poweroff.com - shutdown the system
#
# To Use: Copy the respective files from /usr/lib/syslinux to /boot/syslinux.
# If /usr and /boot are on the same file system, symlink the files instead
# of copying them.
#
# If you do not use a menu, a 'boot:' prompt will be shown and the system
# will boot automatically after 5 seconds.
#
# Please review the wiki: https://wiki.archlinux.org/index.php/Syslinux
# The wiki provides further configuration examples

DEFAULT arch
PROMPT 0        # Set to 1 if you always want to display the boot: prompt 
TIMEOUT 50
# You can create syslinux keymaps with the keytab-lilo tool
#KBDMAP de.ktl

# Menu Configuration
# Either menu.c32 or vesamenu32.c32 must be copied to /boot/syslinux 
UI menu.c32
#UI vesamenu.c32

# Refer to http://syslinux.zytor.com/wiki/index.php/Doc/menu
MENU TITLE Arch Linux
#MENU BACKGROUND splash.png
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

# boot sections follow
#
# TIP: If you want a 1024x768 framebuffer, add "vga=773" to your kernel line.
#
#-*

LABEL arch
	MENU LABEL Arch Linux
	LINUX ../vmlinuz-linux
	APPEND root=/dev/vg00/root ro $crypt resume=/dev/vg00/swap quiet
	INITRD ../initramfs-linux.img

LABEL archfallback
	MENU LABEL Arch Linux Fallback
	LINUX ../vmlinuz-linux
	APPEND root=/dev/vg00/root ro $crypt resume=/dev/vg00/swap
	INITRD ../initramfs-linux-fallback.img

LABEL hdt
        MENU LABEL HDT (Hardware Detection Tool)
        COM32 hdt.c32

LABEL reboot
        MENU LABEL Reboot
        COM32 reboot.c32

LABEL off
        MENU LABEL Power Off
        COMBOOT poweroff.com
EOF

    syslinux-install_update -iam
}

set_sudoers() {
    cat > /etc/sudoers <<EOF
## sudoers file.
##
## This file MUST be edited with the 'visudo' command as root.
## Failure to use 'visudo' may result in syntax or file permission errors
## that prevent sudo from running.
##
## See the sudoers man page for the details on how to write a sudoers file.
##

##
## Host alias specification
##
## Groups of machines. These may include host names (optionally with wildcards),
## IP addresses, network numbers or netgroups.
# Host_Alias	WEBSERVERS = www1, www2, www3

##
## User alias specification
##
## Groups of users.  These may consist of user names, uids, Unix groups,
## or netgroups.
# User_Alias	ADMINS = millert, dowdy, mikef

##
## Cmnd alias specification
##
## Groups of commands.  Often used to group related commands together.
# Cmnd_Alias	PROCESSES = /usr/bin/nice, /bin/kill, /usr/bin/renice, \
# 			    /usr/bin/pkill, /usr/bin/top

##
## Defaults specification
##
## You may wish to keep some of the following environment variables
## when running commands via sudo.
##
## Locale settings
# Defaults env_keep += "LANG LANGUAGE LINGUAS LC_* _XKB_CHARSET"
##
## Run X applications through sudo; HOME is used to find the
## .Xauthority file.  Note that other programs use HOME to find   
## configuration files and this may lead to privilege escalation!
# Defaults env_keep += "HOME"
##
## X11 resource path settings
# Defaults env_keep += "XAPPLRESDIR XFILESEARCHPATH XUSERFILESEARCHPATH"
##
## Desktop path settings
# Defaults env_keep += "QTDIR KDEDIR"
##
## Allow sudo-run commands to inherit the callers' ConsoleKit session
# Defaults env_keep += "XDG_SESSION_COOKIE"
##
## Uncomment to enable special input methods.  Care should be taken as
## this may allow users to subvert the command being run via sudo.
# Defaults env_keep += "XMODIFIERS GTK_IM_MODULE QT_IM_MODULE QT_IM_SWITCHER"
##
## Uncomment to enable logging of a command's output, except for
## sudoreplay and reboot.  Use sudoreplay to play back logged sessions.
# Defaults log_output
# Defaults!/usr/bin/sudoreplay !log_output
# Defaults!/usr/local/bin/sudoreplay !log_output
# Defaults!/sbin/reboot !log_output

##
## Runas alias specification
##

##
## User privilege specification
##
root ALL=(ALL) ALL

## Uncomment to allow members of group wheel to execute any command
%wheel ALL=(ALL) ALL

## Same thing without a password
# %wheel ALL=(ALL) NOPASSWD: ALL

## Uncomment to allow members of group sudo to execute any command
# %sudo ALL=(ALL) ALL

## Uncomment to allow any user to run sudo if they know the password
## of the user they are running the command as (root by default).
# Defaults targetpw  # Ask for the password of the target user
# ALL ALL=(ALL) ALL  # WARNING: only use this together with 'Defaults targetpw'

%rfkill ALL=(ALL) NOPASSWD: /usr/sbin/rfkill
%network ALL=(ALL) NOPASSWD: /usr/bin/netcfg, /usr/bin/wifi-menu

## Read drop-in files from /etc/sudoers.d
## (the '#' here does not indicate a comment)
#includedir /etc/sudoers.d
EOF

    chmod 440 /etc/sudoers
}

set_slim() {
    cat > /etc/slim.conf <<EOF
# Path, X server and arguments (if needed)
# Note: -xauth $authfile is automatically appended
default_path        /bin:/usr/bin:/usr/local/bin
default_xserver     /usr/bin/X
xserver_arguments -nolisten tcp vt07

# Commands for halt, login, etc.
halt_cmd            /sbin/poweroff
reboot_cmd          /sbin/reboot
console_cmd         /usr/bin/xterm -C -fg white -bg black +sb -T "Console login" -e /bin/sh -c "/bin/cat /etc/issue; exec /bin/login"
suspend_cmd         /usr/bin/systemctl hybrid-sleep

# Full path to the xauth binary
xauth_path         /usr/bin/xauth 

# Xauth file for server
authfile           /var/run/slim.auth

# Activate numlock when slim starts. Valid values: on|off
# numlock             on

# Hide the mouse cursor (note: does not work with some WMs).
# Valid values: true|false
# hidecursor          false

# This command is executed after a succesful login.
# you can place the %session and %theme variables
# to handle launching of specific commands in .xinitrc
# depending of chosen session and slim theme
#
# NOTE: if your system does not have bash you need
# to adjust the command according to your preferred shell,
# i.e. for freebsd use:
# login_cmd           exec /bin/sh - ~/.xinitrc %session
# login_cmd           exec /bin/bash -login ~/.xinitrc %session
login_cmd           exec /bin/zsh -l ~/.xinitrc %session

# Commands executed when starting and exiting a session.
# They can be used for registering a X11 session with
# sessreg. You can use the %user variable
#
# sessionstart_cmd	some command
# sessionstop_cmd	some command

# Start in daemon mode. Valid values: yes | no
# Note that this can be overriden by the command line
# options "-d" and "-nodaemon"
# daemon	yes

# Available sessions (first one is the default).
# The current chosen session name is replaced in the login_cmd
# above, so your login command can handle different sessions.
# see the xinitrc.sample file shipped with slim sources
sessions            foo

# Executed when pressing F11 (requires imagemagick)
#screenshot_cmd      import -window root /slim.png

# welcome message. Available variables: %host, %domain
welcome_msg         %host

# Session message. Prepended to the session name when pressing F1
# session_msg         Session: 

# shutdown / reboot messages
shutdown_msg       The system is shutting down...
reboot_msg         The system is rebooting...

# default user, leave blank or remove this line
# for avoid pre-loading the username.
#default_user        simone

# Focus the password field on start when default_user is set
# Set to "yes" to enable this feature
#focus_password      no

# Automatically login the default user (without entering
# the password. Set to "yes" to enable this feature
#auto_login          no

# current theme, use comma separated list to specify a set to 
# randomly choose from
#current_theme       default
current_theme       archlinux-simplyblack

# Lock file
lockfile            /run/lock/slim.lock

# Log file
logfile             /var/log/slim.log
EOF
}

set_netcfg() {
    cat > /etc/network.d/wired <<EOF
CONNECTION='ethernet'
DESCRIPTION='Ethernet with DHCP'
INTERFACE='eth0'
IP='dhcp'
EOF

    chmod 600 /etc/network.d/wired

    cat > /etc/conf.d/netcfg <<EOF
# Enable these netcfg profiles at boot time.
#   - prefix an entry with a '@' to background its startup
#   - set to 'last' to restore the profiles running at the last shutdown
#   - set to 'menu' to present a menu (requires the dialog package)
# Network profiles are found in /etc/network.d
NETWORKS=()

# Specify the name of your wired interface for net-auto-wired
WIRED_INTERFACE="eth0"

# Specify the name of your wireless interface for net-auto-wireless
WIRELESS_INTERFACE="$WIRELESS_DEVICE"

# Array of profiles that may be started by net-auto-wireless.
# When not specified, all wireless profiles are considered.
#AUTO_PROFILES=("profile1" "profile2")
EOF
}

set_root_password() {
    local password="$1"; shift

    echo -en "$password\n$password" | passwd
}

create_user() {
    local name="$1"; shift
    local password="$1"; shift

    useradd -m -s /bin/zsh -G adm,systemd-journal,wheel,rfkill,games,network,video,audio,optical,floppy,storage,scanner,power,adbusers,wireshark "$name"
    echo -en "$password\n$password" | passwd "$name"
}

update_locate() {
    updatedb
}

get_uuid() {
    blkid -o export "$1" | grep UUID | awk -F= '{print $2}'
}

set -ex

if [ "$1" == "chroot" ]
then
    configure
else
    setup
fi
