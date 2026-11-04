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
DOMAIN=aluno.fiap
SERVER_IP=$(detect_ip)
valid_ipv4 "$SERVER_IP"
PRIMARY_IP=$SERVER_IP
WEB_IP=$SERVER_IP
set_reverse_network "${SERVER_IP%.*}.0/24"
set_zone_paths
base_records
add_record mail A "$SERVER_IP"
add_record @ MX mail.aluno.fiap 10
add_record correio CNAME mail.aluno.fiap
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
panel_result=0
evidence_panel >"$WORK/panel.txt" || panel_result=$?
cat "$WORK/panel.txt"
# O contêiner não tem systemd/firewall gerenciado: o resultado deve ser PARCIAL,
# mas consultas DNS/HTTP reais, portas e configurações precisam passar.
[[ $panel_result == 2 && $REPORT_FAIL == 0 ]]
grep -Fq '[OK] SOA autoritativo por TCP' "$WORK/panel.txt"
grep -Fq '[OK] HTML servido corresponde ao template instalado' "$WORK/panel.txt"
# Exercita os ramos de inspeção de firewall como root, com comandos simulados
# apenas neste subshell. Não altera regras do host nem do contêiner.
(
    REPORT_OK=0 REPORT_FAIL=0 REPORT_UNKNOWN=0
    ip() { printf '2: eth0 inet %s/24 scope global eth0\n' "$SERVER_IP"; }
    # shellcheck disable=SC2317 # Invocada indiretamente pelo painel.
    firewall-cmd() {
        case "$*" in
            --state) echo running ;;
            --get-active-zones) echo public ;;
            --get-zone-of-interface=eth0) echo public ;;
            '--zone=public --query-service=http') echo no; return 1 ;;
            *--query-service=*) echo yes ;;
            --info-service=*) echo 'ports: 53/tcp 53/udp 80/tcp' ;;
            *) echo 'Comando inesperado no teste'; return 99 ;;
        esac
    }
    report_firewall >"$WORK/firewalld-probe.txt"
    [[ $REPORT_FAIL == 1 ]]
    grep -Fq '[FALHA] http permitido agora' "$WORK/firewalld-probe.txt"
    grep -Fq '[OK] http salvo permanentemente' "$WORK/firewalld-probe.txt"
    # shellcheck disable=SC2317 # Invocada indiretamente pelo painel.
    firewall-cmd() { echo 'FirewallD is not running'; return 252; }
    # shellcheck disable=SC2317 # Invocada indiretamente pelo painel.
    ufw() {
        [[ $* == 'status verbose' ]] || return 99
        printf 'Status: active\n%s 53/udp ALLOW IN Anywhere\n53/tcp ALLOW IN Anywhere\n80/tcp DENY IN Anywhere\n' "$SERVER_IP"
    }
    REPORT_OK=0 REPORT_FAIL=0 REPORT_UNKNOWN=0
    report_firewall >"$WORK/ufw-probe.txt"
    [[ $REPORT_UNKNOWN == 1 && $REPORT_FAIL == 0 ]]
    grep -Fq '[OK] Regra UFW permite 53/udp' "$WORK/ufw-probe.txt"
    grep -Fq '[NÃO VERIFICADO] Permissão UFW para 80/tcp' "$WORK/ufw-probe.txt"
)
if [[ $PLATFORM == debian ]]; then apache2ctl stop; else httpd -k stop; fi
for _attempt in {1..20}; do
    if ! curl --noproxy '*' -fsS --max-time 1 "http://$SERVER_IP/" >/dev/null 2>&1; then break; fi
    sleep 0.25
done
panel_result=0
evidence_panel >"$WORK/panel-stopped.txt" || panel_result=$?
[[ $panel_result == 1 ]]
grep -Fq '[FALHA] Página de identificação por IP' "$WORK/panel-stopped.txt"
grep -Fq '[OK] SOA autoritativo por TCP' "$WORK/panel-stopped.txt"
grep -Fq 'RESULTADO E COMO APRESENTAR' "$WORK/panel-stopped.txt"
echo "INTEGRAÇÃO $PLATFORM: PASSOU (BIND/Apache reais, template, reaplicação, painel, Apache parado; inspeções de firewall simuladas)."
