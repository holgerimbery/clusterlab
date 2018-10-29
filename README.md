
# feeder-cluster - a Raspberry Pi Cluster (RPi 3B+) without SD Cards

![feeder_logo](https://github.com/holgerimbery/environment/raw/master/feeder_logo_small.jpg)

*feeder (small container ship)* 

a Raspberry Pi 3B+ cluster with docker and - as an option-  ready to install docker swarm with portainer gui or kubernetes. All worker nodes operate in a diskless mode.


*Network booting works only for the wired adapter. Booting over **wireless LAN** is not supported.
It is also important that there is already a **working DHCP server** on the local network.*


#### My own lab:
* 1o Raspberry Pi 3B+ in a 19" 2HE rack mounted assembly
* master is booting from a SSD [attached via USB](https://www.amazon.de/USB-SATA-Adapter-Kabel-UASP/dp/B00HJZJI84/ref=sr_1_3?ie=UTF8&qid=1540311792&sr=8-3&keywords=usb+sata+adapter+2%2C5+startech). 

Keep an eye on the power consumption of the SSD, your Raspberry won´t boot if the consumption is greater than 600mA. 



Please forget all the quirks, hints and workarounds to netboot with older models you may find on the web. There is no need to prepare the worker for netbooting. It will simply try it if there is no SD Card inserted.
Flash latest raspbian lite to an SD-Card and enable ssh. We will setup a master RPi with SD-Card and several worke RPis in a diskless mode.
Later - we will convert the master to boot from a SDD.
This setup can be done headless. After first boot ssh into the RPi and update Raspbian:
You can copy and past every
```
codeblock
```
to the ssh terminal you have with your master RPi.

Let´s start with some basics, new password and update to the latest versions.

```bash
passwd 
sudo -Es
apt update
apt full-upgrade
```
transfer your public key to the RPi to enable password less login, be aware that this will enable it also automatically on the workers

## Setup systemd-networkd

```bash
mkdir -p /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
apt --yes install systemd-container
systemctl mask networking.service
systemctl mask dhcpcd.service
mv /etc/network/interfaces /etc/network/interfaces~
sed -i '1i resolvconf=NO' /etc/resolvconf.conf
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

We will give our master a static ip address because it works as a server. 

For example my master is on 
subnet            192.168.1.0/24
static ip address 192.168.1.100
broadcast address 192.168.1.255
gateway/router    192.168.1.1
dns server        192.168.1.1

Of course you have to use the ip addresses from your network. Look what are yours. You may find your dns server with cat /etc/resolv.conf. If in doubt you may use googles dns server 8.8.8.8. To set the static ip address write this file:

```bash
cat > /etc/systemd/network/04-eth.network <<EOF
[Match]
Name=e*
[Network]
Address=192.168.10.100/24
Gateway=192.168.10.1
DNS=192.168.10.1
EOF
```

Rename hostname from raspberrypi to master:
```bash
sed -i 's/raspberrypi/cluster00/' /etc/hostname
sed -i 's/raspberrypi/cluster00/g' /etc/hosts
```

Reboot.


## Master configuration

ssh into your master. Remember that is has now a new static ip address.

This setup will also be used for the worker, so we copy it to a directory we will later mount as root partition for the worker.
```bash
sudo -Es
mkdir -p /nfs/worker_default
rsync -xa --exclude /nfs / /nfs/worker_default
mkdir -p /tftpboot/00-00-00-00-00-00
rsync -xa /boot/ /tftpboot/00-00-00-00-00-00
```
Don't worry now. Depending on your SD Card copying of 1.1 GByte will take about 15 minutes or longer. Look at the green led on your RasPi.

When finished to prepare the network and the name of the worker:
```bash
rm /nfs/worker_default/etc/systemd/network/04-eth.network
sed -i 's/cluster00/worker_default/' /nfs/worker_default/etc/hostname
sed -i 's/cluster00/worker_default/g' /nfs/worker_default/etc/hosts
```

Now we start the worker in a container. This is similar to chroot but more powerful. We regenerate SSH host keys so ssh will not complain about spoofing ("it has already seen the same host with other ip address"):
Login and execute following commands. This will create new SSH2 server keys and it tries to start the ssh.service but that will fail because the ethernet interface is already used by the master. Starting the ssh.service (here with error) is essentional because we are headless on the worker. If the worker is running on its own hardware this should go without error.
```bash
systemd-nspawn -D /nfs/worker_default /sbin/init
```
```bash
sudo rm /etc/ssh/ssh_host_*
sudo dpkg-reconfigure openssh-server
logout
```
Exit from container with CTRL+(short three times)]. [Mac User CTRL+OPTION+(short three times)6]


## Setup tftp server

Now we will install a tftp server that is needed to send boot files to the worker. The program dnsmasq will provide this. Also we install the network sniffer tcpdump to look if the worker requests its boot files the right way:

```
apt --yes install dnsmasq tcpdump
# Stop dnsmasq breaking DNS resolving:
rm /etc/resolvconf/update.d/dnsmasq
```

Now start tcpdump so you can search for DHCP packets from the worker:
```
tcpdump -i eth0 port bootpc
```

Now power on the worker RPi without SD Card. Then you should get packets from it "DHCP/BOOTP, Request from ..."

IP 0.0.0.0.bootpc > 255.255.255.255.bootps: BOOTP/DHCP, Request from b8:27:eb:d3:85:78

Here we have to notice the mac address b8:27:eb:d3:85:78 from the worker RPi. You should also see that it gets a reply to an ip address from the DHCP server on your local network, here 192.168.10.1:

IP 192.168.1.1.bootps > 192.168.1.101.bootpc: BOOTP/DHCP, Reply, length 300
Exit with CTRL+C. 


If you have more than one raspberry repeat the step above to notice all mac adresses of your RPis.

Then we have to configure dnsmasq to serve boot files via tftp.
Write this file:
```
cat > /etc/dnsmasq.conf <<EOF
port=0
dhcp-range=192.168.1.255,proxy
log-dhcp
enable-tftp
tftp-root=/tftpboot
tftp-unique-root=mac
pxe-service=0,"Raspberry Pi Boot"
EOF
```

The first address of the dhcp-range is the broadcast address of your network. 
Now create a /tftpboot directory for each client with a script
The subdirectory for the specific worker (its mac address, we have noticed with tcpdump) must have only lower case characters and dashes, 
put all mac adresse in the for in in line with a space in between.


```
cat > /home/pi/tftpboot_clients.sh <<EOF
#!/bin/bash
j=0
ip_adress=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
## edit : replace macadresses
for i in b8-27-eb-40-45-36 b8-27-eb-c5-e3-47 b8-27-eb-00-6b-0b b8-27-eb-4f-fc-f6 b8-27-eb-38-bb-d2 b8-27-eb-00-00-01  b8-27-eb-00-00-02 b8-27-eb-c4-8a-99 b8-27-eb-ae-c4-fe
do
    j=$(expr $j + 1)
    rsync -xa --progress /nfs/worker_default/ /nfs/cluster0${j}/
    mkdir -p /tftpboot/${i}
    rsync -xa --progress /tftpboot/00-00-00-00-00-00/ /tftpboot/${i}
    echo "proc            /proc           proc    defaults          0       0" > /nfs/cluster0${j}/etc/fstab
    touch /tftpboot/${i}/cmdline.txt
    echo -n "dwc_otg.lpm_enable=0 console=serial0,115200 console=tty1" > /tftpboot/${i}/cmdline.txt && echo -n " root=/dev/nfs nfsroot=" >> /tftpboot/${i}/cmdline.txt && echo -n $ip_adress >> /tftpboot/${i}/cmdline.txt && echo -n ":/nfs/cluster0" >> /tftpboot/${i}/cmdline.txt && echo -n ${j} >> /tftpboot/${i}/cmdline.txt && echo ",vers=3 rw ip=dhcp rootwait elevator=deadline" >> /tftpboot/${i}/cmdline.txt


done
chmod -R 777 /tftpboot
systemctl enable dnsmasq.service
systemctl restart dnsmasq.service
EOF
chmod 755 /home/pi/tftpboot_clients.sh
/home/pi/tftpboot_clients.sh
```

## Set up NFS root

This should now allow your Raspberry Pi to boot through until it tries to load a root filesystem that is normally located at the second partition of the SD Card (which it doesn't have). All we have to do to get this working is to export the /nfs/ filesystem we created earlier.
```
apt install nfs-kernel-server
systemctl enable rpcbind
systemctl enable nfs-kernel-server
echo "/nfs *(rw,sync,no_subtree_check,no_root_squash)" | tee -a /etc/exports
systemctl restart rpcbind
systemctl restart nfs-kernel-server
```

Now power cycle the worker RPis and they should boot. You can monitor again. You will also see what ip address your worker has:

```
journalctl --unit dnsmasq.service --follow
```

Now you should be able to ssh into the worker e.g. with:
```
ssh pi@192.168.10.101
```

## What to do next?
Do something useful with your cluster :-) 
* install ansible on your workstation clone the repository to your local disk
```
git clone https://github.com/holgerimbery/feeder-cluster.git feeder-cluster
```
* copy config.sample.yml to config.yml
* generate a password hash for the password you created in the first step while setting this up and put it in the config.yml
* copy hosts.sample to hosts and edit it to meet your requirements

### booting the master from USB-SSD
[attached a SSD via USB](https://www.amazon.de/USB-SATA-Adapter-Kabel-UASP/dp/B00HJZJI84/ref=sr_1_3?ie=UTF8&qid=1540311792&sr=8-3&keywords=usb+sata+adapter+2%2C5+startech) to the master RPi, be aware all data on the SSD will be ereased during the automated process

```
cd cluster
./copy-usb-boot.sh
```
ssh to master
```
sudo -Es
./usb-boot.sh
```
halt master, remove sd-card and powercycle RPi



### Install Docker


* update all worker nodes, install docker with permitions and  regenerate all ssh host keys with a single command


```
cd cluster
./setup_nodes.sh
```

sometimes you have to start the last command several time in a row until you get green ok= for all RPis from the playbook at the end.

install docker on the master RPi

```
cd cluster
./setup_master.sh
```
### Docker swarm with Gui
#### Initialise the swarm

ssh to your master and init a swarm

```
docker swarm init
```
remember the "docker swarm join --token §$%&/($%&/()%&/()" part of the output and join all your workers to the swarm

```
ansible nodes -i hosts --become --args "join output" --user pi
```

ssh to the master and
```
docker node ls
```

#### install portainer on the swarm for graphical management

* ssh to the master and download the stack file
* option one: with local acess
```
curl -LO https://raw.githubusercontent.com/holgerimbery/feeder-stack/master/portainer-agent-stack.yml
```
* option two: with external access and docker-flow-proxy and letsencrypt certificate 
```
curl -LO https://raw.githubusercontent.com/holgerimbery/feeder-stack/master/portainer-agent-proxy-stack.yml
```
* edit the stackfile to be compliant with your needs
  (option2 - your email address and your domainname for the cerificate and the proxy session) 
* start the cluster - option one
```
docker stack deploy -c portainer-agent-stack.yml portainer
```
* or for option two, you need to setup a forwarding rule on your internet-access router port 80 & 443
```
docker stack deploy -c portainer-agent-stack.yml portainer
```
* the management interface will be available for option one at
```
https://"<ipadressofmaster>":9000
```
* or for option 2 at
```
https://"<your-configured-domainname>"
```