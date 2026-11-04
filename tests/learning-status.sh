#!/usr/bin/env bash
# Testes do guia/orientador e do relatório; nenhuma alteração no sistema.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source ./gs-linux.sh
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
count=0
check() { local label=$1; shift; "$@" || { echo "FALHOU: $label"; exit 1; }; count=$((count+1)); echo "ok $count - $label"; }

printf '1\n2\n\n0\n0\n' | bash gs-linux.sh >"$test_dir/menu"
check 'Menu padrão abre estudo sem exigir root' grep -Fq 'Registros DNS — qual deles usar?' "$test_dir/menu"
check 'Guia retorna ao menu principal' test "$(grep -c 'O QUE VOCÊ QUER FAZER?' "$test_dir/menu")" -eq 2
printf '1\n\n2\n\n3\n\n4\n\n5\n\n6\n\n7\n\n8\n\n0\n' | bash gs-linux.sh --learn >"$test_dir/guide"
for topic in 'EXPLICAÇÃO EM UMA FRASE' 'SERIAL' 'VirtualHost' 'Gateway' 'LEASE' 'Enforcing' 'ENABLED' 'Backup agendado'; do
    check "Guia explica $topic" grep -Fq "$topic" "$test_dir/guide"
done
printf 'O professor pediu DHCP\ns\n1\ns\n\n0\n' | bash gs-linux.sh --tutor >"$test_dir/tutor"
check 'Orientador identifica DHCP' grep -Fq 'Assunto sugerido: DHCP' "$test_dir/tutor"
check 'Orientador faz pergunta adicional' grep -Fq 'distribuir IPs automaticamente' "$test_dir/tutor"
check 'Não afirma ter instalado DHCP' grep -Fq 'DHCP ainda exige implementação' "$test_dir/tutor"
printf 'Não sei qual assunto\nn\n2\n\n0\n0\n' | bash gs-linux.sh --tutor >"$test_dir/unknown"
check 'Assunto não reconhecido permite escolher no guia' grep -Fq 'Registros DNS — qual deles usar?' "$test_dir/unknown"
# shellcheck disable=SC2016 # Deve ser texto literal para provar que não é executado.
printf '$(touch %s/injected)\ns\n0\n0\n' "$test_dir" | bash gs-linux.sh --tutor >"$test_dir/input"
check 'Pergunta digitada não é executada como comando' test ! -e "$test_dir/injected"
if bash gs-linux.sh --learn </dev/null >"$test_dir/eof" 2>&1; then echo 'EOF deveria interromper'; exit 1; fi
check 'EOF interrompe o guia sem loop' grep -Fq 'Entrada encerrada' "$test_dir/eof"
MODE=demo
wizard >"$test_dir/wizard" <<'INPUT'
aluno.fiap
1
192.168.56.10
0

1
loja
192.168.56.20
6

0
s
INPUT
check 'Ajuda durante cadastro preserva registro extra' test "${REC_NAME[4]}:${REC_VALUE[4]}" = loja:192.168.56.20
check 'Ajuda contextual foi exibida' grep -Fq 'O ponto final' "$test_dir/wizard"
check 'Saída redirecionada não contém escapes ANSI' test "$(LC_ALL=C tr -cd '\033' <"$test_dir/menu" | wc -c)" -eq 0

# Resultados de processo e conteúdo não são equivalentes: código 0 com resposta
# DNS errada também precisa ser FALHA; comando ausente deve ser NÃO VERIFICADO.
REPORT_OK=0 REPORT_FAIL=0 REPORT_UNKNOWN=0
report_match 'Resposta incorreta' esperado printf '%s\n' errado >"$test_dir/probe"
check 'Resposta errada é falha mesmo com exit 0' test "$REPORT_FAIL" -eq 1
report_match 'Resposta correta' esperado printf '%s\n' esperado >>"$test_dir/probe"
check 'Resposta correta passa' test "$REPORT_OK" -eq 1
report_command 'Ferramenta ausente' gs_missing_tool_123 >>"$test_dir/probe"
check 'Ferramenta ausente não vira sucesso' test "$REPORT_UNKNOWN" -eq 1
report_command 'Comando falhou' bash -c 'echo erro; exit 7' >>"$test_dir/probe"
check 'Código de falha real é preservado na evidência' grep -Fq 'código 7' "$test_dir/probe"
REPORT_OK=0 REPORT_FAIL=0 REPORT_UNKNOWN=0
# shellcheck disable=SC2317 # Invocada indiretamente por report_port/capture_probe.
ss() { echo 'UNCONN 0 0 192.168.56.10:53 0.0.0.0:*'; }
report_port UDP 53 named >>"$test_dir/probe"
check 'Socket com proprietário oculto não é confundido com outro processo' test "$REPORT_FAIL:$REPORT_UNKNOWN" = 0:1
unset -f ss

# Painel deve continuar depois de um erro de configuração. As ferramentas são
# substituídas por funções só neste processo; não há alterações nem serviços reais.
select_platform debian 12
STATE_DIR=$test_dir/absent
named-checkconf() { echo 'Erro na configuração BIND'; return 1; }
apache2ctl() { echo 'Syntax OK'; }
ss() { return 0; }
report_firewall() { report_item 'NÃO VERIFICADO' 'Firewall de teste'; }
result=0
evidence_panel >"$test_dir/failure" || result=$?
check 'Painel com falhas retorna 1' test "$result" -eq 1
check 'Erro de configuração aparece no relatório' grep -Fq '[FALHA] BIND' "$test_dir/failure"
check 'Depois da falha, Apache continua sendo verificado' grep -Fq '[OK] Apache' "$test_dir/failure"
check 'Sem configuração salva, não inventa testes DNS/HTTP' grep -Fq '[NÃO VERIFICADO] Consultas DNS e HTTP' "$test_dir/failure"
check 'Painel conclui o resumo mesmo com falhas' grep -Fq 'RESULTADO E COMO APRESENTAR' "$test_dir/failure"
result=0
export_report >"$test_dir/export" || result=$?
report_file=$(sed -n 's/.*Relatório salvo em: //p' "$test_dir/export")
check 'Relatório exportado preserva código de falha' test "$result" -eq 1
check 'Relatório salvo contém as falhas reais' grep -Fq '[FALHA] BIND' "$report_file"
check 'Relatório salvo é privado para o usuário' test "$(stat -c %a "$report_file")" = 600
rm -- "$report_file"
echo "$count testes do guia e painel passaram."
