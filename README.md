<h1>Server-Setup</h1>
</br>
Atomatic Fresh Server Setup Script Installation steps on Ubuntu Connect to your server through ssh and copy and run the following command in the terminal

<b>Server Preparation</b>

<code>apt update -y && apt upgrade -y && apt autoremove -y && apt autoclean -y && reboot</code>

<h2>After Rebooting Server</h2>

<code>apt install -y sudo curl wget dialog</code>

<h2>Server Scripts Installation</h2>

For manual installation, copy and run the following command in the terminal.
```
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/repository.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/bootstrap.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/security.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/network.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/apps.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/hosting.sh)"
```

You can donate to me through Plisio at ❤️

<a href="https://plisio.net/donate/f_9qcQRU" target="_blank"><img src="https://plisio.net/img/donate/donate_light_icons_color.png" alt="Donate Crypto on Plisio" width="240" height="80" /></a>
