# GS Linux — DNS e Web sem decorar comandos

Um único script Bash para **Debian e Rocky Linux**, com menus em português, cores,
banner ASCII, validação das respostas e confirmação antes de alterar a máquina.
Instala BIND e Apache e publica um template HTML baixado da Internet.

## Comece pela demonstração

Abra um terminal na pasta onde está `gs-linux.sh` e execute:

```bash
bash gs-linux.sh --demo
```

Esse modo **não instala, não baixa e não altera configurações**. Serve para aprender
os menus. Pressione Enter para aceitar o valor entre colchetes. As opções são
numéricas; não é preciso decorar nomes de registros.

Para uma primeira tentativa, use `empresa.test`, aceite o IP sugerido e conclua os
registros com `0`. No resumo, `S` continua, `R` refaz as respostas e `N` cancela.

## Instalar na VM da prova

Use uma VM completa, com systemd, Internet e um IPv4 que permaneça estável.
Compatibilidade prevista: **Debian 11, 12 e 13; Rocky Linux 8, 9 e 10**.
Não é um instalador para WSL sem systemd, macOS ou contêineres comuns.

```bash
sudo bash gs-linux.sh
```

Se estiver conectado como `root`, use `bash gs-linux.sh`. Se não tem `sudo` nem
acesso a root, precisará da conta administrativa fornecida pelo professor.

O instalador vai:

1. Identificar a distribuição e pedir o domínio e o IP do servidor.
2. Perguntar quais registros adicionais você quer criar.
3. Mostrar o resumo e pedir confirmação.
4. Instalar pacotes, baixar o template e guardar backups.
5. Configurar BIND, Apache e as permissões necessárias.
6. Liberar DNS e HTTP no firewalld ou UFW, se estiverem ativos.
7. Ativar os serviços e testar DNS e HTTP de verdade.

**Atenção ao resumo:** a configuração principal do BIND será substituída pelo DNS
do laboratório. O site passa a ser o padrão do Apache; os arquivos de outros sites
não são apagados. Use a VM de exercícios, não um servidor com serviços de terceiros.

O template é **Bare, do Start Bootstrap**, licença MIT, fixado em um commit. HTML,
CSS, JavaScript, favicon e licença são baixados; o JavaScript do Bootstrap também
fica local. Depois da instalação, a página não depende de uma CDN para funcionar.
Não há pacote ZIP para extrair nem script externo baixado para executar.

## O que responder nos menus

Imagine que a VM tenha o endereço `192.168.56.10`:

| Pergunta | Exemplo | Significado |
| --- | --- | --- |
| Domínio | `empresa.test` | Nome do laboratório; sem `http://` |
| IPv4 desta máquina | `192.168.56.10` | IP da interface da VM, não o do computador hospedeiro |
| Nome de registro | `loja` | O script cria `loja.empresa.test` |
| Nome `@` | `@` | Representa o próprio `empresa.test` |
| Destino CNAME/MX | `mail.empresa.test` | Nome completo; não use um IP |

O script cria uma base fixa:

| Nome | Tipo | Destino |
| --- | --- | --- |
| `empresa.test` (`@`) | A | IP da VM |
| `ns1.empresa.test` | A | IP da VM |
| `www.empresa.test` | CNAME | `empresa.test` |
| `empresa.test` | NS | `ns1.empresa.test` |
| `empresa.test` | SOA | Metadados da zona, gerados automaticamente |

Você pode adicionar/remover registros **extras** dos seguintes tipos:

| Tipo | Para que serve | Exemplo |
| --- | --- | --- |
| A | Nome para IPv4 | `mail` → `192.168.56.10` |
| CNAME | Apelido para outro nome | `correio` → `mail.empresa.test` |
| MX | Servidor que recebe e-mail do domínio | `@` → `mail.empresa.test`, prioridade `10` |
| TXT | Informação em texto | `@` → `Trabalho de Linux` |

Cadastre o **A do destino antes do CNAME ou MX**. Neste assistente, esses destinos
devem estar na própria zona e ter um A; aliases externos e cadeias de CNAME não são
aceitos. Isso evita loops e destinos sem resolução durante o exercício.
MX não instala e-mail. Prioridade menor significa preferência maior.
TXT aceita até 200 caracteres ASCII visíveis, incluindo espaços e aspas.
AAAA, PTR, SRV, zona reversa, servidor de e-mail e HTTPS não fazem parte desta versão.

Para corrigir a base fixa ou trocar domínio/IP, escolha `R` no resumo ou execute
novamente o assistente. A reaplicação substitui a configuração gerenciada pela
lista nova; os registros extras anteriores não são importados automaticamente.

## Conferir depois de instalar

```bash
sudo bash gs-linux.sh --check
```

