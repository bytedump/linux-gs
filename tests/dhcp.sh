#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../dhcp-linux.sh"
valid_ip 192.168.56.10
! valid_ip 192.168.56.999
! valid_ip '1.2.3.4;reboot'
prefix=192.168.56; dns=192.168.56.10; domain=aluno.fiap; server_name=lab; mac=08:00:27:12:34:56
config=$(render)
for expected in 'default-lease-time 1200;' 'max-lease-time 2400;' 'range 192.168.56.100 192.168.56.199;' 'fixed-address 192.168.56.222;' 'option domain-name "atribuicao.manual";'; do
    grep -Fq "$expected" <<< "$config"
done
mac=''; ! render | grep -q 'host windows'
printf '0\n' | bash "$(dirname "$0")/../dhcp-linux.sh" >/dev/null
echo 'Validação de entradas, configuração e saída do menu passaram.'
