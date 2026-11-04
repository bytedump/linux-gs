#!/usr/bin/env bash
# Teste com dois contêineres DESCARTÁVEIS na mesma rede /24. Altera /etc e inicia daemons.
# Dentro de /repo: bash tests/dns-transfer.sh init primary IP-SECUNDARIO
# Na outra VM de teste: bash tests/dns-transfer.sh init secondary IP-PRIMARIO
# Depois: check nas duas, update no primário e check-update no secundário.
# Não executar em VM de trabalho. O runner Docker está descrito no README.
set -Eeuo pipefail
[[ ${GS_DISPOSABLE_CONTAINER:-} == yes && -f /.dockerenv && $EUID == 0 ]] || {
    echo 'Exige contêiner descartável e GS_DISPOSABLE_CONTAINER=yes.' >&2; exit 1;
}
cd /repo
source ./gs-linux.sh
detect_platform
WORK=$(mktemp -d)
LOG=$WORK/test.log
trap 'rm -rf "$WORK"' EXIT
action=${1:-}

# Apenas substitui systemd, que não roda nesses contêineres. Os daemons são reais.
systemctl() {
    [[ $1 == is-active && $2 == --quiet ]] || return 1
    if [[ $3 == named ]]; then kill -0 "$(cat /tmp/gs-named.pid)"
    else pgrep -x "$WEB_SERVICE" >/dev/null; fi
}

case $action in
    init)
        DNS_ROLE=${2:?Falta o papel}; peer=${3:?Falta o IP do outro servidor}
        valid_server_ip "$peer"
        DOMAIN=aluno.fiap
        SERVER_IP=$(detect_ip)
        valid_server_ip "$SERVER_IP"
        if [[ $DNS_ROLE == primary ]]; then
            PRIMARY_IP=$SERVER_IP; SECONDARY_IP=$peer; WEB_IP=$peer; base_records
        elif [[ $DNS_ROLE == secondary ]]; then
            PRIMARY_IP=$peer; SECONDARY_IP=$SERVER_IP; WEB_IP=$SERVER_IP
        else exit 1; fi
        set_reverse_network "${PRIMARY_IP%.*}.0/24"
        set_zone_paths
        download_template
        apply_configuration
        install -d -m 700 "$STATE_DIR"
        save_state
        nohup named -g -n 1 -U 1 -u "$DNS_GROUP" -c "$DNS_CONF" >/tmp/gs-named.log 2>&1 </dev/null &
        echo "$!" >/tmp/gs-named.pid
        if [[ $PLATFORM == debian ]]; then apache2ctl start; else httpd -k start; fi
        ;;
    check)
        load_state
        wait_secondary_transfer
        verify_services
        report_lab_dns
        (( REPORT_FAIL == 0 ))
        if [[ $DNS_ROLE == secondary ]]; then
            for zone in "$DOMAIN" "$REVERSE_ZONE"; do
                dig -b "$SERVER_IP" @"$PRIMARY_IP" "$zone" AXFR +time=2 +tries=1 >"$WORK/axfr"
                grep -Fq 'XFR size:' "$WORK/axfr"
            done
            ok 'AXFR direto e reverso permitidos para o IP autorizado.'
        else
            dig -b "$SERVER_IP" @"$SERVER_IP" "$DOMAIN" AXFR +time=2 +tries=1 >"$WORK/refused"
            grep -Fq 'Transfer failed.' "$WORK/refused"
            ok 'AXFR recusado para outro IP, mesmo sendo o próprio primário.'
        fi
        headers=$(curl --noproxy '*' -fsSI "http://$SERVER_IP/")
        grep -Fxq 'Server: Apache' <<<"${headers//$'\r'/}"
        ok 'Apache não expõe versão no cabeçalho HTTP.'
        ;;
    update)
        load_state
        [[ $DNS_ROLE == primary ]]
        old_serial=$(dig @"$SERVER_IP" "$DOMAIN" SOA +short | awk '{print $3}')
        add_record webmail A 10.200.200.200
        add_record reserva A "$REVERSE_PREFIX.200"
        cp -a "$WEB_ROOT" "$WORK/site"
        apply_configuration
        save_state
        new_serial=$(awk '/; serial:/ {print $1}' "$ZONE_FILE")
        (( new_serial > old_serial ))
        kill -HUP "$(cat /tmp/gs-named.pid)"
        ok "Serial avançou de $old_serial para $new_serial; recarga enviada ao BIND."
        ;;
    check-update)
        load_state
        [[ $DNS_ROLE == secondary ]]
        # Aguarda o NOTIFY e a transferência da nova versão, não apenas o SOA inicial.
        copied=0
        for _attempt in {1..30}; do
            answer=$(dig @"$SERVER_IP" "webmail.$DOMAIN" A +short +time=1 +tries=1) || answer=''
            if [[ $answer == 10.200.200.200 ]]; then copied=1; break; fi
            sleep 1
        done
        (( copied ))
        wait_secondary_transfer
        verify_dns "webmail.$DOMAIN" A 10.200.200.200
        answer=$(dig @"$SERVER_IP" -x "$REVERSE_PREFIX.200" +short)
        [[ $answer == "reserva.$DOMAIN." ]]
        report_lab_dns
        (( REPORT_FAIL == 0 ))
        ok 'Novo A e novo PTR chegaram ao secundário; SOAs das duas zonas coincidem.'
        ;;
    *) echo 'Use init primary|secondary IP-PEER, check, update ou check-update.' >&2; exit 1 ;;
esac
