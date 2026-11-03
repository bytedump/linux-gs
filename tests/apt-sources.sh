#!/usr/bin/env bash
# Usa o parser do APT sem rede (--print-uris), apenas em pastas temporárias.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
source ./gs-linux.sh
command -v apt-get >/dev/null || { echo 'Teste requer Debian com apt-get.'; exit 77; }
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
keyring=/usr/share/keyrings/debian-archive-keyring.gpg
select_platform debian 13
count=0
check() { local label=$1; shift; "$@" || { echo "FALHOU: $label"; exit 1; }; count=$((count+1)); echo "ok $count - $label"; }
fixture() {
    apt_dir=$test_root/$1/apt
    WORK=$test_root/$1/work
    backups=$test_root/$1/backups
    mkdir -p "$apt_dir/sources.list.d" "$WORK"
}
targets() {
    apt-get -o "Dir::Etc::sourcelist=$apt_dir/sources.list" -o "Dir::Etc::sourceparts=$apt_dir/sources.list.d" --print-uris update >"$WORK/targets" 2>&1
}
fixture dvd
cat >"$apt_dir/sources.list" <<'EOF'
# Debian instalado pelo DVD
deb cdrom:[Debian GNU/Linux 13.7.0 _Trixie_ - Official amd64 DVD Binary-1 with firmware]/ trixie main non-free-firmware
EOF
cp "$apt_dir/sources.list" "$WORK/original"
prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring" >"$WORK/result"
check 'Fonte DVD vira comentário' grep -Fq '# GS Linux: mídia desativada: deb cdrom:' "$apt_dir/sources.list"
check 'Versão correta nas fontes novas' grep -Fxq 'Suites: trixie trixie-updates' "$apt_dir/sources.list.d/gs-linux-debian.sources"
check 'Repositório de segurança da mesma versão' grep -Fxq 'Suites: trixie-security' "$apt_dir/sources.list.d/gs-linux-debian.sources"
check 'Assinaturas continuam obrigatórias' grep -Fxq "Signed-By: $keyring" "$apt_dir/sources.list.d/gs-linux-debian.sources"
check 'Backup conserva a fonte original' cmp -s "$WORK/original" "$APT_BACKUP/0"
check 'APT interpreta as fontes reparadas' targets
check 'APT passa a buscar índices de pacotes online' grep -Fq '/dists/trixie/main/binary-' "$WORK/targets"
if grep -Eq "^'cdrom:" "$WORK/targets"; then echo 'APT ainda usa o DVD'; exit 1; fi
check 'Reparo aguarda atualização bem-sucedida' test "$APT_REPAIR_PENDING" -eq 1
restore_apt_sources >"$WORK/restore"
check 'Restauração recupera o arquivo original' cmp -s "$WORK/original" "$apt_dir/sources.list"
check 'Restauração remove somente a fonte criada' test ! -e "$apt_dir/sources.list.d/gs-linux-debian.sources"

prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring" >"$WORK/result"
APT_REPAIR_PENDING=0 # Simula somente o ponto após uma atualização validada.
cp "$apt_dir/sources.list" "$WORK/repaired"
cp "$apt_dir/sources.list.d/gs-linux-debian.sources" "$WORK/online"
prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring" >"$WORK/repeated"
check 'Reexecução não altera a fonte já reparada' cmp -s "$WORK/repaired" "$apt_dir/sources.list"
check 'Reexecução não duplica repositórios' cmp -s "$WORK/online" "$apt_dir/sources.list.d/gs-linux-debian.sources"
check 'Reexecução não cria nova transação' test "$APT_REPAIR_PENDING" -eq 0

fixture mirror
cat >"$apt_dir/sources.list" <<EOF
deb [signed-by=$keyring] cdrom:[Debian DVD]/ trixie main
deb [signed-by=$keyring] https://deb.debian.org/debian trixie main contrib non-free-firmware
EOF
printf 'deb https://packages.example.test/debian stable main\n' >"$apt_dir/sources.list.d/vendor.list"
cp "$apt_dir/sources.list.d/vendor.list" "$WORK/vendor"
prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring" >"$WORK/result"
check 'Fonte online e seus componentes preservados' grep -Fxq "deb [signed-by=$keyring] https://deb.debian.org/debian trixie main contrib non-free-firmware" "$apt_dir/sources.list"
check 'Fonte de terceiros preservada byte a byte' cmp -s "$WORK/vendor" "$apt_dir/sources.list.d/vendor.list"
check 'Mirror existente não recebe fonte duplicada' test ! -e "$apt_dir/sources.list.d/gs-linux-debian.sources"

