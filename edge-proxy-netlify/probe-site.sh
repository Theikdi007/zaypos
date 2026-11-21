# Probe the deployed proxy from a phone (adb), VPN off. Usage:
#   adb push probe-site.sh /data/local/tmp/ && adb shell sh /data/local/tmp/probe-site.sh https://<name>.netlify.app
# Prints only status, masked IP (two octets) and timings. Sends no token, no secret.
SITE=${1:?usage: probe-site.sh https://<name>.netlify.app}
CURL=${CURL:-curl}
mask() { sed -E 's/([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+/\1.\2.x.x/g'; }
one() {
  out=$($CURL -sS -o /dev/null -m 40 --connect-timeout 8 "$@" \
        -w '%{http_code} %{remote_ip} connect=%{time_connect} tls=%{time_appconnect} total=%{time_total}' 2>&1)
  rc=$?; [ $rc -eq 0 ] && echo "OK $out" || echo "FAIL rc=$rc $(echo "$out" | tr '\n' ' ' | cut -c1-110)"
}
echo "== $(date '+%m-%d %H:%M') $(getprop gsm.operator.alpha 2>/dev/null) =="
ip route 2>/dev/null | grep -oE 'dev [a-z0-9_]+' | sort -u | tr '\n' ' '; echo
for i in 1 2 3; do echo "proxy-own-health  | $(one "$SITE/_proxy/health")" | mask; done
for i in 1 2 3; do echo "api-health-via-proxy | $(one "$SITE/health")" | mask; done
echo "api-401-via-proxy (expect 401) | $(one -X POST -H 'content-type: application/json' -d '{}' "$SITE/api/v1/sync/push")" | mask
# Body size: Netlify's limit is not documented. 405/404/401 = reached the API; 413 = refused by Netlify or the proxy.
for mb in 1 10 30; do
  echo "post-${mb}MB | $(head -c $((mb * 1048576)) /dev/zero | one -X POST -H 'content-type: application/octet-stream' --data-binary @- "$SITE/health")" | mask
done
echo "post-33MB (expect 413) | $(head -c 34603008 /dev/zero | one -X POST --data-binary @- "$SITE/health")" | mask
echo "control-direct-api | $(one https://api.zaypos.app/health)" | mask
echo "== done =="
