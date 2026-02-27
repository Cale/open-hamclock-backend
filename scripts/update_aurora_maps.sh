#!/bin/bash
set -e

export GMT_USERDIR=/opt/hamclock-backend/tmp
cd $GMT_USERDIR

source "/opt/hamclock-backend/scripts/lib_sizes.sh"
ohb_load_sizes   # populates SIZES=(...) per OHB conventions

JSON=ovation.json
XYZ=ovation.xyz

echo "Fetching OVATION..."
curl -fs https://services.swpc.noaa.gov/json/ovation_aurora_latest.json -o "$JSON"

# JSON -> XYZ in 0..360 longitude space for seamless polar gridding
# The aurora wraps around the poles so 0/360 avoids a seam in the grid.
# Rendering is done in -180/180 so HamClock city coordinates are correct.
python3 <<'EOF'
import json
d=json.load(open("ovation.json"))
with open("ovation.xyz","w") as f:
    for lon,lat,val in d["coordinates"]:
        if val <= 2:
            continue
        # keep lon in -180/180
        if lon > 180.0:
            lon -= 360.0
        f.write(f"{lon:.6f} {lat:.6f} {val:.6f}\n")
        # duplicate at both edges to avoid seam
        if lon == -180.0 or lon == 180.0:
            f.write(f"-180.000000 {lat:.6f} {val:.6f}\n")
            f.write(f"180.000000 {lat:.6f} {val:.6f}\n")
EOF

echo "Gridding aurora once..."

# nearneighbor with search radius of 3 degrees gives smooth edges
# without spreading data far from actual aurora locations.
# No grdfilter needed — avoids equatorial bleed entirely.
gmt nearneighbor "$XYZ" -R-180/180/-90/90 -I0.25 -S3 -Lx -Gaurora_raw.nc
gmt grdfilter aurora_raw.nc -Fg2 -D0 -Gaurora.nc
gmt grdclip aurora.nc -Sb1/NaN -Gaurora_clipped.nc

# Dynamically scale CPT to actual data max so bright neon always hits the peak
# Use at least 20 as floor so CPT thresholds don't collapse on quiet days
VMAX=$(gmt grdinfo aurora.nc -C | awk '{v=int($7); print (v>20)?v:20}')
echo "Aurora vmax: $VMAX"

V15=$(echo "$VMAX * 15 / 100" | bc)
V40=$(echo "$VMAX * 40 / 100" | bc)
V65=$(echo "$VMAX * 65 / 100" | bc)

cat > aurora.cpt <<EOF
0      0/0/0    1      0/0/0
1      0/20/0   $V15   0/80/0
$V15   0/80/0   $V40   0/160/0
$V40   0/160/0  $V65   0/220/0
$V65   0/220/0  $VMAX  1/251/0
EOF

# Write BMPv4 (BITMAPV4HEADER), 16bpp RGB565, top-down — matches ClearSkyInstitute format
make_bmp_v4_rgb565_topdown() {
  local inraw="$1" outbmp="$2" W="$3" H="$4"
  python3 - <<'PY' "$inraw" "$outbmp" "$W" "$H"
import struct, sys
inraw, outbmp, W, H = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])

raw = open(inraw, "rb").read()
exp = W*H*3
if len(raw) != exp:
    raise SystemExit(f"RAW size {len(raw)} != expected {exp}")

pix = bytearray(W*H*2)
j = 0
for i in range(0, len(raw), 3):
    r = raw[i]; g = raw[i+1]; b = raw[i+2]
    v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    pix[j:j+2] = struct.pack("<H", v)
    j += 2

bfOffBits = 14 + 108
bfSize = bfOffBits + len(pix)
filehdr = struct.pack("<2sIHHI", b"BM", bfSize, 0, 0, bfOffBits)

biSize = 108
rmask, gmask, bmask, amask = 0xF800, 0x07E0, 0x001F, 0x0000
cstype = 0x73524742  # sRGB
endpoints = b"\x00"*36
gamma = b"\x00"*12

v4hdr = struct.pack("<IiiHHIIIIII",
    biSize, W, -H, 1, 16, 3, len(pix), 0, 0, 0, 0
) + struct.pack("<IIII", rmask, gmask, bmask, amask) \
  + struct.pack("<I", cstype) + endpoints + gamma

with open(outbmp, "wb") as f:
    f.write(filehdr)
    f.write(v4hdr)
    f.write(pix)
