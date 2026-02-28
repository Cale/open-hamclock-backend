## Project Completion Status

HamClock requests about 40+ artifacts. I have locally replicated all of them that I could find.

### Dynamic Text Files
- [x] [Bz/Bz.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/bz_simple.py)
- [x] [aurora/aurora.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_aurora.sh)
- [x] [xray/xray.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/xray_simple.py)
- [x] [worldwx/wx.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/update_world_wx.pl)
- [x] [esats/esats.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/fetch_tle.sh)
- [x] [solarflux/solarflux-history.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_solarflux-history.sh)
- [x] [ssn/ssn-history.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_ssn_history.pl)
- [x] [solar-flux/solarflux-99.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/flux_simple.py)
- [x] [geomag/kindex.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/kindex_simple.py)
- [x] [dst/dst.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/dst_simple.py)
- [x] [drap/stats.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_drap.sh)
- [x] [solar-wind/swind-24hr.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/swind_simple.py)
- [x] [ssn/ssn-31.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/ssn_simple.py)
- [x] [ONTA/onta.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_onta.pl)
- [x] [contests/contests311.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_contest-calendar.sh)
- [x] [dxpeds/dxpeditions.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_dxpeditions_spots.py)
- [x] [NOAASpaceWX/noaaswx.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_noaaswx.sh)
- [x] [cty/cty_wt_mod-ll-dxcc.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/gen_cty_wt_mod.sh)
      
### Dynamic Map Files
Note: Anything under maps/ is considered a "Core Map" in HamClock

- [x] [maps/Clouds*](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/update_cloud_maps.sh)
- [x] maps/Countries* - reuse from CSI; no need to regenerate
- [x] [maps/Wx-mB*](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/update_wx_mb_maps.sh)
- [x] [maps/Wx-in*](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/update_wx_mb_maps.sh)
- [x] [maps/Aurora](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/update_aurora_maps.sh)
- [x] [maps/DRAP*](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/update_drap_maps.sh)
- [x] [maps/MUF-RT*](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/kc2g_muf_heatmap.sh)
- [x] maps/Terrain* - reuse from CSI; no need to regenerate
- [x] [SDO/*](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/update_all_sdo.sh)

### Dynamic Web Endpoints
- [x] [ham/HamClock/RSS/web15rss.pl](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/RSS/web15rss.pl) and this [job](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/web15rss_fetch.py) makes the file
- [x] [ham/HamClock/version.pl](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/version.pl)
- [x] [ham/HamClock/wx.pl](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/wx.pl)
- [x] [ham/HamClock/fetchIPGeoloc.pl](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/fetchIPGeoloc.pl) - requires free tier 1000 req per day account and API key
- [ ] ham/HamClock/fetchBandConditions.pl - implemented however bypassed via proxied
- [ ] ham/HamClock/fetchVOACAPArea.pl - proxied by CSI until we can work out complex task
- [ ] ham/HamClock/fetchVOACAP-MUF.pl - proxied by CSI until we can work out complex task
- [ ] ham/HamClock/fetchVOACAP-TOA.pl - proxied by CSI until we can work out complex task
- [ ] [ham/HamClock/fetchPSKReporter.pl](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/fetchPSKReporter.pl) - currently proxied, it is implemented however it will be subject to rate limiting if deployed centrally. I have created a PSK Reporter proxy as of last week (https://github.com/BrianWilkinsFL/ohb-pskreporter-proxy) and this requires careful integration testing to ensure it works before I am willing to release it into production
- [x] [ham/HamClock/fetchWSPR.pl](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/fetchWSPR.pl)
- [x] [ham/HamClock/fetchRBN.pl](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/fetchRBN.pl)

### Static Files
- [x] [ham/HamClock/cities2.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/cities2.txt) - we did not update this file as it appears to require no change
- [x] [ham/HamClock/NOAASpaceWx/rank2_coeffs.txt](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/ham/HamClock/NOAASpaceWX/rank2_coeffs.txt) - we did not update this file as it appears to require no change

## Integration Testing Status
- [x] GOES-16 X-Ray
- [x] Countries map download and display (all sizes)
- [x] Terrain map download and display (all sizes)
- [x] SDO generation, download, and display
- [x] MUF-RT map generation, download, and display (all sizes)
- [x] Weather map generation, download, and display (all sizes in mB and in)
- [x] Clouds map generation, download, and display (all sizes)
- [x] Aurora map generation, download, and display (all sizes)
- [x] POTA, SOTA, WWFF generation, pull and display
- [x] SSN + history generation, pull, and display
- [x] Solar wind generation, pull and display
- [x] DRAP data generation, pull and display
- [x] Planetary Kp data generation, pull and display
- [x] Solar flux + history data generation, pull and display
- [x] Amateur Satellites data generation, pull and display + [active AMSAT status satellite filter](https://github.com/BrianWilkinsFL/open-hamclock-backend/blob/main/scripts/filter_amsat_active.pl)
- [x] PSK Reporter WSPR request and display
- [x] PSK Reporter Spots request and display - proxied
- [ ] PSK Reporter Spots - non proxied
- [X] VOACAP DE DX - proxied
- [ ] VOACAP DE DX - non proxied
- [x] VOACAP MUF MAP (REL/TOA) - proxied
- [ ] VOACAP MUF MAP (REL/TOA) - non proxied
- [x] RBN request and display