fixture deb822
cat >"$apt_dir/sources.list.d/dvd.sources" <<EOF
Types: deb
URIs: cdrom:[Debian GNU/Linux 13 DVD with firmware]/
Suites: trixie
Components: main
Signed-By: $keyring
EOF
prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring" >"$WORK/result"
check 'Mídia em deb822 recebe Enabled: no' grep -Fxq 'Enabled: no' "$apt_dir/sources.list.d/dvd.sources"
check 'APT aceita a configuração deb822 reparada' targets
if grep -Eq "^'cdrom:" "$WORK/targets"; then echo 'APT ainda usa DVD deb822'; exit 1; fi

fixture mixed
cat >"$apt_dir/sources.list.d/mixed.sources" <<EOF
# Mirror alternativo no mesmo parágrafo
Types: deb
URIs: cdrom:[Debian DVD with firmware]/
 https://deb.debian.org/debian
Suites: trixie
Components: main contrib
Signed-By: $keyring

# Este parágrafo já está desativado: não deve ser reativado.
Types: deb
URIs: cdrom:[Outro DVD]/
Suites: trixie
Components: main
Enabled: no
EOF
prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring" >"$WORK/result"
check 'Fonte mista mantém URI pela Internet' grep -Fxq 'URIs: https://deb.debian.org/debian' "$apt_dir/sources.list.d/mixed.sources"
check 'Parágrafo desativado não é apagado' grep -Fxq 'URIs: cdrom:[Outro DVD]/' "$apt_dir/sources.list.d/mixed.sources"
check 'Fonte mista mantém componentes' grep -Fxq 'Components: main contrib' "$apt_dir/sources.list.d/mixed.sources"
check 'APT aceita fonte mista reparada' targets
check 'Sem duplicação quando URI online já existe em deb822' test ! -e "$apt_dir/sources.list.d/gs-linux-debian.sources"

fixture no_key
printf 'deb cdrom:[Debian DVD]/ trixie main\n' >"$apt_dir/sources.list"
cp "$apt_dir/sources.list" "$WORK/original"
if (prepare_debian_sources "$apt_dir" "$backups" trixie "$WORK/missing-key") >"$WORK/result" 2>&1; then echo 'Deveria recusar fonte sem chave oficial'; exit 1; fi
check 'Sem chave, nenhuma fonte é alterada' cmp -s "$WORK/original" "$apt_dir/sources.list"

fixture invalid
printf 'deb cdrom:[Debian DVD]/ trixie main\n' >"$apt_dir/sources.list"
printf 'Types: invalid\nURIs: https://deb.debian.org/debian\nSuites: trixie\nComponents: main\n' >"$apt_dir/sources.list.d/broken.sources"
cp "$apt_dir/sources.list" "$WORK/original"
if (prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring") >"$WORK/result" 2>&1; then echo 'Deveria detectar fontes inválidas antes de alterar'; exit 1; fi
check 'Erro de sintaxe nas fontes não altera os arquivos originais' cmp -s "$WORK/original" "$apt_dir/sources.list"

fixture interrupt
printf 'deb cdrom:[Debian DVD]/ trixie main\n' >"$apt_dir/sources.list"
cp "$apt_dir/sources.list" "$test_root/interrupted-original"
if (
    trap cleanup EXIT
    prepare_debian_sources "$apt_dir" "$backups" trixie "$keyring"
    exit 1
) >"$test_root/interrupted-log" 2>&1; then echo 'Interrupção deveria retornar erro'; exit 1; fi
check 'Interrupção restaura as fontes antes de sair' cmp -s "$test_root/interrupted-original" "$apt_dir/sources.list"
check 'Interrupção remove a fonte criada' test ! -e "$apt_dir/sources.list.d/gs-linux-debian.sources"
echo "$count testes de fontes APT passaram."
