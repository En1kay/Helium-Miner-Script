#!/bin/bash

while getopts a:i: flag
do
    case "${flag}" in
        a) IP=${OPTARG};;
        i) interface=${OPTARG};;
    esac
done
echo "Interface: $interface";
echo "IP: $IP";

sudo apt update && sudo apt upgrade
sudo apt install wireguard netfilter-persistent -y

sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -p

wg genkey | sudo tee /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key
sudo chmod 600 /etc/wireguard/server_private.key

mkdir /home/keys

wg genkey | sudo tee /home/keys/client_private.key | wg pubkey | sudo tee /home/keys/client_public.key
sudo chmod 600 /home/keys/client_private.key

sudo printf "[INTERFACE]\nPrivateKey = " > /etc/wireguard/wg0.conf
sudo cat /etc/wireguard/server_private.key >> /etc/wireguard/wg0.conf
sudo printf "Address = 10.5.5.1\nListenPort = 61951\n\n[Peer]\nPublicKey = " >> /etc/wireguard/wg0.conf
sudo cat /home/keys/client_public.key >> /etc/wireguard/wg0.conf
sudo printf "AllowedIPs = 10.5.5.2/32" >> /etc/wireguard/wg0.conf

sudo systemctl start wg-quick@wg0
sudo systemctl enable wg-quick@wg0

sudo printf "[INTERFACE]\nPrivateKey = " > /home/keys/wg0.conf
sudo cat /home/keys/client_private.key >> /home/keys/wg0.conf
sudo printf "Address = 10.5.5.2\nListenPort = 61951\n\n[Peer]\nPublicKey = " >> /home/keys/wg0.conf
sudo cat /etc/wireguard/server_public.key >> /home/keys/wg0.conf
sudo printf "AllowedIPs = 0.0.0.0/0\nEndpoint = $IP:61951\nPersistentKeepalive = 25" >> /home/keys/wg0.conf

sudo iptables -P FORWARD DROP
sudo iptables -A FORWARD -i $interface -o wg0 -p tcp --syn --dport 44158 -m conntrack --ctstate NEW -j ACCEPT
sudo iptables -A FORWARD -i $interface -o wg0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A FORWARD -i wg0 -o $interface -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
sudo iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE

sudo iptables -t nat -A PREROUTING -i $interface -p tcp --dport 44158 -j DNAT --to-destination 10.5.5.2

sudo netfilter-persistent save
sudo systemctl enable netfilter-persistent