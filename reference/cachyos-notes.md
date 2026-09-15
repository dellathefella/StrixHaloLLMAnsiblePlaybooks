### SSH Install

```bash
sudo pacman -S openssh
sudo systemctl start sshd
sudo systemctl enable sshd
sudo ufw allow 22/tcp
# Disable firewall entirely
sudo ufw disable
```