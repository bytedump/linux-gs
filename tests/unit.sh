#!/usr/bin/env bash
# Testes sem root, sem rede e sem modificar arquivos do sistema.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source ./gs-linux.sh
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT
count=0
pass() { count=$((count+1)); printf 'ok %s - %s\n' "$count" "$1"; }
accept() { local label=$1; shift; "$@" >/dev/null || { echo "FALHOU: $label"; exit 1; }; pass "$label"; }
reject() { local label=$1; shift; if "$@" >/dev/null; then echo "FALHOU: $label"; exit 1; fi; pass "$label"; }

accept 'IPv4 válido' valid_ipv4 192.168.56.10
accept 'Octetos de borda' valid_ipv4 0.255.0.255
for bad in 256.1.1.1 01.2.3.4 1.2.3 1.2.3.4.5 '1.2.3.4;id' 9999999999999999999999.1.1.1; do reject "IPv4 recusado: $bad" valid_ipv4 "$bad"; done
accept 'Domínio válido' valid_domain empresa.test
# SC2016: a expressão maliciosa precisa permanecer literal para testar a rejeição.
# shellcheck disable=SC2016
for bad in localhost 1.2.3.4 '-empresa.test' 'empresa-.test' 'empresa..test' '$(touch /tmp/gs-injection).test' 'empresa.test;id' 'empresa.test/abc'; do reject "Domínio recusado: $bad" valid_domain "$bad"; done
DOMAIN=empresa.test
accept 'TXT com sublinhado' valid_owner _dmarc TXT
reject 'A com sublinhado' valid_owner _dmarc A
accept 'Prioridade mínima' valid_priority 0
accept 'Prioridade máxima' valid_priority 65535
reject 'Prioridade acima do limite' valid_priority 65536
reject 'Prioridade maliciosa' valid_priority '1+2'
accept 'TXT com aspas e barra' valid_txt 'texto "aspas" e \ barra'
reject 'TXT com quebra de linha' valid_txt $'a\nb'
reject 'TXT vazio' valid_txt ''

SERVER_IP=192.168.56.10
base_records
reject 'Registro duplicado' add_record @ A "$SERVER_IP"
reject 'CNAME não pode coexistir com A' add_record @ CNAME "$DOMAIN"
reject 'A não pode coexistir com CNAME' add_record intranet A "$SERVER_IP"
reject 'CNAME não aponta para si mesmo' add_record loop CNAME loop.empresa.test
reject 'MX com destino inexistente' add_record @ MX mail.empresa.test 10
accept 'A para o destino do MX' add_record mail A 192.168.56.20
accept 'MX com destino existente' add_record @ MX mail.empresa.test 10
accept 'Apelido para um A existente' add_record correio CNAME mail.empresa.test
accept 'TXT de exemplo' add_record @ TXT 'texto "aspas" e \ barra'
render_zone "$TEST_DIR/zone" 123
accept 'MX termina em ponto (não duplica domínio)' grep -Fxq '@ IN MX 10 mail.empresa.test.' "$TEST_DIR/zone"
accept 'TXT escapa aspas e barras' grep -Fxq '@ IN TXT "texto \"aspas\" e \\ barra"' "$TEST_DIR/zone"

for version in 11 12 13; do
    accept "Debian $version reconhecido" select_platform debian "$version"
    [[ $DNS_CONF == /etc/bind/named.conf && $WEB_SERVICE == apache2 ]] || exit 1
done
for version in 8.10 9.7 10; do
    accept "Rocky $version reconhecido" select_platform rocky "$version"
    [[ $DNS_CONF == /etc/named.conf && $WEB_SERVICE == httpd ]] || exit 1
done
reject 'Distribuição desconhecida não recebe comandos incorretos' select_platform fedora 43
render_named "$TEST_DIR/named.conf"
accept 'Recursão DNS pública desativada' grep -Fq 'recursion no;' "$TEST_DIR/named.conf"
accept 'Transferências de zona bloqueadas' grep -Fq 'allow-transfer { none; };' "$TEST_DIR/named.conf"

STATE_DIR=$TEST_DIR/state-dir
mkdir "$STATE_DIR"
save_state
before=$(declare -p REC_NAME REC_TYPE REC_VALUE REC_PRIORITY)
REC_NAME=(); REC_TYPE=(); REC_VALUE=(); REC_PRIORITY=()
load_state
[[ $(declare -p REC_NAME REC_TYPE REC_VALUE REC_PRIORITY) == "$before" ]] || { echo 'Estado salvo perdeu registros'; exit 1; }
pass 'Estado preserva todos os registros, incluindo TXT com espaços'

