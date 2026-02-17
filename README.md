# 🛟 OHB — Open HamClock Backend
Open-source, self-hostable backend replacement for HamClock.

When the original backend went dark, the clocks didn’t have to.

OHB provides faithful replacements for the data feeds and map assets
that HamClock depends on — built by operators, for operators.

> This project is not affiliated with HamClock or its creator,
> Elwood Downey, WB0OEW.
> We extend our sincere condolences to the Downey family.

---

## ✨ What OHB Does

- Rebuilds HamClock dynamic text feeds (solar, geomag, DRAP, PSK, RBN, WSPR, Amateur Satellites, DxNews, Contests, etc)
- Generates map overlays (MUF-RT, DRAP, Aurora, Wx-mB, etc.)
- Produces zlib-compressed BMP assets in multiple resolutions
- Designed for Raspberry Pi, cloud, or on-prem deployment
- Fully open source and community maintained

---

## 🧭 Architecture
```
[ NOAA / KC2G / PSK / SWPC ]
              |
              v
        +-------------+
        |     OHB     |
        |-------------|
        | Python/Perl|
        | GMT/Maps   |
        | Cron Jobs  |
        +-------------+
              |
           HTTP/ZLIB
              |
         +----------+
         | lighttpd |
         +----------+
              |
         +----------+
         | HamClock |
         +----------+
```

## Join us on Discord 💬
We are building a community-powered backend to keep HamClock running. \
Discord is where we can collaborate, troubleshoot, and exchange ideas — no RF license required 😎 \
https://discord.gg/wb8ATjVn6M

## 🚀 Quick Start  
## 📦 Installation  
## 🛠 Usage Examples  
## 🤝 Contributing

## Install:
(NOTE: to run OHB in docker, visit https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/docker/README.md)

```bash
   # Confirmed working in aws t3-micro Ubuntu 24.x LTS instance
   wget -O install_ohb.sh https://raw.githubusercontent.com/BrianWilkinsFL/open-hamclock-backend/refs/heads/main/aws/install_ohb.sh
   chmod +x install_ohb.sh
   sudo ./install_ohb.sh
```
## Selecting map image sizes during install

By default, OHB generates the full HamClock size set. This is only recommend on a high end PC or VM:

`660x330,1320x660,1980x990,2640x1320,3960x1980,5280x2640,5940x2970,7920x3960`

To install with a custom size set, pass one of the options below:

### Option A: Comma-separated list
> [!WARNING]
> Attempting to image generate multiple sizes or 4K UHD sizes on Pi3B can cause it to overheat!

```bash
chmod +x ./install_ohb.sh
sudo ./install_ohb.sh --sizes "660x330,1320x660,1980x990"
```
### Option B: Repeat --size
> [!WARNING]
> Attempting to image generate multiple sizes or 4K UHD sizes on Pi3B can cause it to overheat!

```bash
chmod +x ./install_ohb.sh
sudo ./install_ohb.sh --size 660x330 --size 1320x660 --size 1980x990
```

Install script will store configuration under /opt/hamclock-backend/etc/ohb-sizes.conf

```bash
# Canonical default list (keep in sync with HamClock)
DEFAULT_SIZES=( \
  "660x330" \
  "1320x660" \
  "1980x990" \
  "2640x1320" \
  "3960x1980" \
  "5280x2640" \
  "5940x2970" \
  "7920x3960" \
)
```

Note: OHB will install default maps (Countries and Terrain) for all possible sizes. This does not incur any major CPU or RAM hit on small form factor PCs as it is just a download, extract and install

After install, update your HamClock startup script to point to OHB. Then, reboot your HamClock.

## Starting HamClock with OHB Local Install
HamClock is hard-coded to use the clearskyinstitute.com URL. You can override to use a new backend by starting HamClock with the -b option

