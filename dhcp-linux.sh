#!/usr/bin/env bash
# Menu independente: executar depois de gs-linux.sh da main.
set -Eeuo pipefail
export PATH="$PATH:/usr/sbin:/sbin"
valid_ip() {
    local ip=$1 part
    [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local -a parts; IFS=. read -ra parts <<< "$ip"
    for part in "${parts[@]}"; do ((10#$part <= 255)) || return 1; done
}
render() {
    cat <<CONF
# Laboratório FIAP: somente na interface de Rede Interna escolhida.
authoritative;
default-lease-time 1200;
max-lease-time 2400;
option host-name "$server_name";
subnet $prefix.0 netmask 255.255.255.0 {
    range $prefix.100 $prefix.199;
    option routers $prefix.1;
    option domain-name-servers $dns;
    option domain-name "$domain";
}
CONF
    if [[ -n $mac ]]; then
        cat <<CONF
host windows {
    hardware ethernet $mac;
    fixed-address $prefix.222;
    option domain-name "atribuicao.manual";
}
CONF
    fi
}
platform() {
    source /etc/os-release
    case "$ID:${VERSION_ID%%.*}" in
        debian:11|debian:12|debian:13) service=isc-dhcp-server; package=isc-dhcp-server; leases=/var/lib/dhcp/dhcpd.leases ;;
        rocky:8|rocky:9) service=dhcpd; package=dhcp-server; leases=/var/lib/dhcpd/dhcpd.leases ;;
        *) echo 'ISC DHCP deste laboratório: Debian 11–13 ou Rocky 8/9. Rocky 10 precisa de implementação Kea separada.'; return 1 ;;
    esac
}
configure() (
    [[ $EUID == 0 ]] || { echo 'Execute com sudo.'; exit 1; }
    platform
    ip -br -4 addr
    read -rp 'Interface conectada à Rede Interna: ' iface
    [[ $iface =~ ^[a-zA-Z0-9_.:-]+$ && -d /sys/class/net/$iface && $iface != lo ]] || { echo 'Interface inválida.'; exit 1; }
    if ip -4 route show default | grep -Eq "dev $iface( |$)"; then echo 'Escolha uma interface isolada, sem rota padrão.'; exit 1; fi
    read -rp 'IPv4 fixo desta interface: ' server_ip
    valid_ip "$server_ip" || exit 1
    ip -o -4 addr show dev "$iface" | awk '{print $4}' | grep -Fxq "$server_ip/24" || { echo 'Configure previamente esse IP com prefixo /24.'; exit 1; }
    prefix=${server_ip%.*}; last=${server_ip##*.}
    ((10#$last > 0 && 10#$last < 255 && (10#$last < 100 || 10#$last > 199) && 10#$last != 222)) || { echo 'IP do servidor conflita com pool/reserva ou rede/broadcast.'; exit 1; }
    read -rp 'IP do DNS configurado pela main: ' dns
    valid_ip "$dns" || exit 1
    read -rp 'Domínio DNS do laboratório (ex.: aluno.fiap): ' domain
    [[ ${#domain} -le 253 && $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $domain != *..* ]] || exit 1
    read -rp 'Hostname do servidor (letras, números e hífen): ' server_name
    [[ ${#server_name} -le 63 && $server_name =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || exit 1
    read -rp 'MAC do Windows para reserva .222 (Enter sem reserva): ' mac
    [[ -z $mac || $mac =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || exit 1
    render
    echo "Interface: $iface. Confirme no VirtualBox que as três VMs estão na mesma Rede Interna."
    echo 'O gateway .1 deve existir para fornecer roteamento. O DNS informado precisa ser acessível nessa rede.'
    read -rp 'Digite REDE INTERNA para aplicar: ' answer
    [[ $answer == 'REDE INTERNA' ]] || exit 0
    if [[ $ID == debian ]]; then apt-get update && apt-get install -y "$package"; else dnf install -y "$package"; fi
    candidate=$(mktemp); trap 'rm -f "$candidate"' EXIT
    render > "$candidate"
    dhcpd -t -cf "$candidate"
    backup=$(mktemp -d /var/backups/gs-dhcp.XXXXXXXX)
    conf=/etc/dhcp/dhcpd.conf
    dropdir=/etc/systemd/system/$service.service.d
    drop=$dropdir/gs-dhcp.conf
    had_conf=0; had_drop=0; active=0; enabled=0
    if [[ -f $conf ]]; then cp -a "$conf" "$backup/dhcpd.conf"; had_conf=1; fi
    if [[ -f $drop ]]; then cp -a "$drop" "$backup/drop.conf"; had_drop=1; fi
    systemctl is-active --quiet "$service" && active=1
    systemctl is-enabled --quiet "$service" && enabled=1
    rollback() {
        trap - ERR INT TERM
        if ((had_conf)); then cp -a "$backup/dhcpd.conf" "$conf"; else rm -f "$conf"; fi
        if ((had_drop)); then cp -a "$backup/drop.conf" "$drop"; else rm -f "$drop"; fi
        systemctl daemon-reload
        if ((enabled)); then systemctl enable "$service"; else systemctl disable "$service"; fi
        if ((active)); then systemctl restart "$service"; else systemctl stop "$service"; fi
        echo "Falha: restauração tentada. Backup: $backup" >&2
        exit 1
    }
    trap rollback ERR INT TERM
    install -D -m 644 "$candidate" "$conf"
    mkdir -p "$dropdir"
    cat > "$drop" <<UNIT
[Service]
Type=simple
PIDFile=
ExecStart=
ExecStart=/usr/sbin/dhcpd -4 -f -cf /etc/dhcp/dhcpd.conf $iface
UNIT
    if command -v restorecon >/dev/null; then restorecon "$conf" "$drop"; fi
    systemctl daemon-reload
    systemctl enable "$service"
    systemctl restart "$service"
    systemctl is-active --quiet "$service"
    trap - ERR INT TERM
    echo "Configuração aplicada. Backup: $backup"
    echo "Libere UDP/67 no firewall da interface $iface e teste uma concessão real. Serviço ativo não comprova DHCP funcionando."
    echo 'Windows: ipconfig /release e ipconfig /renew. Linux: cliente DHCP da distribuição.'
)
status() {
    platform || return
    systemctl status "$service" --no-pager || true
    journalctl -u "$service" -n 40 --no-pager || true
    [[ ! -r $leases ]] || tail -n 80 "$leases"
    echo 'Reservas fixed-address podem não aparecer no arquivo de leases; confira ipconfig /all no Windows.'
}
main() {
    while :; do
        printf '\nDHCP — atividade FIAP\n1) Instalar/configurar (inclui reserva opcional)\n2) Status, logs e concessões\n3) Roteiro da atividade\n0) Sair\n'
        read -rp '> ' choice || return 0
        case $choice in
            1) bash "${BASH_SOURCE[0]}" --configure || echo 'Configuração não concluída.' ;;
            2) status ;;
            3) echo 'Servidor com IP fixo /24; três VMs na mesma Rede Interna; pool .100–.199; leases 1200/2400; gateway .1; DNS/domínio da main; reserva Windows .222. Configure firewall UDP/67 na interface isolada e comprove nos clientes. Reexecute a opção 1 para acrescentar reserva, preenchendo novamente os mesmos dados.' ;;
            0) return ;; *) echo 'Opção inválida.' ;;
        esac
    done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    if [[ ${1:-} == --configure ]]; then configure; else main; fi
fi
