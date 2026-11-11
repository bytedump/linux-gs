#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source ./gs-prova.sh
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
DOMAIN=vladmir.lab; SERVER_IP=192.168.56.10; PRIMARY_IP=$SERVER_IP
SECONDARY_IP=''; WEB_IP=$SERVER_IP; DNS_ROLE=primary
select_platform rocky 9
set_reverse_network 192.168.56.0/24; set_zone_paths; base_records
render_named "$scratch/named.conf"
render_web "$scratch/http.conf"
render_zone "$scratch/zone" 2026111100
grep -Fq 'allow-transfer { none; };' "$scratch/named.conf"
! grep -q 'also-notify' "$scratch/named.conf"
grep -Fq 'recursion no;' "$scratch/named.conf"
grep -Fq 'ServerTokens Prod' "$scratch/http.conf"
grep -Fq 'ServerSignature Off' "$scratch/http.conf"
grep -Fq 'www IN A 192.168.56.10' "$scratch/zone"
! use_local_template
# Validação final com respostas de serviços simuladas; cada falha deve bloquear.
cat > "$scratch/verify.sh" <<'CHILD'
set -Eeuo pipefail
source ./gs-prova.sh
DNS_CONF=$1; EXAM_NEW_UUID=fake; SERVER_IP=192.168.56.10; DOMAIN=vladmir.lab; TEMPLATE_SOURCE=internet
nmcli() { echo manual; }
systemctl() { return 0; }
dig() { echo 'Transfer failed.'; }
curl() { printf 'HTTP/1.1 200 OK\r\nServer: Apache\r\n\r\n'; }
case $2 in
 version) curl() { printf 'Server: Apache/2.4.0\r\n'; } ;;
 transfer) dig() { echo 'XFR size: 10 records'; } ;;
 boot) systemctl() { return 1; } ;;
 dynamic) nmcli() { echo auto; } ;;
 local) TEMPLATE_SOURCE=local ;;
esac
exam_verify_final
echo REBOOT_ALLOWED
CHILD
bash "$scratch/verify.sh" "$scratch/named.conf" ok > "$scratch/out"
grep -q REBOOT_ALLOWED "$scratch/out"
for failure in version transfer boot dynamic local; do
 if bash "$scratch/verify.sh" "$scratch/named.conf" "$failure" > "$scratch/out" 2>&1; then echo "Falha não detectada: $failure"; exit 1; fi
 ! grep -q REBOOT_ALLOWED "$scratch/out"
done
echo 'GS: configuração DNS/Web e bloqueio de conclusão em 5 falhas passaram.'
