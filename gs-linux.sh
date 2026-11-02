#!/usr/bin/env bash
# GS Linux — assistente para um laboratório Debian/Rocky Linux.
# Uso: bash gs-linux.sh --demo | sudo bash gs-linux.sh
# Cada função representa uma etapa; as tarefas extras ficam no final do arquivo.

set -Eeuo pipefail
umask 022

VERSION=1.0
MODE=install
DOMAIN='' SERVER_IP='' PLATFORM='' DNS_SERVICE='' WEB_SERVICE=''
DNS_CONF='' ZONE_FILE='' DNS_GROUP='' WEB_CONF=''
WEB_ROOT=/var/www/gs-linux
STATE_DIR=/var/lib/gs-linux
BACKUP='' WORK='' LOG='' TRANSACTION=0
DNS_WAS_ACTIVE=0 WEB_WAS_ACTIVE=0 DNS_WAS_ENABLED=0 WEB_WAS_ENABLED=0
declare -a REC_NAME=() REC_TYPE=() REC_VALUE=() REC_PRIORITY=()
declare -a SAVED_PATHS=() SAVED_EXISTS=() FW_ADDED=()
RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''

colors() {
    if [[ -t 1 && ${TERM:-dumb} != dumb && -z ${NO_COLOR+x} ]]; then
        RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
        CYAN=$'\e[36m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
    fi
}
info() { printf '%s[INFO]%s %s\n' "$CYAN" "$RESET" "$*"; }
ok() { printf '%s[ OK ]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[AVISO]%s %s\n' "$YELLOW" "$RESET" "$*"; }
die() { printf '%s[ERRO]%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
banner() {
    printf '%s' "$CYAN"
    cat <<'ART'
  +------------------------------------------+
  |   ____ ____     _     ___ _   _ _   ___  |
  |  / ___/ ___|   | |   |_ _| \ | | | | \ \ |
  | | |  _\___ \   | |    | ||  \| | | | |> >|
  | | |_| |___) |  | |___ | || |\  | |_| /_/ |
  |  \____|____/   |_____|___|_| \_|\___/    |
  |       DNS + WEB | DEBIAN + ROCKY          |
  +------------------------------------------+
ART
    printf '%s' "$RESET"
    info "Assistente da GS v$VERSION — use em uma VM de laboratório."
}
help_text() {
    cat <<'HELP'
Uso:
  bash gs-linux.sh --demo        Treina os menus sem alterar a máquina.
  sudo bash gs-linux.sh          Instala e configura DNS + Apache.
  sudo bash gs-linux.sh --check  Testa a instalação já realizada.
  bash gs-linux.sh --help        Mostra esta ajuda.

Compatibilidade prevista: Debian 11/12/13 e Rocky Linux 8/9/10, com systemd.
Defina NO_COLOR=1 para desativar cores. Não precisa instalar nada para a demo.
A instalação requer Internet, privilégios de root e uma VM com IPv4 estável.
HELP
}

