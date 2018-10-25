
## some stuff for a sd-card less Raspberry Pi cluster,no need to work with sd-cards any more
this repro contains working code, but needs a little lipstick to look beautiful

my equipment:

1o Raspberry Pi 3B+ in a 19" 2HE rack mounted assembly, one with a SSD [attached via USB](https://www.amazon.de/USB-SATA-Adapter-Kabel-UASP/dp/B00HJZJI84/ref=sr_1_3?ie=UTF8&qid=1540311792&sr=8-3&keywords=usb+sata+adapter+2%2C5+startech). 

Keep an eye on the power consumption of the SSD your Raspberry won´t boot if the consumption is greater than 600mA. 


## Setup Controll Server (tftp/nfs host, boots from USB-SSD) 

##### the included ansible files should used from a external system like a MAC or a Linux PC
Plug the SD card into the server Raspberry Pi. Boot the server. Before you do anything else, make sure you have run sudo raspi-config and expanded the root filesystem to take up the entire SD card.

The client Raspberry Pi will need a root filesystem to boot off, so before we do anything else on the server, we're going to make a full copy of its filesystem and put it in a directory called /nfs/master_raspbian.

```
sudo mkdir -p /nfs/master_raspbian
sudo apt-get install rsync
sudo rsync -xa --progress --exclude /nfs / /nfs/master_raspbian
```


Regenerate SSH host keys on the client filesystem by chrooting into it:
```
cd /nfs/master_raspbian
sudo mount --bind /dev dev
sudo mount --bind /sys sys
sudo mount --bind /proc proc
sudo chroot .
rm /etc/ssh/ssh_host_*
dpkg-reconfigure openssh-server
exit
sudo umount dev
sudo umount sys
sudo umount proc
```

Find the settings of your local network. You need to find the address of your router (or gateway), which can be done with:

```
ip route | grep default | awk '{print $3}'
```

Then run:
```
ip -4 addr show dev eth0 | grep inet
```

which should give an output like:

```
inet 10.42.0.211/24 brd 10.42.0.255 scope global eth0
```

The first address is the IP address of your server Raspberry Pi on the network, and the part after the slash is the network size. It is highly likely that yours will be a /24. Also note the brd (broadcast) address of the network. Note down the output of the previous command, which will contain the IP address of the Raspberry Pi and the broadcast address of the network.

Finally, note down the address of your DNS server, which is the same address as your gateway. You can find this with:
```
cat /etc/resolv.conf
```

Configure a static network address on your server Raspberry Pi by with sudo nano /etc/network/interfaces (where you replace nano with an editor of your choice). Change the line, iface eth0 inet manual so that the address is the first address from the command before last, the netmask address as 255.255.255.0 and the gateway address as the number received from the last command.
```
auto eth0
iface eth0 inet static 
        address 10.42.0.211
        netmask 255.255.255.0
        gateway 10.42.0.1
```
Disable the DHCP client daemon and switch to standard Debian networking:

```
sudo systemctl disable dhcpcd
sudo systemctl enable networking
```
Reboot for the changes to take effect:
```
sudo reboot
```
At this point, you won't have working DNS, so you'll need to add the server you noted down before to /etc/resolv.conf. Do this by using the following command, where the IP address is that of the gateway address you found before.
```
echo "nameserver 10.42.0.1" | sudo tee -a /etc/resolv.conf
```
Make the file immutable (because otherwise dnsmasq will interfere) with the following command:
```
sudo chattr +i /etc/resolv.conf
```
Install software we need:
```
sudo apt-get update
sudo apt-get install dnsmasq tcpdump
```
Stop dnsmasq breaking DNS resolving:
```
sudo rm /etc/resolvconf/update.d/dnsmasq
sudo reboot
```
Configure your DHCP Server to forward fftp request "next-server" to the IP of this Raspberry Pi
Now start tcpdump so you can search for DHCP packets from the client Raspberry Pi:
```
sudo tcpdump -i eth0 port bootpc
```
Connect the client Raspberry Pi to your network and power it on. Check that the LEDs illuminate on the client after around 10 seconds, then you should get a packet from the client "DHCP/BOOTP, Request from ..."
please write down the mac-adress of each and every raspberry Pi you want to enable with networkboot

```
IP 0.0.0.0.bootpc > 255.255.255.255.bootps: BOOTP/DHCP, Request from b8:27:eb...
```
Now we need to modify the dnsmasq configuration to enable DHCP to reply to the device. Press CTRL+C on the keyboard to exit the tcpdump program, then type the following:
```
echo | sudo tee /etc/dnsmasq.conf
sudo nano /etc/dnsmasq.conf
```

Then replace the contents of dnsmasq.conf with:
```
port=0
dhcp-range=10.42.0.255,proxy
log-dhcp
enable-tftp
tftp-root=/tftpboot
tftp-unique-root=mac
pxe-service=0,"Raspberry Pi Boot"
```
Where the first address of the dhcp-range line is, use the broadcast address you noted down earlier.

Now create a /tftpboot directory:
```
sudo mkdir /tftpboot
sudo chmod 777 /tftpboot
sudo systemctl enable dnsmasq.service
sudo systemctl restart dnsmasq.service
```

Next, you will need to copy all files from /boot-partition to a folder /tftpboot/"macadress with -"/ 



Restart dnsmasq for good measure:
```
sudo systemctl restart dnsmasq
```

## Put everything from SD card to SSD
copy the usb-boot from ressources to a directory and execute it, reboot to load /boot from sd and rest from SSD, adjust /etc/fstab to remove sd completely 
by changing "PARTUUID=" for / 
halt Raspberry Pi, remove SD and restart.


## Setup NTFS-Boot for Clients (diskless boot)


This should now allow your Raspberry Pi to boot through until it tries to load a root filesystem (which it doesn't have). All we have to do to get this working is to export the /nfs/master_raspbian filesystem we created earlier.
```
sudo apt-get install nfs-kernel-server
```

copy exports file(example within ressources directory) to /etc/exports

```
sudo systemctl enable rpcbind
sudo systemctl restart rpcbind
sudo systemctl enable nfs-kernel-server
sudo systemctl restart nfs-kernel-server
```

Edit /tftpboot/"macadress with-"/cmdline.txt and from root= onwards, and replace it with:
```
root=/dev/nfs nfsroot=10.42.0.211:/nfs/"target",vers=3 rw ip=dhcp rootwait elevator=deadline
```
You should substitute the IP address here with the IP address you have noted down.

Finally, edit /nfs/"target"/etc/fstab and remove the /dev/mmcblkp1 and p2 lines (only proc should be left).

It´s a good practice to put an operating systems root files system in a master_xyz directory and use the included ansible playbook to generate client specific directories in /nfs. 
The same structure for the /boot Partition, one master_xyz and several client specific directory within /sftpboot, a symbolic link with the clients serialnumber as the name should then point to the client specific directory

