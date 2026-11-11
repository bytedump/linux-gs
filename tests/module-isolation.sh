#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
cp gs-linux.sh "$fixture/"
# Falha e traps no filho não podem interromper o submenu/pai.
cat > "$fixture/dhcp-linux.sh" <<'CHILD'
#!/usr/bin/env bash
trap 'echo TRAP_DO_FILHO' EXIT
exit 42
CHILD
printf '7\n3\n0\n0\n' | bash "$fixture/gs-linux.sh" > "$fixture/result"
grep -q 'código 42' "$fixture/result"
[[ $(grep -c 'O QUE VOCÊ QUER FAZER?' "$fixture/result") == 2 ]]
[[ $(grep -c 'DNS / WEB E DHCP' "$fixture/result") == 2 ]]
rm "$fixture/dhcp-linux.sh"
printf '7\n3\n0\n0\n' | bash "$fixture/gs-linux.sh" > "$fixture/missing"
grep -q 'Módulo ausente' "$fixture/missing"
bash "$fixture/gs-linux.sh" --help > "$fixture/help"
grep -q -- '--install' "$fixture/help"
# A ação DNS continua encaminhada ao instalador original, sem carregar DHCP.
source ./gs-linux.sh
calls=''
run_lab_module() { calls+="$*|"; }
network_menu >/dev/null <<'INPUT'
1
2
3
0
INPUT
[[ $calls == 'gs-linux.sh --install|gs-linux.sh --status|dhcp-linux.sh|' ]]
echo 'Isolamento: falha 42, módulo ausente, retorno ao menu e roteamento passaram.'
