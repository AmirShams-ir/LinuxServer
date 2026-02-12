<div align="center">

# 🚀 LinuxServer – Automated VPS Hosting Setup

![Debian](https://img.shields.io/badge/Debian-12|13-red?logo=debian)
![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04|24.04-orange?logo=ubuntu)
![License](https://img.shields.io/badge/License-MIT-blue)
![Maintained](https://img.shields.io/badge/Maintained-Yes-success)

> ⚡ Automatic Fresh Server Setup & Hosting Bootstrap Script  
> Optimized for **Debian & Ubuntu VPS**

</div>

---

## ✨ About This Project

**LinuxServer** is a professional automated setup toolkit for fresh VPS installations.

It prepares your server for production hosting by configuring:

- 🔐 Security hardening
- 🌐 DNS configuration
- 📦 Repository tuning
- 💽 Disk optimization
- 🔒 SSL configuration
- ⚙️ Network optimization
- 🏗 Hosting bootstrap environment

Built for clean, stable and production-ready deployments.

---

# 🖥 Supported Operating Systems

- ✅ Debian 12  
- ✅ Debian 13  
- ✅ Ubuntu 22.04 LTS  
- ✅ Ubuntu 24.04 LTS  

---

# ⚙️ Step 1 — Initial Server Preparation

Connect to your VPS via SSH and run:

```bash
apt update -y && apt upgrade -y && apt autoremove -y && apt autoclean -y && reboot
```

---

# 🔧 Step 2 — Install Required Tools (After Reboot)

```bash
apt install -y sudo curl wget
```

---

# 🚀 Step 3 — Install Hosting Scripts

You can install scripts manually one by one:

```bash
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/dns.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/repository.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/disktweak.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/bootstrap.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/ssl.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/netstrap.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/host.sh)"
bash -c "$(curl -Lfo- https://raw.githubusercontent.com/AmirShams-ir/LinuxServer/refs/heads/main/security.sh)"
```

---

# 🧠 Script Overview

| Script | Description |
|--------|-------------|
| `dns.sh` | DNS resolver & performance tuning |
| `repository.sh` | Official repo configuration & cleanup |
| `disktweak.sh` | Disk & filesystem optimization |
| `security.sh` | SSH hardening, firewall & protection |
| `ssl.sh` | SSL & certificate automation |
| `bootstrap.sh` | Base server environment setup |
| `netstrap.sh` | Advanced network optimization |
| `host.sh` | Hosting environment automation |

---

# 🔐 Why Use LinuxServer?

- 🧼 Clean & structured setup  
- 🛡 Secure-by-default configuration  
- ⚡ Performance optimized  
- 📦 Official repositories only  
- 🧩 Modular architecture  
- 🧑‍💻 Easy to maintain  

---

# 💰 Support the Project

If this project helps you, you can support development via crypto donation:

<div align="center">
<a href="https://plisio.net/donate/f_9qcQRU" target="_blank">
<img src="https://plisio.net/img/donate/donate_light_icons_color.png" width="240" />
</a>
</div>

---

<div align="center">

## ❤️ Made with Love by Amir & ChatGPT

Production-grade VPS setup toolkit  
Built for stability. Designed for performance.
Core Architecture & Automation Design by ChatGPT

</div>
