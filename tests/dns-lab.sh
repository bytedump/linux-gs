#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source ./gs-linux.sh
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
count=0
check() { local label=$1; shift; "$@" || { echo "FALHOU: $label"; exit 1; }; count=$((count+1)); echo "ok $count - $label"; }
reject() { local label=$1; shift; if "$@" >"$test_dir/rejected" 2>&1; then echo "FALHOU: $label"; exit 1; fi; count=$((count+1)); echo "ok $count - $label"; }
select_platform debian 13
DOMAIN=aluno.fiap; SERVER_IP=192.168.56.10; PRIMARY_IP=$SERVER_IP
SECONDARY_IP=192.168.56.20; WEB_IP=$SECONDARY_IP
set_reverse_network 192.168.56.0/24
set_zone_paths
base_records
reject 'ns1 não aceita IP diferente do primário' add_record ns1 A 192.168.56.99
reject 'Reversa recusa prefixo não implementado' set_reverse_network 192.168.56.0/25
reject 'Reversa recusa endereço que não é de rede' set_reverse_network 192.168.56.10/24
render_zone "$test_dir/direct" 2026110400
render_reverse "$test_dir/reverse" 2026110400
render_named "$test_dir/named"
check 'www é A e aponta para o secundário' grep -Fxq 'www IN A 192.168.56.20' "$test_dir/direct"
check 'intranet é CNAME de www' grep -Fxq 'intranet IN CNAME www.aluno.fiap.' "$test_dir/direct"
check 'SOA refresh da atividade' grep -Eq '^ +28800 +;' "$test_dir/direct"
check 'SOA retry da atividade' grep -Eq '^ +14400 +;' "$test_dir/direct"
check 'SOA expire da atividade' grep -Eq '^ +86400 +;' "$test_dir/direct"
check 'SOA minimum da atividade' grep -Eq '^ +600 \)' "$test_dir/direct"
check 'Nome da zona reversa' test "$REVERSE_ZONE" = 56.168.192.in-addr.arpa
check 'PTR do primário' grep -Fxq '10 IN PTR ns1.aluno.fiap.' "$test_dir/reverse"
check 'PTR do www/secundário' grep -Fxq '20 IN PTR www.aluno.fiap.' "$test_dir/reverse"
if grep -Fq 'intranet.aluno.fiap' "$test_dir/reverse"; then echo 'Não deve gerar PTR de CNAME'; exit 1; fi
check 'Arquivo direto usa o nome solicitado' test "$ZONE_FILE" = /var/lib/bind/gs-linux/aluno.fiap.zone
check 'ACL libera apenas o secundário' grep -Fq 'allow-transfer { 192.168.56.20; };' "$test_dir/named"
check 'Notify do primário é explícito' grep -Fq 'also-notify { 192.168.56.20; };' "$test_dir/named"
add_record webmail A 10.200.200.200
render_reverse "$test_dir/reverse" 2026110400
if grep -Fq webmail "$test_dir/reverse"; then echo 'IP externo não pertence à zona reversa local'; exit 1; fi
edit_record >"$test_dir/edit" <<'INPUT'
3
192.168.56.30
INPUT
render_zone "$test_dir/edited" 2026110401
check 'Edição de www atualiza o IP' grep -Fxq 'www IN A 192.168.56.30' "$test_dir/edited"
check 'Edição de www preserva intranet' grep -Fxq 'intranet IN CNAME www.aluno.fiap.' "$test_dir/edited"
# www foi movido para o final pela edição; intranet continua no índice 3 da lista.
edit_record >"$test_dir/edit-invalid" <<'INPUT'
3
inexistente.aluno.fiap
INPUT
render_zone "$test_dir/after-invalid" 2026110401
check 'Edição inválida preserva todos os registros anteriores' cmp -s "$test_dir/edited" "$test_dir/after-invalid"
remove_record >"$test_dir/remove" <<'INPUT'
1
INPUT
render_zone "$test_dir/removed" 2026110402
if grep -Eq '^@ IN A ' "$test_dir/removed"; then echo 'Registro @ deveria ser removível'; exit 1; fi
check 'Serial inicial usa data e contador' test "$(next_zone_serial 0 20261104)" = 2026110400
check 'Reaplicação aumenta contador' test "$(next_zone_serial 2026110400 20261104)" = 2026110401
check 'Outro dia reinicia contador' test "$(next_zone_serial 2026110399 20261104)" = 2026110400
check 'Migração de serial epoch preserva crescimento' test "$(next_zone_serial 1793723801 20261104)" = 2026110400
if (next_zone_serial 2026110499 20261104) >"$test_dir/serial-error" 2>&1; then echo 'Não deve ultrapassar nn=99'; exit 1; fi
if (next_zone_serial 2026110500 20261104) >"$test_dir/serial-error" 2>&1; then echo 'Não deve diminuir serial com relógio atrasado'; exit 1; fi
STATE_DIR=$test_dir/state
mkdir "$STATE_DIR"
save_state
load_state
check 'Estado preserva a zona reversa' test "$REVERSE_NETWORK" = 192.168.56.0/24
check 'Estado preserva o IP autorizado' test "$SECONDARY_IP" = 192.168.56.20
DNS_ROLE=secondary; SERVER_IP=192.168.56.20
REC_NAME=(); REC_TYPE=(); REC_VALUE=(); REC_PRIORITY=()
set_zone_paths
render_named "$test_dir/secondary"
check 'Duas zonas slave são declaradas' test "$(grep -c 'type slave;' "$test_dir/secondary")" -eq 2
check 'Secundário consulta o primário correto' grep -Fq 'masters { 192.168.56.10; };' "$test_dir/secondary"
check 'Secundário usa caminho gravável no Debian' test "$ZONE_DIR" = /var/cache/bind/gs-linux
save_state; load_state
check 'Estado preserva o papel secundário' test "$DNS_ROLE" = secondary
select_platform rocky 9; set_zone_paths
check 'Secundário usa slaves no Rocky' test "$ZONE_DIR" = /var/named/slaves/gs-linux
select_platform debian 13
printf 'antigo.test\n192.168.56.10\n@\tA\t-\t192.168.56.10\n' >"$STATE_DIR/state"
load_state
check 'Estado 1.1 continua legível' test "$LEGACY_STATE:$DOMAIN" = 1:antigo.test
check 'Migração não inventa zona reversa antiga' test -z "$REVERSE_ZONE"
check 'Estado antigo aponta para arquivo antigo' test "$ZONE_FILE" = /var/lib/bind/gs-linux/db.zone

