#!/bin/bash

# Display available network interfaces
ip link

echo "What network interface would you like to use?"
read interface

echo "Enter the SSID of the Wi-Fi network:"
read ssid

echo "Enter the password (PSK) for the Wi-Fi network:"
read psk

# Configure the Wi-Fi connection
conf="/etc/wpa_supplicant/wpa_supplicant.conf"
cat > $conf << EOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
update_config=1

network={
    ssid="$ssid"
    psk="$psk"
    mesh_fwding=1
}
EOF

# Unblocking WiFi and killing any previous instances of wpa_supplicant
rfkill unblock wifi
killall wpa_supplicant

# Starting the wpa_supplicant
wpa_supplicant -B -i "$interface" -c "$conf"

# Obtaining IP address
dhclient "$interface"

# Check network connection
ping -c 4 artixlinux.org

# Display block devices and ask user to select one for installation
lsblk
echo "What drive do you want to use?"
read drive

# Confirm partitioning
echo "Are you sure you want to partition /dev/$drive? This can erase data! [y/N]"
read confirmation
if [[ $confirmation != "y" && $confirmation != "Y" ]]; then
    echo "Partitioning canceled."
    exit 1
fi

# Get partition sizes
echo "Boot partition size (in Gb):"
read boot
echo "Root partition size (in Gb):"
read root
echo "Swap partition size (in Gb):"
read swap
echo "Home partition size (in Gb):"
read home

# Create partitions
fdisk /dev/$drive << EOF
o
n
p
1
+${boot}G
n
p
2
+${root}G
n
p
3
+${swap}G
n
p
4
+${home}G
w
EOF

# Formatting partitions
mkfs.fat -F 32 /dev/${drive}1
mkfs.ext4 /dev/${drive}2
mkswap /dev/${drive}3
mkfs.ext4 /dev/${drive}4

# Mount filesystems
mount /dev/${drive}2 /mnt
mkdir /mnt/boot/efi /mnt/home
mount /dev/${drive}1 /mnt/boot/efi
mount /dev/${drive}4 /mnt/home
swapon /dev/${drive}3

# Installing base system
basestrap /mnt linux linux-firmware base base-devel runit elogind-runit networkmanager networkmanager-runit sudo nano git grub efibootmgr

# Generate fstab
fstabgen -U /mnt >> /mnt/etc/fstab

# Configure system settings within chroot
artix-chroot /mnt /bin/bash <<EOF
echo "Select region:"
read region
echo "Select city:"
read city
ln -sf /usr/share/zoneinfo/\$region/\$city /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen

echo "KEYMAP=us" > /etc/vconsole.conf

grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo "Root password:"
read root_password
echo "root:\$root_password" | chpasswd

echo "Username:"
read user
useradd -G wheel -m \$user

echo "Password for \$user:"
read -s password
echo "\$user:\$password" | chpasswd

echo "Hostname:"
read hostname
echo "\$hostname" > /etc/hostname

cat << EOH > /etc/hosts
127.0.0.1       localhost
::1             localhost
127.0.1.1       \$hostname.localdomain \$hostname
EOH
EOF

# Unmount all partitions and reboot
sync
umount -R /mnt || reboot
