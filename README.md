# GS Linux — DNS e Web sem decorar comandos

Um único script Bash para **Debian e Rocky Linux**, com menus em português, cores,
banner ASCII, validação das respostas e confirmação antes de alterar a máquina.
Instala BIND e Apache e publica um template HTML (baixado e verificado por SHA-256, com cópia local de reserva).

**Versão 1.2.3:** perfil das atividades DNS Primary/Secondary: domínio `nome.fiap`,
`www` como A, `intranet` como CNAME, zona reversa /24 com PTR e transferência para
uma segunda VM. [Passo a passo das duas VMs e demonstração](docs/atividade-dns.md).

## Rocky sem interface gráfica: como levar o script para a VM

**Não precisa instalar Firefox.** No terminal do seu **clone linkado Rocky**, com
Internet e uma conta com `sudo`, execute uma linha por vez. Se alguma falhar, pare
e consulte o tutorial abaixo antes de continuar:

```bash
sudo dnf install -y git
cd ~
git clone https://github.com/bytedump/linux-gs.git
cd linux-gs
bash gs-linux.sh --demo
```

O Git baixa **a pasta inteira**, incluindo `template/`. `--demo` serve para treinar;
para instalar de verdade, já dentro dessa pasta, use `sudo bash gs-linux.sh --install`.
Se entrou como `root`, retire `sudo` dos comandos.

**[Tutorial completo: clone linkado, rede, download pelo terminal e transferência
pelo Windows se o GitHub não abrir na VM](docs/colocar-na-vm.md).**

## Menu principal: aprender, treinar e comprovar

```bash
bash gs-linux.sh
```

O script abre este menu antes de fazer qualquer instalação:

```text
1) Aprender: glossário e exemplos
2) Orientador: o professor pediu...
3) Treinar a instalação (demonstração, sem alterações)
4) Instalar/configurar DNS + Web nesta VM
5) Comprovar: serviços, portas, DNS, Web e firewall
6) Salvar relatório de comprovação em texto
0) Sair
```

**Começando do zero? Use 1 e leia “DNS” e “Registros”.** O guia explica termos,
mostra exemplos, sugere como explicar o resultado ao professor e apresenta comandos
de consulta. Inclui DHCP, rede, firewall, SELinux, serviços, logs e possíveis tarefas.
O texto está dentro do próprio `gs-linux.sh`: funciona offline, sem instalar pacotes.

Na opção **2**, você pode escrever “o professor pediu algo sobre DHCP”. O orientador
identifica palavras-chave, pede confirmação do assunto e oferece caminhos para
planejar a alteração, demonstrar o resultado ou investigar um erro. É um roteiro
local, não uma IA conectada; não executa o texto digitado nem inventa uma solução
para qualquer enunciado. **DHCP e as tarefas extras não são instalados pelo guia.**

Também há atalhos:

```bash
bash gs-linux.sh --learn
bash gs-linux.sh --tutor
```

Durante o cadastro de registros DNS, a opção **6** explica A/CNAME/MX/TXT sem perder
as respostas já preenchidas. Enter retorna ao cadastro.

O terminal usa ciano para perguntas/opções, magenta para seções, azul para
explicações/comandos, verde para sucesso, amarelo para avisos e vermelho para erros.
As palavras e rótulos continuam visíveis quando as cores estão desativadas.

## Comece pela demonstração

Abra um terminal na pasta onde está `gs-linux.sh` e execute:

```bash
bash gs-linux.sh --demo
```

Esse modo **não instala, não baixa e não altera configurações**. Serve para aprender
os menus. Pressione Enter para aceitar o valor entre colchetes. As opções são
numéricas; não é preciso decorar nomes de registros.

Para uma primeira tentativa, use `aluno.fiap`, escolha **1 — Primário**, selecione
o IP da interface Host-Only e informe `0` para usar só uma VM. Aceite a rede reversa
/24 e conclua os registros com `0`. No resumo, `S` continua, `R` refaz e `N` cancela.

## Instalar na VM da prova

Use uma VM completa, com systemd, Internet e um IPv4 que permaneça estável.
Compatibilidade prevista: **Debian 11, 12 e 13; Rocky Linux 8, 9 e 10**.
Não é um instalador para WSL sem systemd, macOS ou contêineres comuns.