PY
}

zlib_compress() {
  local in="$1" out="$2"
  python3 -c "
import zlib, sys
data = open(sys.argv[1], 'rb').read()
open(sys.argv[2], 'wb').write(zlib.compress(data, 9))
" "$in" "$out"
}

# ---------------------------------------------------------------------------
# ImageMagick 6: raised resource limits for very large maps (7920x3960 etc.)
# ---------------------------------------------------------------------------
export MAGICK_LIMIT_WIDTH=65536
export MAGICK_LIMIT_HEIGHT=65536
export MAGICK_LIMIT_AREA=4096MB
export MAGICK_LIMIT_MEMORY=2048MB
export MAGICK_LIMIT_MAP=4096MB
export MAGICK_LIMIT_DISK=8192MB

im_convert() {
  convert \
    -limit width    65536  \
    -limit height   65536  \
    -limit area     4096MB \
    -limit memory   2048MB \
    -limit map      4096MB \
    -limit disk     8192MB \
    "$@"
}

echo "Rendering maps..."

OUTDIR="/opt/hamclock-backend/htdocs/ham/HamClock/maps"
mkdir -p "$OUTDIR"

for DN in D N; do

for SZ in "${SIZES[@]}"; do
  BASE="$GMT_USERDIR/aurora_${DN}_${SZ}"
  BMP="$OUTDIR/map-${DN}-${SZ}-Aurora.bmp"

  W=${SZ%x*}
  H=${SZ#*x}

  # Points -> cm for PS_MEDIA (1pt = 2.54/72 cm)
  W_cm=$(awk "BEGIN{printf \"%.4f\", $W * 2.54 / 72}")
  H_cm=$(awk "BEGIN{printf \"%.4f\", $H * 2.54 / 72}")

  echo "  -> ${DN} ${SZ}"

  # Per-run gmt.conf: exact page size + zero origin so psconvert -A crops cleanly
  GMT_CONF="$GMT_USERDIR/gmtconf_aurora_${DN}_${SZ}"
  mkdir -p "$GMT_CONF"
  GMT_USERDIR="$GMT_CONF" gmt set \
    PS_MEDIA "${W_cm}cx${H_cm}c" \
    MAP_ORIGIN_X 0c \
    MAP_ORIGIN_Y 0c

  # ── Step 1: base land/sea fill ──────────────────────────────────────────
  PS_BASE="${BASE}_base.ps"
  PNG_BASE="${BASE}_base.png"
  (
    cd "$GMT_USERDIR" || exit 1
    if [[ "$DN" == "D" ]]; then
      LAND_COLOR="72/72/72"
      SEA_COLOR="72/72/72"
    else
      LAND_COLOR="0/0/0"
      SEA_COLOR="0/0/0"
    fi
    GMT_USERDIR="$GMT_CONF" \
    gmt pscoast \
      -R-180/180/-90/90 \
      -JX${W}p/${H}p \
      -X0 -Y0 \
      -G${LAND_COLOR} -S${SEA_COLOR} -A10000 \
      -P -K > "$PS_BASE" && \
    gmt psxy -R -J -T -O >> "$PS_BASE" && \
    GMT_USERDIR="$GMT_CONF" \
    gmt psconvert "$PS_BASE" -Tg -E72 "-A+s${W_cm}c/${H_cm}c" -F"${BASE}_base"
  ) || { echo "gmt base failed for ${DN} $SZ"; continue; }

  # ── Step 2: aurora grdimage at native size ──────────────────────────────
  PNG_AURORA="${BASE}_aurora.png"
  (
    cd "$GMT_USERDIR" || exit 1
    GMT_USERDIR="$GMT_CONF" \
    gmt pscoast \
      -R-180/180/-90/90 \
      -JX${W}p/${H}p \
      -X0 -Y0 \
      -G0/0/0 -S0/0/0 -A10000 \
      -P -K > "${BASE}_aur.ps"
    GMT_USERDIR="$GMT_CONF" \
    gmt grdimage aurora_clipped.nc \
      -R-180/180/-90/90 \
      -JX${W}p/${H}p \
      -Caurora.cpt -Q -n+b \
      -O -K >> "${BASE}_aur.ps"
    gmt psxy -R -J -T -O >> "${BASE}_aur.ps"
    GMT_USERDIR="$GMT_CONF" \
    gmt psconvert "${BASE}_aur.ps" -Tg -E72 "-A+s${W_cm}c/${H_cm}c" -F"${BASE}_aurora"
  ) || { echo "gmt aurora failed for ${DN} $SZ"; continue; }

  # ── Step 3: white coastlines/borders overlay ────────────────────────────
  PS_LINES="${BASE}_lines.ps"
  PNG_LINES="${BASE}_lines.png"
  (
    cd "$GMT_USERDIR" || exit 1
    GMT_USERDIR="$GMT_CONF" \
    gmt pscoast \
      -R-180/180/-90/90 \
      -JX${W}p/${H}p \
      -X0 -Y0 \
      -W0.75p,black -N1/0.5p,black -A10000 \
      -P -K > "$PS_LINES" && \
    gmt psxy -R -J -T -O >> "$PS_LINES" && \
    GMT_USERDIR="$GMT_CONF" \
    gmt psconvert "$PS_LINES" -Tg -E72 "-A+s${W_cm}c/${H_cm}c" -F"${BASE}_lines"
  ) || { echo "gmt lines failed for ${DN} $SZ"; continue; }

  # ── Step 4: composite: base + aurora (screen blend) + lines ────────────
  PNG_AURORA_TRANS="${BASE}_aurora_trans.png"
  PNG_COMP="${BASE}_comp.png"
  RAW="${BASE}.raw"

  # psconvert produces white-background PNGs.
  # Aurora: remove white bg -> coloured glow on transparent
  im_convert "$PNG_AURORA" -fuzz 5% -transparent white "$PNG_AURORA_TRANS" || \
    { echo "aurora transparency failed for $SZ"; continue; }

  # Lines were drawn in black on white bg.
  # Remove white bg -> black lines on transparent, then negate -> white lines on transparent.
  PNG_LINES_TRANS="${BASE}_lines_trans.png"
  im_convert "$PNG_LINES" -fuzz 8% -transparent white -negate "$PNG_LINES_TRANS" || \
    { echo "lines transparency failed for $SZ"; continue; }

  # Step 1: composite aurora over base
  PNG_STEP1="${BASE}_step1.png"
  im_convert "$PNG_BASE" "$PNG_AURORA_TRANS" -compose over -composite "$PNG_STEP1" || \
    { echo "aurora composite failed for $SZ"; continue; }

  # Step 2 (Day only): apply white haze AFTER aurora so aurora glows through it
  # Create a solid white PNG at map size with 45% opacity and composite over.
  PNG_STEP2="${BASE}_step2.png"
  if [[ "$DN" == "D" ]]; then
    PNG_HAZE="${BASE}_haze.png"
    im_convert -size "${W}x${H}" "xc:rgba(255,255,255,0.45)" "$PNG_HAZE" && \
    im_convert "$PNG_STEP1" "$PNG_HAZE" -compose over -composite "$PNG_STEP2" || \
      { echo "haze composite failed for $SZ"; continue; }
    rm -f "$PNG_HAZE"
  else
    cp "$PNG_STEP1" "$PNG_STEP2"
  fi

  # Step 3: composite white lines over result, resize to exact WxH
  im_convert "$PNG_STEP2" "$PNG_LINES_TRANS" -compose over -composite \
    -resize "${W}x${H}!" \
    "$PNG_COMP" || { echo "lines composite failed for $SZ"; continue; }

  im_convert "$PNG_COMP" RGB:"$RAW" || { echo "raw extract failed for $SZ"; continue; }
  make_bmp_v4_rgb565_topdown "$RAW" "$BMP" "$W" "$H" || { echo "bmp write failed for $SZ"; continue; }

  rm -f "$RAW" "$PNG_BASE" "$PNG_AURORA" "$PNG_AURORA_TRANS" \
        "$PNG_LINES" "$PNG_LINES_TRANS" "$PNG_STEP1" "$PNG_STEP2" "$PNG_COMP" \
        "${BASE}_base.ps" "${BASE}_aur.ps" "${BASE}_lines.ps"

  zlib_compress "$BMP" "${BMP}.z"
  chmod 0644 "$BMP" "${BMP}.z" 2>/dev/null || true

  echo "  -> Done: $BMP"

done

done

rm -f aurora_native.nc aurora_raw.nc aurora.nc aurora_clipped.nc aurora.cpt ovation.xyz

echo "Done."
