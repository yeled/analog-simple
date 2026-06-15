#!/usr/bin/env bash
#
# Stamp manifest.xml for a build target. The dev branches and the public
# branch differ in manifest.xml in exactly two ways — the Garmin app UUID and
# the supported device list — which is what makes beta->public merges
# conflict. This script regenerates manifest.xml for the chosen target so you
# never hand-merge it:
#
#   scripts/set-manifest.sh beta     # beta app id, single device (fast dev)
#   scripts/set-manifest.sh public   # public app id, full store device list
#
# Everything else (permissions, languages, min SDK) is identical and lives
# here as the single source of truth.
set -euo pipefail

cd "$(dirname "$0")/.."

BETA_ID="b3a1e6c2-4f8d-4a2b-9c3e-7d6f5a8b9c12"
PUBLIC_ID="88c61d1d-1f9a-4748-b732-02445464f28f"

# Beta builds only target the Venu 4 we test on; the public app ships the
# full family.
BETA_PRODUCTS="venu441mm venu445mm"
PUBLIC_PRODUCTS="\
approachs50 approachs7042mm approachs7047mm d2airx10 d2mach1 d2mach2 \
d2mach2pro descentg2 descentmk343mm descentmk351mm enduro3 epix2 epix2pro42mm \
epix2pro47mm epix2pro51mm fenix7 fenix7pro fenix7pronowifi fenix7s fenix7spro \
fenix7x fenix7xpro fenix7xpronowifi fenix843mm fenix847mm fenix8pro47mm \
fenix8solar47mm fenix8solar51mm fenixe fr165 fr165m fr255 fr255m fr255s \
fr255sm fr265 fr265s fr57042mm fr57047mm fr955 fr965 fr970 \
instinct3amoled45mm instinct3amoled50mm instinct3solar45mm \
instinctcrossoveramoled instincte40mm instincte45mm marq2 marq2aviator venu2 \
venu2plus venu2s venu3 venu3s venu441mm venu445mm venusq2 venusq2m venux1 \
vivoactive5 vivoactive6"

case "${1:-}" in
  beta)   APP_ID="$BETA_ID";   PRODUCTS="$BETA_PRODUCTS" ;;
  public) APP_ID="$PUBLIC_ID"; PRODUCTS="$PUBLIC_PRODUCTS" ;;
  *) echo "usage: $0 {beta|public}" >&2; exit 2 ;;
esac

products_xml=""
for p in $PRODUCTS; do
  products_xml+="            <iq:product id=\"$p\"/>"$'\n'
done

cat > manifest.xml <<EOF
<?xml version="1.0"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
    <iq:application id="$APP_ID" type="watchface" name="@Strings.AppName" entry="AnalogSimpleApp" launcherIcon="@Drawables.LauncherIcon" minSdkVersion="4.2.0">
        <iq:products>
${products_xml}        </iq:products>
        <iq:permissions>
            <iq:uses-permission id="Background"/>
            <iq:uses-permission id="Communications"/>
            <iq:uses-permission id="Positioning"/>
            <iq:uses-permission id="SensorHistory"/>
        </iq:permissions>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
        <iq:barrels/>
    </iq:application>
</iq:manifest>
EOF

count=$(echo "$PRODUCTS" | wc -w | tr -d ' ')
echo "manifest.xml -> $1 (id=$APP_ID, $count product(s))"
