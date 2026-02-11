<h1>Server-Setup</h1>
</br>
Atomatic Fresh Server Setup Script Installation steps on Debian/Ubuntu VPS.
Connect to your vps through ssh and copy and run the following command in the terminal.

<b>Server Preparation</b>

<code>apt update -y && apt upgrade -y && apt autoremove -y && apt autoclean -y && reboot</code>

<h2>After Rebooting Server</h2>

<code>apt install -y sudo curl wget</code>

<h2>Host Server Scripts Installation Commands</h2>

For manual installation, copy and run the following command in the terminal.
```
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/dns.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/repository.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/disktweak.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/security.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/ssl.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/bootstrap.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/netstrap.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/host.sh)"
```

You can donate to me through Plisio

<a href="https://plisio.net/donate/f_9qcQRU" target="_blank"><img src="https://plisio.net/img/donate/donate_light_icons_color.png" alt="Donate Crypto on Plisio" width="240" height="80" /></a>

<b> Made with ❤️ 4U </b>