### Localhost (if running OHB adjacent to your existing HamClock client such as Raspberry Pi)
```bash
hamclock -b localhost:80
```
Note: Depending on where you installed HamClock application, the path may be different. If you followed the instructions [here](https://qso365.co.uk/2024/05/how-to-set-up-a-hamclock-for-your-shack/), then it will be installed in /usr/local/bin.

### Starting HamClock with OHB Central Install
```bash
hamclock -b \<central-server-ip-or-host\>:80
```
## Stopping OHB
### Web Server
```bash
sudo systemctl stop lighttpd
```
### Cron Jobs
#### Remove all jobs
```bash
sudo crontab -u www-data -l > ~/www-data.cron.backup
sudo crontab -u www-data -r
```
Note: Removing the cron jobs will stop all future background processes, not currently running. Ensure that the www-data.cron.backup actually was created before you remove all of www-data user's cronjobs

#### Restore all jobs
```bash
sudo crontab -u www-data /path/to/www-data.cron.backup
sudo crontab -u www-data -l | head
```

## Enabling OHB Dashboard
To enable OHB dashboard, it is a manual install while it is being developed. 

```bash
 sudo cp /opt/hamclock-backend/lighttpd-conf/51-ohb-dashboard.conf /etc/lighttpd/conf-enabled/
 sudo lighttpd -t -f /etc/lighttpd/lighttpd.conf
 sudo service lighttpd force-reload
 sudo -u www-data cp /opt/hamclock-backend/ham/dashboard/* /opt/hamclock-backend/htdocs
```
Ensure all scripts are owned by www-data under /opt/hamclock-backend/htdocs

## Project Completion Status

HamClock requests about 40+ artifacts. I have locally replicated all of them that I could find.

### Dynamic Text Files
- [x] Bz/Bz.txt
- [x] aurora/aurora.txt
- [x] xray/xray.txt
- [x] worldwx/wx.txt
- [x] esats/esats.txt
- [x] solarflux/solarflux-history.txt
- [x] ssn/ssn-history.txt
- [x] solar-flux/solarflux-99.txt
- [x] geomag/kindex.txt
- [x] dst/dst.txt
- [x] drap/stats.txt
- [x] solar-wind/swind-24hr.txt
- [x] ssn/ssn-31.txt
- [x] ONTA/onta.txt
- [x] contests/contests311.txt
- [x] dxpeds/dxpeditions.txt
- [x] NOAASpaceWX/noaaswx.txt
- [x] ham/HamClock/cty/cty_wt_mod-ll-dxcc.txt
      
### Dynamic Map Files
Note: Anything under maps/ is considered a "Core Map" in HamClock

- [x] maps/Clouds*
- [x] maps/Countries*
- [x] maps/Wx-mB*
- [x] maps/Aurora
- [x] maps/DRAP
- [x] maps/MUF-RT
- [x] maps/Terrain
- [x] SDO/*

### Dynamic Web Endpoints
- [x] ham/HamClock/RSS/web15rss.pl
- [x] ham/HamClock/version.pl
- [x] ham/HamClock/wx.pl
- [x] ham/HamClock/fetchIPGeoloc.pl - requires free tier 1000 req per day account and API key
- [x] ham/HamClock/fetchBandConditions.pl
- [ ] ham/HamClock/fetchVOACAPArea.pl
- [ ] ham/HamClock/fetchVOACAP-MUF.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=0.00&TOA=3.0&MODE=19&TOA=3.0
- [ ] ham/HamClock/fetchVOACAP-TOA.pl?YEAR=2026&MONTH=1&UTC=17&TXLAT=&TXLNG=&PATH=0&WATTS=100&WIDTH=660&HEIGHT=330&MHZ=14.10&TOA=3.0&MODE=19&TOA=3.0
- [x] ham/HamClock/fetchPSKReporter.pl?ofgrid=XXYY&maxage=1800
- [x] ham/HamClock/fetchWSPR.pl
- [ ] ham/HamClock/fetchRBN.pl

### Static Files
- [x] ham/HamClock/cities2.txt
- [x] ham/HamClock/NOAASpaceWx/rank2_coeffs.txt

## Integration Testing Status
- [x] GOES-16 X-Ray
- [x] Countries map download
- [x] Terrain map download
- [x] DRAP map generation, download, and display
- [x] SDO generation, download, and display
- [x] MUF-RT map generation, download, and display
- [x] Weather map generation, download, and display
- [x] Clouds map generation, download, and display
- [x] Aurora map generation, download, and display
- [x] Aurora map generation, download, and display
- [x] Parks on the Air generation, pull and display
- [x] SSN generation, pull, and display
- [x] Solar wind generation, pull and display
- [x] DRAP data generation, pull and display
- [x] Planetary Kp data generation, pull and display
- [x] Solar flux data generation, pull and display
- [x] Amateur Satellites data generation, pull and display
- [ ] PSK Reporter WSPR
- [X] VOACAP DE DX
- [ ] VOACAP MUF MAP
- [ ] RBN
