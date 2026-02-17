## 🚀 Quick Start

Clone and run the installer:

```bash
git clone https://github.com/BrianWilkinsFL/open-hamclock-backend.git
cd open-hamclock-backend
sudo bash install_ohb.sh --size <desired size list>
```
Verify Core Feeds:

curl http://localhost/ham/HamClock/solarflux/solarflux-history.txt | tail
curl http://localhost/ham/HamClock/geomag/kindex.txt | tail

Verify Maps Exist:

sudo ls /opt/hamclock-backend/htdocs/ham/HamClock/maps | head

If you see data and maps, OHB is running.

Full installation details:
👉 [Detailed Installation Instructions](INSTALL.md)