Na atividade com duas placas, prepare Host-Only para as VMs conversarem e NAT para
Internet; configure IPs fixos distintos na Host-Only. O script lista as interfaces
e sugere `192.168.56.x` antes da NAT `10.0.2.x`, mas não altera adaptadores do
VirtualBox nem configura o IP fixo do sistema. Confira a rede pedida na sua turma.

```bash
sudo bash gs-linux.sh --install
```

Ou abra `sudo bash gs-linux.sh` e escolha **4**. Se estiver conectado como `root`,
use `bash gs-linux.sh --install`. Se não tem `sudo` nem
acesso a root, precisará da conta administrativa fornecida pelo professor.

O instalador vai:

1. Identificar a distribuição e pedir domínio, papel, IP e rede reversa /24.
2. No primário, pedir o IP opcional do secundário e permitir editar os registros.
   No secundário, pedir o IP do primário e receber dele as duas zonas.
3. Mostrar o resumo e pedir confirmação.
4. Instalar pacotes, baixar o template e guardar backups.
5. Configurar BIND, Apache e as permissões necessárias.
6. Liberar DNS e HTTP no firewalld ou UFW, se estiverem ativos.
7. Ativar os serviços e testar DNS direto/reverso e HTTP de verdade. No secundário,
   aguardar até 45 segundos pela transferência e comparar os SOAs das duas zonas.

No Debian instalado por DVD/ISO, o APT pode ainda apontar para `cdrom:` e apresentar
“Please use apt-cdrom” ou “does not have a Release file”. A partir da versão **1.1.1**,
o script prepara as fontes antes da instalação: desativa entradas de mídia em
`sources.list`, `.list` e `.sources`, preservando mirrors e opções já configurados.
Se não houver fonte HTTP/HTTPS de pacotes binários ativa, adiciona as fontes oficiais
da versão instalada (Debian principal, atualizações e segurança, componente `main`).
Não mistura Debian 11/12/13 nem altera fontes pela Internet existentes.

O backup das fontes fica em `/var/backups/gs-linux/apt-DATA-HORA.XXXXXXXX/`, com um
manifesto dos caminhos. Se a atualização falhar, ou o processo for interrompido
antes de validá-la, o assistente tenta restaurar essas fontes. Após uma atualização
bem-sucedida, o reparo do APT permanece, mesmo se uma etapa posterior falhar.
As fontes adicionadas usam o transporte HTTP oficial do Debian, permitindo obter
também `ca-certificates` numa instalação mínima; a assinatura do arquivo Release e
os hashes dos pacotes continuam obrigatórios, com o chaveiro oficial Debian.
Nenhuma opção `trusted=yes` ou de aceitação de pacotes sem autenticação é ativada.

**Atenção ao resumo:** a configuração principal do BIND será substituída pelo DNS
do laboratório. O site passa a ser o padrão do Apache; os arquivos de outros sites
não são apagados. Use a VM de exercícios, não um servidor com serviços de terceiros.

O template é **Bare, do Start Bootstrap**, licença MIT, fixado em um commit. HTML,
CSS, JavaScript, favicon e licença são baixados; o JavaScript do Bootstrap também
fica local. Depois da instalação, a página não depende de uma CDN para funcionar.
O download do template usa arquivos individuais; nenhum instalador externo é executado.

**Template verificado e cópia local.** O script traz os **SHA-256** dos seis arquivos do
template e confere tudo o que baixa. Se o download falhar, ou se um arquivo não bater com
o hash, ele avisa e usa a **cópia local** da pasta `template/`, que fica ao lado do
`gs-linux.sh` e passa pela mesma verificação. Só os arquivos listados são publicados; um
arquivo extra na pasta é ignorado. Sem a pasta e sem Internet, a instalação é interrompida.
**Leve a pasta `template/` junto com o script**: copiar só o `.sh` ainda funciona, mas
sem plano B para o template. Isso **não** torna a instalação offline: BIND e Apache
continuam sendo instalados pelos repositórios online. No Debian, o script desativa fontes
`cdrom:` e exige que a atualização dos repositórios funcione; uma instalação completamente
offline não é suportada.
Para atualizar a cópia, baixe os mesmos arquivos da versão fixada e atualize os hashes
na lista `TEMPLATE_SHA256`, no início do script.

## O que responder nos menus

Imagine que a VM tenha o endereço `192.168.56.10`:

| Pergunta | Exemplo | Significado |
| --- | --- | --- |
| Domínio | `aluno.fiap` | Nome do laboratório; sem `http://` |
| Papel desta VM | `1` | Primário cria as zonas; secundário recebe cópias |
| IPv4 desta máquina | `192.168.56.10` | IP da interface da VM, não o do computador hospedeiro |
| IP reservado ao secundário | `192.168.56.20` | Outra VM; use `0` se só tiver uma |
| Rede reversa | `192.168.56.0/24` | Mesma rede informada nas duas instalações |
| Nome de registro | `loja` | O script cria `loja.aluno.fiap` |
| Nome `@` | `@` | Representa o próprio `aluno.fiap` |
| Destino CNAME/MX | `mail.aluno.fiap` | Nome completo; não use um IP |

No primário, o script propõe esta base editável:

| Nome | Tipo | Destino |
| --- | --- | --- |
| `aluno.fiap` (`@`) | A | IP da VM |
| `ns1.aluno.fiap` | A | IP da VM |
| `www.aluno.fiap` | A | IP do secundário, ou do primário quando usar só uma VM |
| `intranet.aluno.fiap` | CNAME | `www.aluno.fiap` |
| `aluno.fiap` | NS | `ns1.aluno.fiap` |
| `aluno.fiap` | SOA | Metadados da zona, gerados automaticamente |

Use **7** para editar o valor de um registro e **5** para remover. `ns1` é protegido
porque sustenta SOA/NS; seu IP acompanha o primário informado. Para mudar nome/tipo,
remova e cadastre novamente, removendo antes aliases/MX dependentes.

Você pode cadastrar estes tipos:

| Tipo | Para que serve | Exemplo |
| --- | --- | --- |
| A | Nome para IPv4 | `mail` → `192.168.56.10` |
| CNAME | Apelido para outro nome | `correio` → `mail.aluno.fiap` |
| MX | Servidor que recebe e-mail do domínio | `@` → `mail.aluno.fiap`, prioridade `10` |
| TXT | Informação em texto | `@` → `Trabalho de Linux` |

Cadastre o **A do destino antes do CNAME ou MX**. Neste assistente, esses destinos
devem estar na própria zona e ter um A; aliases externos e cadeias de CNAME não são
aceitos. Isso evita loops e destinos sem resolução durante o exercício.
MX não instala e-mail. Prioridade menor significa preferência maior.
TXT aceita até 200 caracteres ASCII visíveis, incluindo espaços e aspas.
Os **PTRs são automáticos**: um por IP dentro da rede /24 selecionada. Se vários nomes
compartilham um IP, vale o primeiro cadastrado, e `ns1` tem prioridade (no primário, `10 IN
PTR ns1.<dominio>.`). Vários PTRs para um IP seriam válidos, mas um nome principal é mais
fácil de explicar. CNAME não ganha PTR próprio. Um A externo, como `webmail → 10.200.200.200`, não entra na zona
reversa de `192.168.56.0/24`.

SOA usa os valores da atividade: refresh `28800`, retry `14400`, expire `86400` e
minimum `600`. Serial segue `AAAAMMDDnn`, começando em `00`; cada reaplicação o
aumenta. Relógio anterior ao serial salvo ou mais de 100 versões no dia interrompem
a publicação com aviso. Migração de um serial epoch antigo também preserva o aumento.
AAAA, SRV, reversa de outros prefixos, servidor de e-mail e HTTPS não estão incluídos.

Para trocar domínio/IP/papel, escolha `R` no resumo ou execute
novamente o assistente. A reaplicação substitui a configuração gerenciada pela
lista nova; os registros extras anteriores não são importados automaticamente.
Estado salvo na versão 1.1 continua legível pelo painel, que avisa sobre a reversa
ausente; reexecutar a instalação aplica o perfil novo com backup dos arquivos antigos.

## Conferir depois de instalar

Para apresentar ao professor, escolha **5** no menu ou use:

```bash
sudo bash gs-linux.sh --status
```

O painel mostra o comando, a resposta e o resultado de cada teste, incluindo:

- Sintaxe da configuração BIND/Apache; serviços ativos e habilitados no boot.
- Portas UDP/53, TCP/53 e TCP/80 e os processos em escuta.
- IP salvo ainda presente na VM; NS e cada registro salvo; SOA autoritativo por TCP.
- PTRs, `nslookup` NS/SOA/A/MX e logs recentes do BIND; com secundário configurado,
  compara SOA/serial dos dois servidores para as zonas direta e reversa.
