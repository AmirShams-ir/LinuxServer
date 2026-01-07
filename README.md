<b>Server-Setup</b>
</br>
Atomatic Fresh Server Setup Script Installation steps on Ubuntu Connect to your server through ssh and copy and run the following command in the terminal

<b> Server Preparation </b>

<code> apt update -y && apt upgrade -y && apt autoremove -y && apt autoclean -y && reboot </code>

After Rebooting Server

* apt install -y sudo curl wget dialog
Server Scripts Installation

 bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/net.sh)"
