#!/usr/bin/env bash
# Somente em contêiner DESCARTÁVEL e como root: altera /etc e inicia daemons reais.
# Valida os pacotes, arquivos, template, DNS e HTTP. Não simula uma VM com systemd.
set -Eeuo pipefail
[[ ${GS_DISPOSABLE_CONTAINER:-} == yes && -f /.dockerenv && $EUID == 0 ]] || {
    echo 'Este teste só pode rodar em um contêiner descartável com GS_DISPOSABLE_CONTAINER=yes.' >&2; exit 1;
}
cd /repo
source ./gs-linux.sh
detect_platform
WORK=$(mktemp -d)
LOG=$WORK/install.log
trap 'rm -rf "$WORK"' EXIT
install_packages
DOMAIN=empresa.test
SERVER_IP=$(detect_ip)
valid_ipv4 "$SERVER_IP"
base_records
add_record mail A "$SERVER_IP"
add_record @ MX mail.empresa.test 10
add_record correio CNAME mail.empresa.test
add_record @ TXT 'GS "Linux" e \ teste'
download_template
apply_configuration
named -g -n 1 -U 1 -u "$DNS_GROUP" -c "$DNS_CONF" >"$WORK/named.log" 2>&1 &
named_pid=$!
if [[ $PLATFORM == debian ]]; then apache2ctl start; else httpd -k start; fi
# Aqui não há systemd: a verificação de processo usa o daemon real iniciado acima.
systemctl() {
    [[ $1 == is-active && $2 == --quiet ]] || return 1
    if [[ $3 == named ]]; then kill -0 "$named_pid"; else pgrep -x "$WEB_SERVICE" >/dev/null; fi
}
for _attempt in {1..20}; do
    if dig @"$SERVER_IP" "$DOMAIN" A +short +time=1 +tries=1 2>/dev/null | grep -Fxq "$SERVER_IP"; then break; fi
    sleep 0.25
done
verify_services
install -d -m 700 "$STATE_DIR"
save_state
load_state
verify_services

# Segunda aplicação: configurações continuam válidas e serial avança.
old_serial=$(awk '/; serial:/ {print $1}' "$ZONE_FILE")
apply_configuration
new_serial=$(awk '/; serial:/ {print $1}' "$ZONE_FILE")
(( new_serial > old_serial ))
kill "$named_pid"
wait "$named_pid" || true
named -g -n 1 -U 1 -u "$DNS_GROUP" -c "$DNS_CONF" >"$WORK/named.log" 2>&1 &
named_pid=$!
if [[ $PLATFORM == debian ]]; then apache2ctl graceful; else httpd -k graceful; fi
for _attempt in {1..20}; do
    if dig @"$SERVER_IP" "$DOMAIN" A +short +time=1 +tries=1 2>/dev/null | grep -Fxq "$SERVER_IP"; then break; fi
    sleep 0.25
done
verify_services
echo "INTEGRAÇÃO $PLATFORM: PASSOU (BIND/Apache reais, template, registros, reaplicação)."
