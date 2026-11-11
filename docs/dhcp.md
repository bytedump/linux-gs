# DHCP depois da main

Execute a instalação DNS/Web na main primeiro. Em seguida:

```bash
git fetch origin
git switch feat/dhcp-lab-menu
sudo bash dhcp-linux.sh
```

O menu independente tem instalação/configuração, status/logs/concessões e roteiro. Não é necessário reaplicar gs-linux.sh.

Antes da aplicação, configure a interface do laboratório das três VMs na mesma Rede Interna no VirtualBox, preservando o IPv4 fixo /24 do servidor DNS para manter a configuração da main válida. Mantenha NAT para instalar pacotes, sem servir DHCP nessa interface. O script solicita a interface e recusa a interface com rota padrão; a confirmação de Rede Interna é necessária porque o Linux convidado não identifica o modo do VirtualBox.

O assistente gera dhcpd.conf com os valores do exercício, vincula o serviço à interface escolhida e oferece reserva por MAC. Instala ISC DHCP em Debian 11–13 ou Rocky 8/9; Rocky 10 precisa de Kea e não está coberto. Cria backup e tenta restaurar configuração/estado em falha de aplicação. Pacotes instalados permanecem.

Libere UDP/67 no firewall da interface de laboratório. A configuração do firewall é manual nesta versão. O gateway .1 precisa existir; o script não cria roteador. Confirme DNS acessível, concessões Linux/Windows e reserva .222 no cliente. Reserva fixed-address não precisa aparecer em dhcpd.leases. Não confunda serviço ativo com concessão comprovada.

Validação local: bash -n e tests/dhcp.sh. Instalação real, SELinux, firewall e concessões em duas VMs clientes ainda exigem ensaio no laboratório.

## Acesso pelo menu principal

Nesta branch, `sudo bash gs-linux.sh` mantém as opções existentes e acrescenta **7 — Submenu DNS + Web / DHCP**. O submenu permite instalar DNS/Apache, verificar DNS/Apache e abrir o menu exclusivo de DHCP. Atalhos: `--network` para o submenu, `--dhcp` para DHCP. `--install`, `--check`, `--status` e `--report` continuam exclusivos do fluxo original de DNS/Apache.

Cada módulo é executado em outro processo Bash. Uma saída com erro ou arquivo DHCP ausente é informada e devolve o controle ao submenu; traps, variáveis e rollback do módulo não são carregados no processo do menu. Isso não substitui a validação da rede: mudar IPs/adaptadores manualmente pode afetar os serviços existentes.

Teste `tests/module-isolation.sh`: simula DHCP encerrando com código 42 e trap, módulo ausente e roteamento das ações; verifica retorno ao menu. Não prova disponibilidade de DNS/Apache em VMs reais durante uma falha de instalação DHCP.