- No secundário, confirma que os arquivos das duas zonas foram recebidos.
- Resposta HTTP pelo IP e pelo domínio; conteúdo HTML e acesso ao CSS.
- firewalld: zona da interface e permissões atuais/permanentes; UFW: regras locais.
- No Rocky, estado e contextos do SELinux.

**Um erro não interrompe os outros testes.** Verde significa que aquele teste
passou. Vermelho indica falha. Amarelo indica aviso ou algo não verificado, como
falta de ferramenta, permissão ou configuração salva. Firewall inativo não ganha
um “OK”. Consultas de regras/contextos marcadas “inspeção” exibem evidências para
análise; não comprovam, por si, que o tráfego da rede é permitido.

O painel só consulta: não reinicia serviços, altera configurações nem abre portas.
Sem `sudo`, ele pode mostrar resultados parciais. Seu código de saída é **0** para
verificações locais completas, **1** se houve falhas e **2** se ficaram avisos ou
verificações incompletas. O teste a partir de outro computador fica explicitamente
pendente, mesmo quando todos os testes locais passam.

Para salvar as evidências da demonstração, escolha **6** ou use:

```bash
sudo bash gs-linux.sh --report
```

O script informa o caminho de um arquivo `/tmp/gs-linux-relatorio.XXXXXXXX.txt`,
sem cores, legível apenas pelo usuário que o gerou (root se usou sudo). Leia com
`sudo less CAMINHO-EXIBIDO` e copie para um local permanente se precisar guardar
para a entrega: `/tmp` pode ser limpo ao reiniciar. O relatório inclui IPs/domínio
do laboratório e regras do firewall. Mantém o mesmo código de saída do painel.

Para uma checagem rápida que para na primeira falha, continua disponível:

```bash
sudo bash gs-linux.sh --check
```

Esse comando relê os registros salvos e consulta o BIND, incluindo UDP e TCP.
Também verifica se o HTTP entrega o HTML instalado, pelo IP e pelo domínio.
Não instala nem modifica configurações.

Para estudar os comandos por trás do teste, substitua o IP/domínio pelos seus:

```bash
dig @192.168.56.10 aluno.fiap A
dig @192.168.56.10 www.aluno.fiap A
dig @192.168.56.10 intranet.aluno.fiap CNAME
dig @192.168.56.10 -x 192.168.56.20
dig @192.168.56.10 aluno.fiap MX
dig @192.168.56.10 aluno.fiap TXT
dig @192.168.56.10 aluno.fiap SOA +tcp
curl --noproxy '*' http://192.168.56.10/
curl --noproxy '*' --resolve aluno.fiap:80:192.168.56.10 http://aluno.fiap/
```

O `@IP` do `dig` significa **consultar aquele servidor DNS**. O `--resolve` do curl
permite testar o site pelo domínio sem modificar o DNS do seu computador.

Abra `http://IP-DA-VM/` no navegador. Para abrir `http://aluno.fiap/` em outro
computador, ele precisa usar a VM como DNS para essa zona. O script configura o
servidor inteiro; não altera automaticamente computadores clientes, DHCP,
roteadores, encaminhamentos do hipervisor ou firewalls do provedor.

O DNS é **autoritativo, sem recursão**: responde pela sua zona, não substitui um
resolvedor geral para navegar na Internet. Use consultas explícitas com `dig @IP`
para a demonstração. O sufixo `.fiap` segue o enunciado local e não registra domínio
público; para laboratórios genéricos, `.test` é um sufixo reservado a testes.

## O que muda entre Debian e Rocky

| Item | Debian | Rocky Linux |
| --- | --- | --- |
| Instalador de pacotes | `apt-get` | `dnf` |
| Serviço DNS | `named` (pacote `bind9`) | `named` (pacote `bind`) |
| Serviço Web | `apache2` | `httpd` |
| Configuração BIND | `/etc/bind/named.conf` | `/etc/named.conf` |
| Diretório das zonas primárias | `/var/lib/bind/gs-linux/` | `/var/named/gs-linux/` |
| Diretório das zonas secundárias | `/var/cache/bind/gs-linux/` | `/var/named/slaves/gs-linux/` |
| Site Apache | `/etc/apache2/sites-available/000-000-gs-linux.conf` + `a2ensite` | `/etc/httpd/conf.d/00-gs-linux.conf` |
| Arquivos do site | `/var/www/gs-linux` | `/var/www/gs-linux` |

