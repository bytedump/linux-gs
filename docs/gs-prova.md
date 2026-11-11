# GS 1TDCPV — Rocky

A branch gs-prova-1.2.5 parte da versão 1.2.4 e acrescenta gs-prova.sh, um script único com o instalador completo. O gs-linux.sh original e a reserva-1.2.4 continuam disponíveis. DHCP não faz parte da GS.

## Homologação

Crie a VM `Seu nome completo - Homologação`. Use console do VirtualBox, com Host-Only para o laboratório e NAT para Internet. Escolha um IP livre na mesma rede do cliente Windows; a sugestão é 192.168.56.10/24 (ou .10 na rede já presente). Não mantenha duas VMs ligadas com o mesmo IP.

```bash
git fetch origin
git switch gs-prova-1.2.5
sudo bash gs-prova.sh --prepare
sudo bash gs-prova.sh --exam
```

A preparação identifica uma candidata Ethernet sem rota padrão, mostra as interfaces, pergunta/valida os parâmetros e salva gs-prova.conf. Padrão de domínio: vladmir.lab. Confirme a interface Host-Only no VirtualBox. Este perfil exige duas interfaces: laboratório e NAT/rota padrão separadas. A preparação não configura a VM; --exam é quem aplica o IP persistente via NetworkManager e todo o deploy, sem perguntas.

O script cria um perfil Ethernet persistente com IPv4 manual /24, sem gateway na interface Host-Only, preservando a saída NAT. Não precisa de MAC fixo do clone. Instala DNS autoritativo e Apache, bloqueia AXFR e recursão, oculta versão, habilita serviços, baixa o template da Internet e confere hashes. Se download falhar, não aceita fallback local para esta GS. Configuração e verificações precisam passar antes do reboot. As verificações finais são feitas dentro da transação de DNS/HTTP; falhas tentam restaurar arquivos/serviços e perfil de rede anterior. Pacotes instalados permanecem.

O script reinicia automaticamente após sucesso. Após boot:

```bash
sudo bash gs-prova.sh --status
```

## Produção e Windows

Combine a criação do clone com o professor. Nome: `Seu nome completo - Produção`. Leve gs-prova.sh e o gs-prova.conf preparado; execute `sudo bash gs-prova.sh --exam`. O cliente Windows deve estar na mesma Host-Only e usar o IP do servidor como DNS. Acesse `http://www.vladmir.lab/` (ou seu domínio escolhido) e tire print de tela inteira. DNS é autoritativo sem recursão: não oferece resolução geral da Internet.

Entregas em entrega/: PDF e Word do script original e do modificado; Word com margens de 0,5 polegada (estreitas). PDFs foram gerados diretamente do mesmo código para leitura; se a exigência for exportação pelo Word, abra o DOCX e use Exportar PDF. Não há prints simulados: capture a validação real do professor e o acesso Windows. Caso altere o script posteriormente, regenere os documentos antes de enviar.

## Validação e limites

Sintaxe Bash e testes/prova.sh (arquivo tests/prova.sh) validam os arquivos DNS/HTTP e a detecção de falhas simuladas: versão HTTP exposta, AXFR liberado, boot desabilitado, IP dinâmico e template local. Os 186 testes anteriores verificam o instalador original. A instalação Rocky real, NetworkManager, firewall, reinício e acesso do Windows precisam ser comprovados na VM Homologação. Não se declarou essa execução como validada neste ambiente.

## Correção 1.2.6: Apache preconfigurado na porta 81

O Rocky do laboratório apresentou `Server configured, listening on: port 81`. O perfil GS agora guarda backup das diretivas Listen nos arquivos padrão `/etc/httpd/conf/httpd.conf` e `/etc/httpd/conf.d/*.conf`, remove essas declarações e centraliza `Listen 80` no site gerenciado. O VirtualHost sozinho não muda a porta de escuta. A validação Apache permanece obrigatória e o rollback restaura os arquivos alterados. O teste de regressão reproduz Listen 81 e verifica a declaração única 80 e backups restauráveis. O PDF/DOCX modificado foi regenerado.
