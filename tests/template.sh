#!/usr/bin/env bash
# Template verificado + cópia local, e um PTR por IP. Não usa rede nem altera /etc.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source ./gs-linux.sh
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
count=0
check() { local label=$1; shift; "$@" || { echo "FALHOU: $label"; exit 1; }; count=$((count+1)); echo "ok $count - $label"; }
lacks() { ! grep -qF -- "$1" "$2"; }
isolated_download() { ( LOG=/dev/null; DOMAIN=aluno.fiap; WORK=$1; TEMPLATE_DIR=$2; curl() { return 6; }; download_template ); }
reject() { local label=$1; shift; if "$@" >"$test_dir/rejected" 2>&1; then echo "FALHOU: $label"; exit 1; fi; count=$((count+1)); echo "ok $count - $label"; }
GOOD=$PWD/template
LOG=/dev/null; DOMAIN=aluno.fiap
new_work() { WORK=$(mktemp -d "$test_dir/work.XXXXXX"); TEMPLATE_SOURCE=''; }
# Simula o curl: 'good' copia o template verdadeiro; 'bad' altera um arquivo; 'down' falha.
curl_mode=good
curl() {
    local out='' url='' rel
    while (( $# )); do case $1 in -o) out=$2; shift ;; https://*) url=$1 ;; esac; shift; done
    [[ $curl_mode != down ]] || return 6
    case $url in
        */dist/*) rel=${url#*/dist/} ;; */LICENSE) rel=LICENSE ;; *bootstrap.bundle.min.js) rel=js/bootstrap.bundle.min.js ;; *) return 22 ;;
    esac
    cp -- "$GOOD/$rel" "$out"
    if [[ $curl_mode == bad && $rel == index.html ]]; then printf '<!doctype html><script>alert(1)</script>\n' >"$out"; fi
}
check 'Hashes do script conferem com a pasta template/' verify_template "$GOOD"

new_work; curl_mode=good; TEMPLATE_DIR=$test_dir/inexistente
check 'Download bom é aceito sem cópia local' download_template >/dev/null
check 'Origem registrada: internet' test "$TEMPLATE_SOURCE" = internet

new_work; curl_mode=down; TEMPLATE_DIR=$GOOD
check 'Sem Internet usa a cópia local' download_template >/dev/null
check 'Origem registrada: local' test "$TEMPLATE_SOURCE" = local
check 'Site montado tem o CSS' test -s "$WORK/site/css/styles.css"
check 'Site montado tem o Bootstrap local' test -s "$WORK/site/js/bootstrap.bundle.min.js"
check 'Domínio aplicado no HTML' grep -q 'GS Linux: aluno.fiap' "$WORK/site/index.html"
check 'Bootstrap deixa de apontar para CDN' lacks cdn.jsdelivr "$WORK/site/index.html"

new_work; curl_mode=bad; TEMPLATE_DIR=$GOOD
check 'Download adulterado cai na cópia local' download_template >/dev/null
check 'Conteúdo adulterado não entrou no site' lacks 'alert(1)' "$WORK/site/index.html"
check 'Origem após adulteração: local' test "$TEMPLATE_SOURCE" = local

cp -a "$GOOD" "$test_dir/tampered"; printf 'x' >>"$test_dir/tampered/js/scripts.js"; printf 'segredo' >"$test_dir/tampered/extra.txt"
new_work; curl_mode=down; TEMPLATE_DIR=$test_dir/tampered
reject 'Sem Internet e cópia local alterada: aborta' isolated_download "$WORK" "$test_dir/tampered"
new_work
reject 'Sem Internet e sem pasta template/: aborta' isolated_download "$WORK" "$test_dir/nada"

cp -a "$GOOD" "$test_dir/comextra"; printf 'x' >"$test_dir/comextra/extra.txt"
new_work; curl_mode=down; TEMPLATE_DIR=$test_dir/comextra
check 'Cópia local com arquivo extra ainda é válida' download_template >/dev/null
check 'Arquivo extra não é publicado' test ! -e "$WORK/site/extra.txt"

# Um PTR por IP; ns1 tem prioridade.
select_platform debian 13
SERVER_IP=192.168.56.10; PRIMARY_IP=$SERVER_IP; SECONDARY_IP=192.168.56.20; WEB_IP=$SECONDARY_IP
set_reverse_network 192.168.56.0/24; set_zone_paths; base_records
render_reverse "$test_dir/reverse" 2026110400
check 'IP do primário tem exatamente um PTR' test "$(grep -c '^10 IN PTR' "$test_dir/reverse")" = 1
check 'PTR do primário é ns1' grep -Fxq '10 IN PTR ns1.aluno.fiap.' "$test_dir/reverse"
check 'PTR do secundário é www' grep -Fxq '20 IN PTR www.aluno.fiap.' "$test_dir/reverse"
add_record mail A 192.168.56.10 >/dev/null; add_record loja A 192.168.56.20 >/dev/null
render_reverse "$test_dir/reverse2" 2026110400
check 'Novo A no mesmo IP não duplica PTR' test "$(grep -c '^10 IN PTR' "$test_dir/reverse2")" = 1
check 'Primeiro nome cadastrado vence quando não há ns1' grep -Fxq '20 IN PTR www.aluno.fiap.' "$test_dir/reverse2"

# Aviso do www lê os registros finais (editados/removidos), não o valor inicial.
notice() { NO_COLOR=1 www_notice 2>&1 | tr '\n' ' ' | tr -s ' '; }
base_records
check 'www no secundário: avisa com o IP do secundário' grep -q 'secundário (192.168.56.20)' <(notice)
REC_VALUE[2]=192.168.56.10
check 'www editado para esta VM: sem aviso' test -z "$(notice)"
REC_VALUE[2]=192.168.56.30
check 'www editado para outra máquina: avisa o novo IP' grep -q 'aponta para 192.168.56.30' <(notice)
check 'Aviso editado não cita o IP antigo' lacks '192.168.56.20' <(notice)
base_records
REC_NAME=("${REC_NAME[@]:0:2}" "${REC_NAME[@]:3}"); REC_TYPE=("${REC_TYPE[@]:0:2}" "${REC_TYPE[@]:3}")
REC_VALUE=("${REC_VALUE[@]:0:2}" "${REC_VALUE[@]:3}"); REC_PRIORITY=("${REC_PRIORITY[@]:0:2}" "${REC_PRIORITY[@]:3}")
check 'www removido: informa que não há registro' grep -q 'Não há registro www' <(notice)
check 'www removido: não cita mais o secundário' lacks 'aponta para o secundário' <(notice)
check 'www removido com @ presente: cita o domínio' grep -q 'e por aluno.fiap' <(notice)
REC_NAME=("${REC_NAME[@]:1}"); REC_TYPE=("${REC_TYPE[@]:1}"); REC_VALUE=("${REC_VALUE[@]:1}"); REC_PRIORITY=("${REC_PRIORITY[@]:1}")
check 'Sem www e sem @: avisa que nenhum nome resolve' grep -q 'nenhum desses nomes será resolvido' <(notice)
check 'Sem www e sem @: não promete acesso pelo domínio' lacks 'e por aluno.fiap' <(notice)
echo; echo "$count testes do template e dos PTRs passaram."
