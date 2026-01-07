Server-Setup
Atomatic Fresh Server Setup Script Installation steps on Ubuntu Connect to your server through ssh and copy and run the following command in the terminal

Server Preparation

apt update -y && apt upgrade -y && apt autoremove -y && apt autoclean -y && reboot
After Rebooting Server

apt install -y sudo curl wget dialog
Server Scripts Installation

sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/start.sh)"
For manual installation, copy and run the following command in the terminal.

sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/user.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/swap.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/bbr.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/hybla.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/corn.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/ssl.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/tls.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/ufw.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/udpgw.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/speed.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/warp.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/pihole.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/tcpo.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/website.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/wordpress.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/essential.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/advanced.sh)"
sudo bash -c "$(curl -Lfo- https://raw.githubusercontent.com/Amir-Net/Server-Setup/main/repositories.sh)"

Used Projects in this script 🙏

https://github.com/P3TERX/warp.sh
https://github.com/ErfanNamira/FreeIRAN
You can donate to me through Plisio at ❤️

Donate Crypto on Plisio
