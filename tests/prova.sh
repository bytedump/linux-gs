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
# Reproduz a VM fornecida: Listen 81 no arquivo principal e outro Listen
# em conf.d. Garante uma única declaração 80 e restauração dos originais.
mkdir -p "$scratch/httpd/conf" "$scratch/httpd/conf.d"
printf 'Listen 81\nServerRoot /etc/httpd\n' > "$scratch/httpd/conf/httpd.conf"
printf '# configuração preexistente\nListen 127.0.0.1:8080\n' > "$scratch/httpd/conf.d/old.conf"
cp "$scratch/httpd/conf/httpd.conf" "$scratch/original-main"
cp "$scratch/httpd/conf.d/old.conf" "$scratch/original-extra"
BACKUP=$scratch/backup; mkdir -p "$BACKUP"
SAVED_PATHS=(); SAVED_EXISTS=()
WEB_CONF=$scratch/httpd/conf.d/00-gs-linux.conf
exam_normalize_http_listeners "$scratch/httpd"
render_web "$WEB_CONF"
[[ $(grep -RhEc '^[[:space:]]*Listen[[:space:]]+' "$scratch/httpd" | awk '{s+=$1}END{print s}') == 1 ]]
grep -Fxq 'Listen 80' "$WEB_CONF"
for file in "${SAVED_PATHS[@]}"; do cp -a "$BACKUP/files$file" "$file"; done
cmp "$scratch/original-main" "$scratch/httpd/conf/httpd.conf"
cmp "$scratch/original-extra" "$scratch/httpd/conf.d/old.conf"
echo 'Regressão Listen 81: porta 80 única e backups restauráveis passaram.'