# O texto digitado nunca é executado como comando (não usamos eval).
ask() {
    local prompt=$1 default=${2:-} answer
    if [[ -n $default ]]; then printf '%s [%s]: ' "$prompt" "$default"; else printf '%s: ' "$prompt"; fi
    if ! IFS= read -r answer; then die 'Entrada encerrada. Execute em um terminal interativo.'; fi
    answer="${answer#"${answer%%[![:space:]]*}"}"
    answer="${answer%"${answer##*[![:space:]]}"}"
    REPLY=${answer:-$default}
}
valid_ipv4() {
    local value=$1 part
    local -a parts
    [[ $value =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a parts <<< "$value"
    for part in "${parts[@]}"; do
        [[ ${#part} -le 3 && ( $part == 0 || $part != 0* ) ]] || return 1
        (( 10#$part <= 255 )) || return 1
    done
}
valid_hostname() {
    local value=$1 label
    local -a labels
    [[ ${#value} -le 253 && $value =~ ^[a-z0-9.-]+$ && $value != .* && $value != *. && $value != *..* ]] || return 1
    IFS=. read -r -a labels <<< "$value"
    for label in "${labels[@]}"; do
        [[ ${#label} -le 63 && $label != -* && $label != *- ]] || return 1
    done
}
valid_domain() { [[ $1 == *.* && ! $1 =~ ^[0-9.]+$ ]] && valid_hostname "$1"; }
valid_owner() {
    local value=$1 type=$2
    [[ $value == @ ]] && return 0
    # TXT pode usar nomes como _dmarc. Os demais seguem nomes de host.
    if [[ $type == TXT ]]; then value=${value//_/a}; fi
    valid_hostname "$value" && (( ${#value} + ${#DOMAIN} + 1 <= 253 ))
}
valid_priority() { [[ $1 =~ ^[0-9]{1,5}$ ]] && (( 10#$1 <= 65535 )); }
valid_txt() { [[ -n $1 && ${#1} -le 200 && ! $1 =~ [^[:print:]] ]]; }

select_platform() {
    local id=$1 version=${2%%.*}
    case "$id:$version" in
        debian:11|debian:12|debian:13)
            PLATFORM=debian; DNS_SERVICE=named; WEB_SERVICE=apache2; DNS_GROUP=bind
            DNS_CONF=/etc/bind/named.conf; ZONE_FILE=/var/lib/bind/gs-linux/db.zone
            WEB_CONF=/etc/apache2/sites-enabled/000-000-gs-linux.conf ;;
        rocky:8|rocky:9|rocky:10)
            PLATFORM=rocky; DNS_SERVICE=named; WEB_SERVICE=httpd; DNS_GROUP=named
            DNS_CONF=/etc/named.conf; ZONE_FILE=/var/named/gs-linux/db.zone
            WEB_CONF=/etc/httpd/conf.d/00-gs-linux.conf ;;
        *) return 1 ;;
    esac
}
detect_platform() {
    [[ -r /etc/os-release ]] || die 'Não encontrei /etc/os-release.'
    # Arquivo fornecido pelo sistema operacional, nunca dados digitados pelo usuário.
    . /etc/os-release
    if ! select_platform "$ID" "$VERSION_ID"; then
        if [[ $MODE == demo ]]; then
            warn 'Sistema fora da lista; a demonstração usará os caminhos do Debian.'
            select_platform debian 12
        else die "Sistema não previsto: $PRETTY_NAME. Use Debian 11–13 ou Rocky 8–10."; fi
    fi
    info "Sistema: $PRETTY_NAME | DNS: BIND | Web: Apache ($WEB_SERVICE)."
}
detect_ip() {
    local candidate=''
    if command -v ip >/dev/null; then
        candidate=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}') || true
    fi
    if [[ -z $candidate ]] && command -v hostname >/dev/null; then
        candidate=$(hostname -I 2>/dev/null | awk '{print $1}') || true
    fi
    if valid_ipv4 "$candidate"; then printf '%s' "$candidate"; fi
}
ip_is_local() { ip -o -4 addr show | awk '{split($4,a,"/");print a[1]}' | grep -Fxq -- "$SERVER_IP"; }

add_record() {
    local name=$1 type=$2 value=$3 priority=${4:-} i
    for i in "${!REC_NAME[@]}"; do
        [[ ${REC_NAME[i]} == "$name" ]] || continue
        if [[ ${REC_TYPE[i]} == "$type" && ${REC_VALUE[i]} == "$value" && ${REC_PRIORITY[i]} == "$priority" ]]; then
            warn 'Esse registro já está na lista.'; return 1
        fi
        if [[ $type == CNAME || ${REC_TYPE[i]} == CNAME ]]; then
            warn 'CNAME precisa ser o único registro desse nome. Remova o registro anterior primeiro.'; return 1
        fi
    done
    if [[ $type == CNAME && ( $name == @ || $name == ns1 ) ]]; then
        warn 'O domínio principal e ns1 são reservados para a configuração básica.'; return 1
    fi
    # Um alias só aponta para um nome que já possui A: impede ciclos e aliases quebrados.
    if [[ $type == CNAME || $type == MX ]]; then
        local found=0 target
        for i in "${!REC_NAME[@]}"; do
            target=${REC_NAME[i]}; [[ $target == @ ]] && target=$DOMAIN || target=$target.$DOMAIN
            [[ ${REC_TYPE[i]} == A && $target == "$value" ]] && found=1
        done
        if (( ! found )); then
            warn 'Cadastre primeiro um registro A para esse destino dentro do seu domínio.'; return 1
        fi
    fi
    REC_NAME+=("$name"); REC_TYPE+=("$type"); REC_VALUE+=("$value"); REC_PRIORITY+=("$priority")
}
base_records() {
    REC_NAME=(@ ns1 www); REC_TYPE=(A A CNAME)
    REC_VALUE=("$SERVER_IP" "$SERVER_IP" "$DOMAIN"); REC_PRIORITY=('' '' '')
}
show_records() {
    local i
    printf '\n%-4s %-22s %-7s %s\n' 'Nº' 'NOME' 'TIPO' 'VALOR'
    for i in "${!REC_NAME[@]}"; do
        printf '%-4s %-22s %-7s %s %s\n' "$((i+1))" "${REC_NAME[i]}" "${REC_TYPE[i]}" "${REC_PRIORITY[i]}" "${REC_VALUE[i]}"
    done
    info '1, 2 e 3 são a base fixa: domínio, servidor DNS (ns1) e site (www).'
}
prompt_record() {
    local type=$1 name value priority=''
    while :; do
        ask 'Nome do registro (ex.: loja, mail ou @ para o domínio principal)'
        name=${REPLY,,}; name=${name%.}
        [[ $name == "$DOMAIN" ]] && name=@
        [[ $name == *."$DOMAIN" ]] && name=${name%."$DOMAIN"}
        if valid_owner "$name" "$type"; then break; fi
        warn 'Nome inválido. Use letras sem acento, números e hífens; TXT também aceita _.'
    done
    case $type in
        A)
            while :; do
                ask 'IPv4 de destino (ex.: 192.168.56.20)' "$SERVER_IP"; value=$REPLY
                if valid_ipv4 "$value"; then break; fi
                warn 'IPv4 inválido. Cada parte deve ir de 0 a 255, sem zeros à esquerda.'
            done ;;
        CNAME|MX)
            info 'O destino precisa ter um registro A nesta zona. Ex.: mail.empresa.test.'
            [[ $type == MX ]] && warn 'MX só publica o endereço: não instala um servidor de e-mail.'
            while :; do
                ask 'Nome completo de destino' "$DOMAIN"; value=${REPLY,,}; value=${value%.}
                if valid_domain "$value"; then break; fi
                warn 'Use um nome completo, como mail.empresa.test, nunca um IP.'
            done
            if [[ $type == MX ]]; then
                while :; do
                    ask 'Prioridade do MX (menor número = maior preferência)' 10; priority=$REPLY
                    if valid_priority "$priority"; then priority=$((10#$priority)); break; fi
                    warn 'Digite um número entre 0 e 65535.'
                done
            fi ;;
        TXT)
            while :; do
                ask 'Texto (até 200 caracteres; não precisa colocar aspas)'; value=$REPLY
                if LC_ALL=C valid_txt "$value"; then break; fi
                warn 'Use de 1 a 200 caracteres visíveis, sem acentos ou quebras de linha.'
            done ;;
    esac
    if add_record "$name" "$type" "$value" "$priority"; then ok 'Registro adicionado.'; fi
}
remove_record() {
    local index i target
    show_records
    ask 'Número do registro extra a remover (0 = voltar)' 0
    [[ $REPLY =~ ^[0-9]{1,5}$ ]] || { warn 'Digite um número da lista.'; return; }
    index=$((10#$REPLY - 1))
    (( index == -1 )) && return 0
    if (( index < 3 || index >= ${#REC_NAME[@]} )); then warn 'Escolha um registro extra, a partir de 4.'; return; fi
    target=${REC_NAME[index]}; [[ $target == @ ]] && target=$DOMAIN || target=$target.$DOMAIN
    for i in "${!REC_NAME[@]}"; do
        if [[ ( ${REC_TYPE[i]} == CNAME || ${REC_TYPE[i]} == MX ) && ${REC_VALUE[i]} == "$target" ]]; then
            warn 'Outro registro depende desse destino. Remova o alias/MX primeiro.'; return
        fi
    done
    unset 'REC_NAME[index]' 'REC_TYPE[index]' 'REC_VALUE[index]' 'REC_PRIORITY[index]'
    REC_NAME=("${REC_NAME[@]}"); REC_TYPE=("${REC_TYPE[@]}"); REC_VALUE=("${REC_VALUE[@]}"); REC_PRIORITY=("${REC_PRIORITY[@]}")
    ok 'Registro removido.'
}
wizard() {
    local suggested choice
    suggested=$(detect_ip)
    [[ $MODE == demo && -z $suggested ]] && suggested=192.168.56.10
    while :; do
        while :; do
            ask 'Domínio do laboratório (sem http://; .test é próprio para exercícios)' empresa.test
            DOMAIN=${REPLY,,}; DOMAIN=${DOMAIN%.}
            if valid_domain "$DOMAIN" && [[ $DOMAIN != *.local ]]; then break; fi
            warn 'Exemplo válido: empresa.test. Evite .local, reservado para descoberta de rede.'
        done
        while :; do
            ask 'IPv4 DESTA máquina, acessível pelos colegas na rede' "$suggested"; SERVER_IP=$REPLY
            if valid_ipv4 "$SERVER_IP" && [[ $SERVER_IP != 127.* && $SERVER_IP != 0.* ]] && (( ${SERVER_IP%%.*} < 224 )); then break; fi
            warn 'Informe o IP da interface de rede, não 127.0.0.1, multicast ou 0.0.0.0.'
        done
        warn 'Mantenha esse IP estável na VM. Se o DHCP mudar o IP, execute o assistente novamente.'
        base_records
        while :; do
            show_records
            printf '\n1) A — nome → IPv4\n2) CNAME — apelido → outro nome\n3) MX — servidor de e-mail\n4) TXT — texto\n5) Remover registro extra\n0) Concluir registros\n'
            ask 'Escolha uma opção' 0
            case $REPLY in
                1) prompt_record A ;; 2) prompt_record CNAME ;; 3) prompt_record MX ;; 4) prompt_record TXT ;;
                5) remove_record ;; 0) break ;; *) warn 'Escolha uma opção de 0 a 5.' ;;
            esac
        done
        printf '\n%sRESUMO ANTES DE CONTINUAR%s\n' "$BOLD" "$RESET"
        info "Domínio: $DOMAIN | IP: $SERVER_IP | Sistema: $PLATFORM"
        show_records
        info 'Instalar: BIND e Apache; baixar: template Bare / Start Bootstrap (licença MIT).'
        warn 'A configuração principal do BIND será substituída; o Apache servirá este site como padrão.'
        info 'Arquivos alterados terão backup. Pacotes instalados permanecem se houver falha.'
        info 'Firewall ativo: liberar somente DNS (TCP/UDP 53) e HTTP (TCP 80). SELinux permanece ativo.'
        ask 'S = continuar, R = refazer as respostas, N = sair' N; choice=${REPLY,,}
        case $choice in s|sim) return ;; r) continue ;; *) info 'Cancelado. Nenhuma configuração aplicada.'; exit 0 ;; esac
    done
}

preflight() {
    (( EUID == 0 )) || die 'Para instalar: sudo bash gs-linux.sh. Para treinar: bash gs-linux.sh --demo.'
    command -v systemctl >/dev/null || die 'Esta instalação precisa de systemd (use uma VM completa).'
    [[ -d /run/systemd/system ]] || die 'O systemd não está ativo. Use uma VM Debian/Rocky, não um contêiner comum.'
    command -v flock >/dev/null || die 'Falta flock (pacote util-linux).'
    exec 9>/run/lock/gs-linux.lock
    flock -n 9 || die 'Já existe outra execução deste instalador.'
    [[ ! -L $STATE_DIR && ! -L $WEB_ROOT ]] || die 'Diretório de trabalho é um link simbólico; interrompendo para preservar os arquivos.'
}
run() {
    local label=$1; shift
    info "$label"
    if "$@" >>"$LOG" 2>&1; then ok "$label"; else
        tail -n 15 "$LOG" >&2
        die "Falha: $label. Consulte $LOG. Não prossiga ignorando esse erro."
    fi
}
install_packages() {
    if [[ $PLATFORM == debian ]]; then
        run 'Atualizando a lista de pacotes' apt-get -o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 update
        run 'Instalando BIND, Apache e ferramentas de teste' env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=60 install -y bind9 bind9-utils dnsutils apache2 curl ca-certificates iproute2
    else
        local -a packages=(bind bind-utils httpd ca-certificates iproute policycoreutils)
        # Rocky pode trazer curl-minimal: ele já atende ao script; não o troque à força.
        if ! command -v curl >/dev/null; then packages+=(curl); fi
        run 'Instalando BIND, Apache e ferramentas de teste' dnf -y --setopt=timeout=30 --setopt=retries=2 install "${packages[@]}"
    fi
}
check_ports() {
    local line
    while IFS= read -r line; do
        [[ -n $line ]] || continue
        # systemd-resolved pode manter seu stub 127.0.0.53/54: não colide com os IPs configurados.
        [[ $line == *127.0.0.53:53* || $line == *127.0.0.54:53* ]] && continue
        if [[ $line != *'"named"'* && $line != *'"apache2"'* && $line != *'"httpd"'* ]]; then
            warn "$line"
            die 'Outro programa está usando a porta 53 ou 80. Resolva o conflito antes de instalar.'
        fi
    done < <(ss -H -lntup '( sport = :53 or sport = :80 )')
}
backup_path() {
    local path=$1
    [[ ! -L $path ]] || die "Arquivo gerenciado é um link simbólico: $path. Revise-o antes de continuar."
    SAVED_PATHS+=("$path")
    if [[ -e $path ]]; then
        SAVED_EXISTS+=(1)
        mkdir -p -- "$BACKUP/files$(dirname "$path")"
        cp -a -- "$path" "$BACKUP/files$path"
        printf 'EXISTIA %s\n' "$path" >>"$BACKUP/manifest.txt"
    else SAVED_EXISTS+=(0); printf 'NOVO %s\n' "$path" >>"$BACKUP/manifest.txt"; fi
}
begin_transaction() {
    if [[ ! -f $STATE_DIR/state ]]; then
        local path
        for path in "$WEB_ROOT" "$WEB_CONF" "$(dirname "$ZONE_FILE")"; do
            [[ ! -e $path ]] || die "Já existe $path sem identificação do assistente. Preservado: mova-o ou use uma VM limpa."
        done
    fi
    BACKUP=/var/backups/gs-linux/$(date +%Y%m%d-%H%M%S)-$$
    install -d -m 700 "$BACKUP"
    systemctl is-active --quiet "$DNS_SERVICE" && DNS_WAS_ACTIVE=1
    systemctl is-active --quiet "$WEB_SERVICE" && WEB_WAS_ACTIVE=1
    systemctl is-enabled --quiet "$DNS_SERVICE" && DNS_WAS_ENABLED=1
    systemctl is-enabled --quiet "$WEB_SERVICE" && WEB_WAS_ENABLED=1
    # Só começamos a alterar arquivos depois de concluir todos os backups.
    backup_path "$DNS_CONF"; backup_path "$ZONE_FILE"; backup_path "$WEB_CONF"
    backup_path "$WEB_ROOT"; backup_path "$STATE_DIR/state"
    TRANSACTION=1
}
rollback() {
    local i path item kind zone service status=0
    warn 'Falha detectada. Restaurando os arquivos e as regras alteradas nesta execução...'
    for ((i=${#SAVED_PATHS[@]}-1;i>=0;i--)); do
        path=${SAVED_PATHS[i]}
        rm -rf -- "$path" || status=1
        if [[ ${SAVED_EXISTS[i]} == 1 ]]; then cp -a -- "$BACKUP/files$path" "$path" || status=1; fi
    done
    for item in "${FW_ADDED[@]}"; do
        IFS='|' read -r kind zone service <<< "$item"
        case $kind in
            runtime) firewall-cmd --zone="$zone" --remove-service="$service" || status=1 ;;
            permanent) firewall-cmd --permanent --zone="$zone" --remove-service="$service" || status=1 ;;
            ufw) ufw --force delete allow to "$zone" port "${service%/*}" proto "${service#*/}" || status=1 ;;
        esac
    done
    if command -v restorecon >/dev/null; then restorecon -R "$DNS_CONF" "$(dirname "$ZONE_FILE")" "$WEB_ROOT" "$WEB_CONF" 2>/dev/null || true; fi
    if (( DNS_WAS_ACTIVE )); then systemctl restart "$DNS_SERVICE" || status=1; else systemctl stop "$DNS_SERVICE" || status=1; fi
    if (( WEB_WAS_ACTIVE )); then systemctl restart "$WEB_SERVICE" || status=1; else systemctl stop "$WEB_SERVICE" || status=1; fi
    if (( ! DNS_WAS_ENABLED )); then systemctl disable "$DNS_SERVICE" || status=1; fi
    if (( ! WEB_WAS_ENABLED )); then systemctl disable "$WEB_SERVICE" || status=1; fi
    if (( status )); then warn "A restauração teve falhas: consulte $LOG e os backups em $BACKUP."; else ok 'Arquivos anteriores restaurados. Pacotes instalados foram mantidos.'; fi
}
cleanup() {
    local result=$?
    trap - EXIT ERR INT TERM
    set +e
    if (( result != 0 && TRANSACTION )); then rollback >>"$LOG" 2>&1; warn "Instalação interrompida; restauração registrada em $LOG. Backup: $BACKUP"; fi
    [[ -z $WORK ]] || rm -rf -- "$WORK"
    exit "$result"
}

# Template fixado em um commit: atualizações do autor não mudam o conteúdo silenciosamente.
download_template() {
    local base=https://raw.githubusercontent.com/StartBootstrap/startbootstrap-bare/a9b948d6138fd3fbfaa6a26908ffbd47c50f9881 file
    install -d "$WORK/site/css" "$WORK/site/js" "$WORK/site/assets"
    for file in index.html css/styles.css js/scripts.js assets/favicon.ico; do
        run "Baixando template: $file" curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 90 --retry 2 "$base/dist/$file" -o "$WORK/site/$file"
        [[ -s $WORK/site/$file ]] || die "Download vazio: $file."
    done
    run 'Baixando licença do template' curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 90 --retry 2 "$base/LICENSE" -o "$WORK/site/LICENSE"
    run 'Baixando JavaScript do Bootstrap para acesso local' curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 90 --retry 2 'https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js' -o "$WORK/site/js/bootstrap.bundle.min.js"
    grep -qi '<!doctype html>' "$WORK/site/index.html" || die 'O arquivo baixado não parece ser o template HTML.'
    sed -i "s|https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js|js/bootstrap.bundle.min.js|;s|A Bootstrap 5 Starter Template|GS Linux: $DOMAIN|;s|A complete project boilerplate built with Bootstrap|Servidor DNS e Apache configurados|" "$WORK/site/index.html"
    printf '%s\n' "$DOMAIN" >"$WORK/site/gs-health.txt"
}
render_zone() {
    local output=$1 serial=$2 i value
    cat >"$output" <<EOF
; Gerado pelo GS Linux. Edite o script ou execute o assistente novamente.
\$TTL 300
@ IN SOA ns1.$DOMAIN. hostmaster.$DOMAIN. (
    $serial ; serial: aumenta a cada execução
    3600       ; refresh
    900        ; retry
    604800     ; expire
    300 )      ; negative cache
@ IN NS ns1.$DOMAIN.
EOF
    for i in "${!REC_NAME[@]}"; do
        value=${REC_VALUE[i]}
        case ${REC_TYPE[i]} in
            A) printf '%s IN A %s\n' "${REC_NAME[i]}" "$value" ;;
            CNAME) printf '%s IN CNAME %s.\n' "${REC_NAME[i]}" "$value" ;;
            MX) printf '%s IN MX %s %s.\n' "${REC_NAME[i]}" "${REC_PRIORITY[i]}" "$value" ;;
            TXT) value=${value//\\/\\\\}; value=${value//\"/\\\"}; printf '%s IN TXT "%s"\n' "${REC_NAME[i]}" "$value" ;;
        esac
    done >>"$output"
}
render_named() {
    local output=$1 cache
    if [[ $PLATFORM == debian ]]; then cache=/var/cache/bind; else cache=/var/named; fi
    cat >"$output" <<EOF
// GS Linux: servidor autoritativo para o laboratório, sem recursão pública.
options {
    directory "$cache";
    listen-on port 53 { 127.0.0.1; $SERVER_IP; };
    listen-on-v6 { none; };
    recursion no;
    allow-query { any; };
    allow-transfer { none; };
    dnssec-validation auto;
};
zone "$DOMAIN" IN {
    type master;
    file "$ZONE_FILE";
    allow-update { none; };
    notify no;
};
EOF
}
render_web() {
    cat >"$1" <<EOF
# GS Linux: arquivo ordenado antes dos outros sites para ser o padrão.
ServerName $DOMAIN
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN $SERVER_IP
    DocumentRoot "$WEB_ROOT"
    DirectoryIndex index.html
    <Directory "$WEB_ROOT">
        Options -Indexes -Includes -ExecCGI
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF
}
apply_configuration() {
    local serial previous=0
    serial=$(date +%s)
    if [[ -f $ZONE_FILE ]]; then previous=$(awk '/; serial:/ {print $1; exit}' "$ZONE_FILE"); fi
    if [[ $previous =~ ^[0-9]{1,10}$ ]] && (( previous >= serial )); then serial=$((previous+1)); fi
    (( serial < 4294967295 )) || die 'Serial DNS fora do limite; revise a zona existente.'
    render_zone "$WORK/db.zone" "$serial"
    render_named "$WORK/named.conf"
    render_web "$WORK/web.conf"
    run 'Validando sintaxe da zona DNS' named-checkzone "$DOMAIN" "$WORK/db.zone"
    run 'Validando sintaxe da configuração BIND' named-checkconf "$WORK/named.conf"
    install -d -m 750 -o root -g "$DNS_GROUP" "$(dirname "$ZONE_FILE")"
    install -m 640 -o root -g "$DNS_GROUP" "$WORK/db.zone" "$ZONE_FILE"
    install -m 640 -o root -g "$DNS_GROUP" "$WORK/named.conf" "$DNS_CONF"
    install -m 644 "$WORK/web.conf" "$WEB_CONF"
    # Remove apenas o diretório pertencente ao assistente, já incluído no backup.
    rm -rf -- "$WEB_ROOT"
    cp -a "$WORK/site" "$WEB_ROOT"
    find "$WEB_ROOT" -type d -exec chmod 755 {} +
    find "$WEB_ROOT" -type f -exec chmod 644 {} +
    if [[ $PLATFORM == rocky ]]; then
        run 'Aplicando os contextos padrão do SELinux' restorecon -RF "$DNS_CONF" "$(dirname "$ZONE_FILE")" "$WEB_CONF" "$WEB_ROOT"
    fi
    run 'Validando BIND e carregamento da zona' named-checkconf -z "$DNS_CONF"
    if [[ $PLATFORM == debian ]]; then run 'Validando Apache' apache2ctl configtest; else run 'Validando Apache' httpd -t; fi
}
configure_firewall() {
    local zone service iface ufw_status rules
    if systemctl is-active --quiet firewalld; then
        iface=$(ip -o -4 addr show | awk -v wanted="$SERVER_IP" '{split($4,a,"/"); if(a[1]==wanted){print $2;exit}}')
        zone=$(firewall-cmd --get-zone-of-interface="$iface" 2>/dev/null) || true
        if [[ -z $zone || $zone == 'no zone' ]]; then zone=$(firewall-cmd --get-default-zone); fi
        for service in dns http; do
            if ! firewall-cmd --zone="$zone" --query-service="$service" >/dev/null; then
                FW_ADDED+=("runtime|$zone|$service")
                run "Liberando $service no firewalld ($zone)" firewall-cmd --zone="$zone" --add-service="$service"
            fi
            if ! firewall-cmd --permanent --zone="$zone" --query-service="$service" >/dev/null; then
                FW_ADDED+=("permanent|$zone|$service")
                run "Persistindo $service no firewalld ($zone)" firewall-cmd --permanent --zone="$zone" --add-service="$service"
            fi
        done
    elif command -v ufw >/dev/null && ufw_status=$(LC_ALL=C ufw status) && [[ $ufw_status == *'Status: active'* ]]; then
        for service in 53/udp 53/tcp 80/tcp; do
            if ! grep -Eq "^${SERVER_IP//./\\.}[[:space:]]+${service}[[:space:]]+ALLOW[[:space:]]+Anywhere[[:space:]]*$" <<<"$ufw_status"; then
                # Regra para este IPv4: não altera regras IPv6 preexistentes.
                FW_ADDED+=("ufw|$SERVER_IP|$service")
                run "Liberando $service no UFW" ufw insert 1 allow to "$SERVER_IP" port "${service%/*}" proto "${service#*/}"
            fi
        done
    else
        # Não apagamos regras de um firewall personalizado nem iniciamos um firewall novo.
        if command -v nft >/dev/null; then
            rules=$(nft list ruleset) || die 'Não foi possível inspecionar as regras nftables.'
            [[ -z $rules ]] || die 'Há regras nftables personalizadas. Este assistente suporta firewalld ou UFW ativos; revise a VM.'
        fi
        if command -v iptables-save >/dev/null; then
            rules=$(iptables-save) || die 'Não foi possível inspecionar iptables.'
            if grep -Eq '^-A |^:[^ ]+ DROP ' <<<"$rules"; then die 'Há regras iptables personalizadas. Revise o firewall da VM antes de continuar.'; fi
        fi
        warn 'Nenhum firewall gerenciado ativo. Nenhuma regra foi apagada e nenhum firewall foi iniciado.'
    fi
}
verify_dns() {
    local name=$1 type=$2 expected=$3 answer
    answer=$(dig @"$SERVER_IP" "$name" "$type" +short +time=2 +tries=1)
    grep -Fxq -- "$expected" <<<"$answer" || die "DNS inesperado para $name $type. Esperado: $expected; recebido: $answer"
}
verify_services() {
    local i name expected response
    systemctl is-active --quiet "$DNS_SERVICE" || die 'O BIND não está ativo.'
    systemctl is-active --quiet "$WEB_SERVICE" || die 'O Apache não está ativo.'
    verify_dns "$DOMAIN" A "$SERVER_IP"
    verify_dns "ns1.$DOMAIN" A "$SERVER_IP"
    verify_dns "www.$DOMAIN" CNAME "$DOMAIN."
    verify_dns "$DOMAIN" NS "ns1.$DOMAIN."
    response=$(dig @"$SERVER_IP" "$DOMAIN" SOA +tcp +short +time=2 +tries=1)
    [[ $response == "ns1.$DOMAIN. hostmaster.$DOMAIN. "* ]] || die 'A consulta DNS por TCP falhou.'
    response=$(dig @"$SERVER_IP" "$DOMAIN" SOA +norecurse +time=2 +tries=1)
    [[ $response == *'status: NOERROR'* && $response =~ flags:.*[[:space:]]aa[\;\ ] ]] || die 'O DNS não respondeu como autoridade da zona.'
    for i in "${!REC_NAME[@]}"; do
        name=${REC_NAME[i]}; [[ $name == @ ]] && name=$DOMAIN || name=$name.$DOMAIN
        expected=${REC_VALUE[i]}
        case ${REC_TYPE[i]} in
            CNAME) expected+=. ;;
            MX) expected="${REC_PRIORITY[i]} $expected." ;;
            TXT) expected=${expected//\\/\\\\}; expected=${expected//\"/\\\"}; expected="\"$expected\"" ;;
        esac
        verify_dns "$name" "${REC_TYPE[i]}" "$expected"
    done
    # --noproxy impede que os testes locais sejam enviados a um proxy corporativo.
    response=$(curl --noproxy '*' --fail --silent --show-error --max-time 10 --resolve "$DOMAIN:80:$SERVER_IP" "http://$DOMAIN/gs-health.txt")
    [[ $response == "$DOMAIN" ]] || die 'O virtual host não está entregando o site configurado.'
    response=$(curl --noproxy '*' --fail --silent --show-error --max-time 10 "http://$SERVER_IP/gs-health.txt")
    [[ $response == "$DOMAIN" ]] || die 'O template não é a página padrão por IP.'
    curl --noproxy '*' --fail --silent --show-error --max-time 10 "http://$SERVER_IP/" -o "$WORK/served.html"
    cmp -s "$WEB_ROOT/index.html" "$WORK/served.html" || die 'O HTML servido não corresponde ao template instalado.'
    ok 'DNS UDP/TCP, autoridade da zona, registros e página padrão HTTP passaram nos testes locais.'
}
save_state() {
    { printf '%s\n%s\n' "$DOMAIN" "$SERVER_IP"; local i
      for i in "${!REC_NAME[@]}"; do printf '%s\t%s\t%s\t%s\n' "${REC_NAME[i]}" "${REC_TYPE[i]}" "${REC_PRIORITY[i]:--}" "${REC_VALUE[i]}"; done
    } >"$STATE_DIR/state"
    chmod 600 "$STATE_DIR/state"
}
load_state() {
    [[ -f $STATE_DIR/state ]] || die 'Ainda não existe instalação registrada. Execute sudo bash gs-linux.sh.'
    local name type priority value
    { IFS= read -r DOMAIN; IFS= read -r SERVER_IP
      if ! valid_domain "$DOMAIN" || ! valid_ipv4 "$SERVER_IP"; then die 'Estado salvo inválido.'; fi
      REC_NAME=(); REC_TYPE=(); REC_PRIORITY=(); REC_VALUE=()
      while IFS=$'\t' read -r name type priority value; do
          REC_NAME+=("$name"); REC_TYPE+=("$type"); REC_PRIORITY+=("${priority/-/}"); REC_VALUE+=("$value")
      done
    } <"$STATE_DIR/state"
}

# PONTO DE EXTENSÃO PARA A PROVA: crie funções para as tarefas solicitadas.
# Chame-as aqui. Cada função deve validar seu resultado e usar run/info/ok.
# Se alterar novos arquivos, inclua backup_path ANTES da primeira alteração.
extra_tasks() { :; }

main() {
    case ${1:-} in
        --demo) MODE=demo ;; --check) MODE=check ;; --help|-h) help_text; return ;;
        '') ;; *) help_text; die "Opção desconhecida: $1" ;;
    esac
    (( $# <= 1 )) || die 'Use apenas uma opção por vez.'
    colors; banner; detect_platform
    if [[ $MODE == demo ]]; then
        warn 'DEMONSTRAÇÃO: nenhuma instalação, download ou alteração será feita.'
        wizard
        info 'Na instalação real: pacotes → template → backups → configuração → firewall → testes.'
        ok 'Demonstração concluída. Nenhum serviço foi instalado.'
        return
    fi
    preflight
    WORK=$(mktemp -d /tmp/gs-linux.XXXXXXXX)
    trap cleanup EXIT
    trap 'printf "[ERRO] Etapa interrompida na linha %s.\n" "$LINENO" >&2' ERR
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if [[ $MODE == check ]]; then load_state; verify_services; return; fi
    wizard
    install -d -m 700 "$STATE_DIR"
    LOG=$STATE_DIR/install-$(date +%Y%m%d-%H%M%S)-$$.log
    : >"$LOG"; chmod 600 "$LOG"
    info "Log detalhado: $LOG"
    # Pacotes ficam fora da transação: desinstalá-los automaticamente poderia quebrar outros usos.
    if command -v ss >/dev/null; then check_ports; fi
    install_packages
    ip_is_local || die "O IP $SERVER_IP não pertence a esta máquina. Execute novamente e escolha o IP correto."
    check_ports
    download_template
    begin_transaction
    apply_configuration
    configure_firewall
    run 'Ativando BIND na inicialização' systemctl enable "$DNS_SERVICE"
    run 'Ativando Apache na inicialização' systemctl enable "$WEB_SERVICE"
    run 'Iniciando/reiniciando BIND' systemctl restart "$DNS_SERVICE"
    run 'Iniciando/reiniciando Apache' systemctl restart "$WEB_SERVICE"
    verify_services
    extra_tasks
    save_state
    TRANSACTION=0
    printf '\n%sPRONTO! TESTES LOCAIS CONCLUÍDOS.%s\n' "$GREEN$BOLD" "$RESET"
    info "Abra pelo IP: http://$SERVER_IP/"
    info "Para usar http://$DOMAIN/ em outro computador, ele deve consultar o DNS $SERVER_IP."
    info 'O domínio é do laboratório; não é registrado na Internet. Roteador e firewall externo não são alterados.'
    info "Backup: $BACKUP | Log: $LOG"
    info 'Para testar novamente: sudo bash gs-linux.sh --check'
}

# Permite que os testes carreguem as funções sem iniciar uma instalação.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