Esse comando relê os registros salvos e consulta o BIND, incluindo UDP e TCP.
Também verifica se o HTTP entrega o HTML instalado, pelo IP e pelo domínio.
Não instala nem modifica configurações.

Para estudar os comandos por trás do teste, substitua o IP/domínio pelos seus:

```bash
dig @192.168.56.10 empresa.test A
dig @192.168.56.10 www.empresa.test CNAME
dig @192.168.56.10 empresa.test MX
dig @192.168.56.10 empresa.test TXT
dig @192.168.56.10 empresa.test SOA +tcp
curl --noproxy '*' http://192.168.56.10/
curl --noproxy '*' --resolve empresa.test:80:192.168.56.10 http://empresa.test/
```

O `@IP` do `dig` significa **consultar aquele servidor DNS**. O `--resolve` do curl
permite testar o site pelo domínio sem modificar o DNS do seu computador.

Abra `http://IP-DA-VM/` no navegador. Para abrir `http://empresa.test/` em outro
computador, ele precisa usar a VM como DNS para essa zona. O script configura o
servidor inteiro; não altera automaticamente computadores clientes, DHCP,
roteadores, encaminhamentos do hipervisor ou firewalls do provedor.

O DNS é **autoritativo, sem recursão**: responde pela sua zona, não substitui um
resolvedor geral para navegar na Internet. Use consultas explícitas com `dig @IP`
para a demonstração. A escolha de `.test` não registra um domínio público.

## O que muda entre Debian e Rocky

| Item | Debian | Rocky Linux |
| --- | --- | --- |
| Instalador de pacotes | `apt-get` | `dnf` |
| Serviço DNS | `named` (pacote `bind9`) | `named` (pacote `bind`) |
| Serviço Web | `apache2` | `httpd` |
| Configuração BIND | `/etc/bind/named.conf` | `/etc/named.conf` |
| Zona do laboratório | `/var/lib/bind/gs-linux/db.zone` | `/var/named/gs-linux/db.zone` |
| Site Apache | `/etc/apache2/sites-enabled/000-000-gs-linux.conf` | `/etc/httpd/conf.d/00-gs-linux.conf` |
| Arquivos do site | `/var/www/gs-linux` | `/var/www/gs-linux` |

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
| CNAME/MX sem destino | Primeiro crie o registro A do destino |
| Teste local passa, outro PC não acessa | Confira rede da VM, firewall externo e configuração DNS do cliente |

Se a falha acontecer após o início da alteração dos arquivos, o script tenta
restaurar os arquivos anteriores, as regras que adicionou e o estado dos serviços
capturado após a instalação dos pacotes. O log registra falhas na restauração.
**Pacotes instalados não são desinstalados automaticamente.** Queda de energia ou
`kill -9` não permitem executar a recuperação; os backups continuam disponíveis.
Eles contêm `manifest.txt` e os caminhos originais dentro de `files/`.

O script nunca considera falha de teste como sucesso. A configuração DNS tem
recursão, transferência de zona e atualização dinâmica desativadas.

## Entender o código para as três tarefas surpresa

Leia as funções nesta ordem:

1. `wizard`: perguntas e resumo; `valid_*`: validação das respostas.
2. `install_packages`: instalação específica de cada distribuição.
3. `render_zone`, `render_named`, `render_web`: conteúdo dos arquivos.
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
```

Os testes locais cobrem entrada inválida, conflitos entre registros, escape de TXT,
caminhos por distribuição, estado salvo, restauração, cancelamento e demonstração.

`tests/integration.sh` exige um **contêiner descartável**, root, checkout montado
em `/repo` e `GS_DISPOSABLE_CONTAINER=yes`. Ele instala pacotes e inicia BIND/Apache
reais; não o execute na sua VM de trabalho. Mantém TLS e assinaturas dos pacotes.

Validação realizada nesta entrega:

- Debian 12: BIND e Apache reais, download do template, consultas A/CNAME/MX/TXT/NS,
  autoridade SOA, DNS UDP/TCP, HTTP por domínio/IP, estado salvo e reaplicação passaram.
- Rocky 9: a tentativa de instalar os pacotes foi bloqueada pelo proxy deste
  ambiente (`403` para `mirrors.rockylinux.org`). A instalação real ainda não foi validada.
- Debian 11/13 e Rocky 8/10: caminhos e seleção de plataforma cobertos pelos testes;
  instalação completa ainda não executada nessas versões.
- Os contêineres não validam boot com systemd, SELinux enforcing nem tráfego de
  outra máquina através de um firewall. Faça um ensaio em uma VM igual à da prova.

Cores aparecem automaticamente em terminal compatível. Para desativar:
`NO_COLOR=1 bash gs-linux.sh --demo`. Saída redirecionada para arquivo já sai sem cores.