# Rollback precisa restaurar diretórios de zona e o link Apache sem seguir seu destino.
BACKUP=$test_dir/backup
mkdir -p "$BACKUP" "$test_dir/zones"
printf 'zona anterior\n' >"$test_dir/zones/cache.zone"
printf 'site anterior\n' >"$test_dir/available.conf"
ln -s "$test_dir/available.conf" "$test_dir/enabled.conf"
backup_path "$test_dir/zones"
backup_path "$test_dir/enabled.conf" link
rm "$test_dir/zones/cache.zone" "$test_dir/enabled.conf"
printf 'zona nova\n' >"$test_dir/zones/new.zone"
printf 'site novo\n' >"$test_dir/enabled.conf"
systemctl() { return 0; }
rollback >"$test_dir/rollback" 2>&1
unset -f systemctl
check 'Rollback recupera arquivos de zonas secundárias' grep -Fxq 'zona anterior' "$test_dir/zones/cache.zone"
check 'Rollback remove arquivos novos da pasta gerenciada' test ! -e "$test_dir/zones/new.zone"
check 'Rollback restaura link do Apache' test -L "$test_dir/enabled.conf"
check 'Backup do link não modifica seu destino' grep -Fxq 'site anterior' "$test_dir/available.conf"
ip() { printf '2: nat0 inet 10.0.2.15/24 scope global nat0\n3: lab0 inet 192.168.56.10/24 scope global lab0\n'; }
MODE=demo
choose_server_ip >"$test_dir/interfaces" <<<' '
check 'Interface do laboratório é sugerida antes da NAT' test "$SERVER_IP:$SERVER_IFACE" = 192.168.56.10:lab0
wizard >"$test_dir/secondary-demo" <<'INPUT'
aluno.fiap
2
192.168.56.20
192.168.56.10

s
INPUT
check 'Assistente secundário coleta o primário correto' test "$DNS_ROLE:$PRIMARY_IP:$SERVER_IP" = secondary:192.168.56.10:192.168.56.20
check 'Assistente secundário não gera registros locais' test "${#REC_NAME[@]}" -eq 0
echo "$count testes do perfil DNS passaram."
