<h1>Server-Setup</h1>
</br>
Atomatic Fresh Server Setup Script Installation steps on Ubuntu Connect to your server through ssh and copy and run the following command in the terminal

<b>Server Preparation</b>

<code> apt update -y && apt upgrade -y && apt autoremove -y && apt autoclean -y && reboot </code>

<h2>After Rebooting Server</h2>

<code> apt install -y sudo curl wget dialog </code>

<h2>Server Scripts Installation</h2>

 <code> 
 bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/repository.sh)"

 bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/bootstrap.sh)"

 bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/security.sh)"

 bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/network.sh)"
 </code>