# Recuperação usa arquivos temporários e simula somente comandos externos.
BACKUP=$TEST_DIR/backup
mkdir "$BACKUP"
LOG=$TEST_DIR/log
SAVED_PATHS=(); SAVED_EXISTS=(); FW_ADDED=()
printf 'original\n' >"$TEST_DIR/original"
backup_path "$TEST_DIR/original"
backup_path "$TEST_DIR/novo"
printf 'alterado\n' >"$TEST_DIR/original"
printf 'novo\n' >"$TEST_DIR/novo"
systemctl() { return 0; }
restorecon() { return 0; }
rollback >"$LOG" 2>&1
[[ $(cat "$TEST_DIR/original") == original && ! -e $TEST_DIR/novo ]] || { echo 'Rollback falhou'; exit 1; }
pass 'Rollback restaura arquivo anterior e remove arquivo novo'

# Exercita regras preexistentes e reaplicação, sem tocar no firewall da máquina.
firewall_state=$TEST_DIR/firewall
printf 'runtime:dns\npermanent:dns\n' >"$firewall_state"
systemctl() { [[ $1 == is-active && $3 == firewalld ]]; }
ip() { printf '2: eth0 inet 192.168.56.10/24 scope global eth0\n'; }
firewall-cmd() {
    local kind=runtime action='' service='' arg
    for arg in "$@"; do
        case $arg in
            --get-zone-of-interface=*) echo public; return ;;
            --permanent) kind=permanent ;;
            --query-service=*) action=query; service=${arg#*=} ;;
            --add-service=*) action=add; service=${arg#*=} ;;
            --remove-service=*) action=remove; service=${arg#*=} ;;
        esac
    done
    case $action in
        query) grep -Fxq "$kind:$service" "$firewall_state" ;;
        add) printf '%s:%s\n' "$kind" "$service" >>"$firewall_state" ;;
        remove) sed -i "/^$kind:$service\$/d" "$firewall_state" ;;
        *) return 1 ;;
    esac
}
FW_ADDED=()
configure_firewall >"$LOG" 2>&1
[[ ${#FW_ADDED[@]} == 2 ]] || { echo 'Não preservou permissões preexistentes'; exit 1; }
configure_firewall >>"$LOG" 2>&1
[[ ${#FW_ADDED[@]} == 2 && $(wc -l <"$firewall_state") == 4 ]] || { echo 'Duplicou regras na reaplicação'; exit 1; }
pass 'Firewalld preserva DNS existente e não duplica permissões'
systemctl() { return 0; }
rollback >>"$LOG" 2>&1
[[ $(cat "$firewall_state") == $'runtime:dns\npermanent:dns' ]] || { echo 'Rollback apagou regra anterior'; exit 1; }
pass 'Rollback do firewalld remove somente as permissões adicionadas'

systemctl() { return 1; }
ufw_calls=$TEST_DIR/ufw-calls
ufw() {
    if [[ $1 == status ]]; then
        printf 'Status: active\n192.168.56.10 53/udp ALLOW Anywhere\n80/tcp (v6) ALLOW Anywhere (v6)\n'
    else printf '%s\n' "$*" >>"$ufw_calls"; fi
}
FW_ADDED=()
configure_firewall >>"$LOG" 2>&1
[[ ${#FW_ADDED[@]} == 2 ]] || { echo 'UFW não reconheceu regra existente'; exit 1; }
accept 'UFW libera apenas o IPv4 selecionado' grep -Fxq 'insert 1 allow to 192.168.56.10 port 80 proto tcp' "$ufw_calls"
systemctl() { return 0; }
rollback >>"$LOG" 2>&1
accept 'Rollback UFW usa o mesmo destino, preservando regras IPv6' grep -Fxq -- '--force delete allow to 192.168.56.10 port 80 proto tcp' "$ufw_calls"

# Retira as simulações; a demo abaixo executa um processo Bash novo.
unset -f systemctl restorecon firewall-cmd ip ufw

# Entrada inválida deve pedir correção; a demo não pede root nem instala pacotes.
printf 'dominio-invalido\naluno.fiap\n1\n999.1.1.1\n192.168.56.10\n0\n\n9\n0\ns\n' | bash ./gs-linux.sh --demo >"$TEST_DIR/demo"
accept 'Demo rejeita domínio incorreto' grep -Fq 'Exemplo válido' "$TEST_DIR/demo"
accept 'Demo rejeita IP incorreto' grep -Fq 'Informe o IP' "$TEST_DIR/demo"
accept 'Demo rejeita opção inexistente' grep -Fq 'Escolha uma opção' "$TEST_DIR/demo"
accept 'Demo termina com sucesso' grep -Fq 'Demonstração concluída' "$TEST_DIR/demo"
if printf 'aluno.fiap\n1\n192.168.56.10\n0\n\n0\n' | bash ./gs-linux.sh --demo >"$TEST_DIR/eof" 2>&1; then echo 'EOF deveria interromper'; exit 1; fi
pass 'Entrada encerrada não entra em loop nem instala'
printf 'aluno.fiap\n1\n192.168.56.10\n0\n\n0\nn\n' | bash ./gs-linux.sh --demo >"$TEST_DIR/cancel"
accept 'Confirmação negativa cancela' grep -Fq 'Cancelado' "$TEST_DIR/cancel"
printf '\n%s testes passaram.\n' "$count"