O arquivo direto se chama `DOMINIO.zone`; o reverso, por exemplo,
`56.168.192.in-addr.arpa`. O secundário usa uma pasta gravável pelo BIND, inclusive
com os contextos padrão de `slaves` no Rocky. Apache usa `ServerTokens Prod` e
`ServerSignature Off` para não divulgar sua versão.

No Rocky, `restorecon` aplica os contextos padrão do SELinux. O script **não usa
`setenforce 0`**. Se firewalld está ativo, libera os serviços `dns` e `http` na zona
da interface escolhida, tanto em execução quanto na configuração permanente.
No UFW ativo, cria permissões para o IPv4 do servidor. As portas são 53/UDP,
53/TCP e 80/TCP. Não desativa nem inicia um firewall novo. Regras personalizadas de
nftables/iptables sem um desses gerenciadores interrompem a instalação.

## Se aparecer um erro

Leia a mensagem `[ERRO]`: ela indica a etapa e o caminho do log. Logs ficam em
`/var/lib/gs-linux/` e backups em `/var/backups/gs-linux/`, protegidos para root.

| Mensagem/situação | O que fazer |
| --- | --- |
| Falta permissão | Execute com `sudo` ou na conta root |
| systemd não está ativo | Use uma VM completa com a distribuição prevista |
| IP não pertence à máquina | Veja `ip -4 addr` e refaça a escolha |
| Porta 53 ou 80 ocupada | Confira o programa mostrado; não mate serviços sem saber o que são |
| Erro no download/pacotes | Confira Internet, DNS, repositórios e o log; depois execute novamente |
| `cdrom:`, `apt-cdrom` ou DVD sem `Release` | Atualize para a versão 1.1.1 ou posterior e execute novamente; o reparo de fontes APT é automático |
| CNAME/MX sem destino | Primeiro crie o registro A do destino |
| Transferência não confirmada | Confira domínio/rede iguais, primário ativo, IP do secundário autorizado e TCP/53 entre as VMs |
| Primário pronto, painel falha ao consultar secundário | Configure/inicie a segunda VM e repita o painel nas duas |
| Serial futuro ou limite atingido | Confira a data da VM e o serial salvo; não diminua o serial manualmente |
| Teste local passa, outro PC não acessa | Confira rede da VM, firewall externo e configuração DNS do cliente |

Se a falha acontecer após o início da alteração dos arquivos, o script tenta
restaurar os arquivos anteriores, as regras que adicionou e o estado dos serviços
capturado após a instalação dos pacotes. O log registra falhas na restauração.
**Pacotes instalados não são desinstalados automaticamente.** Queda de energia ou
`kill -9` não permitem executar a recuperação; os backups continuam disponíveis.
Eles contêm `manifest.txt` e os caminhos originais dentro de `files/`.

O script nunca considera falha de teste como sucesso. Recursão e atualização
dinâmica ficam desativadas. No primário, a transferência é permitida **somente ao
IP do secundário informado**, com `also-notify` e `notify yes`; sem secundário,
transferências e notify ficam desativados. Não há TSIG neste perfil de rede isolada.

## Entender o código para as três tarefas surpresa

Leia as funções nesta ordem:

1. `wizard`: perguntas e resumo; `valid_*`: validação das respostas.
2. `install_packages`: instalação específica de cada distribuição.
3. `render_zone`, `render_reverse`, `render_named`, `render_web`: conteúdo dos arquivos.
4. `apply_configuration`: validação e publicação dos arquivos.
5. `configure_firewall`: portas necessárias.
6. `verify_services`: consultas DNS e requisições HTTP.
7. `extra_tasks`: local reservado para chamar as três tarefas da prova.

Uma função agrupa comandos com um nome. Exemplo **apenas ilustrativo**:

```bash
minha_tarefa() {
    info 'Explicação do que esta etapa fará'
    # Comandos pedidos pelo professor e testes do resultado entram aqui.
}
```

Depois chame `minha_tarefa` dentro de `extra_tasks`. Use `run 'Descrição' comando`
para registrar saída e interromper em caso de erro. Se alterar um arquivo novo,
chame `backup_path /caminho/do/arquivo` antes. As tarefas surpresa ainda precisam
ser implementadas conforme o enunciado; esse ponto de extensão não as adivinha.

## Testes e limites da validação

```bash
bash tests/unit.sh
bash tests/learning-status.sh
bash tests/apt-sources.sh  # requer apt-get; não usa rede nem altera /etc
bash tests/dns-lab.sh
bash tests/template.sh   # template/hashes/cópia local e PTR único; sem rede
```

Os testes locais cobrem entrada inválida, conflitos entre registros, escape de TXT,
caminhos por distribuição, estado salvo, restauração, cancelamento e demonstração.
Também cobrem guia/orientador sem root, ajuda contextual, entrada literal, falhas
acumuladas no painel, ferramentas ausentes e exportação de evidências.
Os testes de APT usam o parser real em diretórios temporários para conferir fontes
legadas/deb822, preservação de mirrors, assinaturas obrigatórias, backups e repetição.
O perfil DNS testa edição, PTRs, SOA, serial, ACL/notify, primário/secundário,
compatibilidade do estado antigo e preferência pela interface Host-Only.

`tests/integration.sh` exige um **contêiner descartável**, root, checkout montado
em `/repo` e `GS_DISPOSABLE_CONTAINER=yes`. Ele instala pacotes e inicia BIND/Apache
reais; não o execute na sua VM de trabalho. Mantém TLS e assinaturas dos pacotes.

`tests/dns-transfer.sh` usa **dois contêineres descartáveis**, na mesma rede /24,
com BIND, Apache, curl, iproute2 e dnsutils instalados, o repositório em `/repo`
e `GS_DISPOSABLE_CONTAINER=yes`. Com os contêineres já preparados, execute:

```bash
# Dentro do primário; substitua pelo IP real do contêiner secundário:
bash /repo/tests/dns-transfer.sh init primary 172.29.56.20
# Dentro do secundário; substitua pelo IP real do contêiner primário:
bash /repo/tests/dns-transfer.sh init secondary 172.29.56.10
# Nas duas máquinas:
bash /repo/tests/dns-transfer.sh check
# No primário:
bash /repo/tests/dns-transfer.sh update
# No secundário:
bash /repo/tests/dns-transfer.sh check-update
```

Esses testes transferem zonas reais, conferem AXFR permitido/recusado, acrescentam
o A externo `webmail` e um A local com PTR, e comprovam a atualização no secundário.
Não são comandos de instalação para usar na prova; lá, use o assistente normal.

Validação realizada nesta entrega:

- Debian 12: BIND e Apache reais, download do template, consultas A/CNAME/MX/TXT/NS,
  PTRs, autoridade SOA, DNS UDP/TCP, HTTP por domínio/IP, estado salvo e reaplicação passaram.
  O novo painel foi exercitado com HTTP funcionando e depois com Apache parado:
  detectou a falha Web e continuou mostrando os resultados DNS. As consultas de
  firewalld/UFW foram exercitadas com respostas simuladas, sem alterar regras reais.
- Rocky 9: a tentativa de instalar os pacotes foi bloqueada pelo proxy deste
  ambiente (`403` para `mirrors.rockylinux.org`). A instalação real ainda não foi validada.
- Debian 13: erro de repositório CD/DVD reproduzido em contêiner; o reparo automático
  permitiu atualizar pacotes e concluir a integração com BIND/Apache reais e o painel.
  Na versão 1.2, dois contêineres com BIND/Apache reais confirmaram transferência
  direta/reversa, AXFR permitido somente ao secundário, atualização de A/PTR após
  aumento do serial e cabeçalho Apache sem versão. O painel conferiu os registros
  transferidos, incluindo o novo `webmail`.
- Debian 11 e Rocky 8/10: caminhos e seleção de plataforma cobertos pelos testes;
  instalação completa ainda não executada nessas versões.
- Os contêineres não validam boot com systemd, SELinux enforcing nem tráfego de
  outra máquina através de um firewall. Faça um ensaio em uma VM igual à da prova.

Cores aparecem automaticamente em terminal compatível. Para desativar:
`NO_COLOR=1 bash gs-linux.sh --demo`. Saída redirecionada para arquivo já sai sem cores.
