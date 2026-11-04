# Atividade DNS: roteiro para duas VMs

Este roteiro acompanha as atividades **Linux - 03.1_DNS_Primary** e
**Linux - 03.2_DNS_Secondary**, enviadas com o material da turma. Use os endereços e
nomes do enunciado do professor se forem diferentes dos exemplos abaixo.

## 1. Entenda o desenho

| Máquina | IP de exemplo | Responsabilidade |
| --- | --- | --- |
| VM 1 — primário | `192.168.56.10` | Guarda a configuração original e envia as zonas |
| VM 2 — secundário | `192.168.56.20` | Recebe cópias e responde às mesmas consultas DNS |
| Domínio | `aluno.fiap` | Substitua `aluno` pelo nome solicitado |
| Rede reversa | `192.168.56.0/24` | Mesma resposta nas duas VMs |

**As VMs precisam conversar entre si.** Na atividade, o primeiro adaptador é
Host-Only, compartilhado pelas duas VMs; o segundo é NAT, para baixar pacotes.
Configure antes os dois IPs fixos na interface Host-Only, sem repetir endereços.
O script configura DNS/Web, mas não cria adaptadores no VirtualBox nem fixa o IP.
Não use o gateway NAT como gateway da interface Host-Only; mantenha a saída para
Internet pela NAT. Um `10.0.2.15` repetido em duas VMs NAT não as coloca na mesma rede.

Para conferir o que existe, sem alterar nada:

```bash
ip -4 addr
ip route
```

No assistente, a lista mostra interface + IP. Confira qual é a Host-Only;
`192.168.56.x` recebe preferência na sugestão, mas a escolha é sua.

## 2. Prepare o primário primeiro

Na **VM 1**, na pasta do script atualizado:

```bash
sudo bash gs-linux.sh --install
```

Responda:

1. Domínio: `aluno.fiap`.
2. Papel: **1 — Primário**.
3. IP desta VM: `192.168.56.10`, ou o número correspondente na lista.
4. IP reservado ao secundário: `192.168.56.20`.
5. Rede reversa: `192.168.56.0/24`.
6. Confira os registros e escolha **0 — Concluir**.
7. Leia o resumo e digite **S**.

A base será:

| Nome | Tipo | Valor |
| --- | --- | --- |
| `@` (o próprio domínio) | A | `192.168.56.10` |
| `ns1` | A | `192.168.56.10` |
| `www` | A | `192.168.56.20` |
| `intranet` | CNAME | `www.aluno.fiap` |

NS/SOA e PTRs são gerados automaticamente. `www` já é A: não precisa cadastrar de
novo. Para mudar seu IP, use **7 — Editar**. Para entender os registros, use **6**.
`ns1` permanece vinculado ao primário para não quebrar SOA/NS.

O script pode concluir os testes locais mesmo sem a VM 2 pronta. A comprovação
da replicação só poderá passar depois da etapa seguinte.

**Só tem uma VM para treinar?** Responda `0` na pergunta do secundário. Nesse caso,
`www` apontará para a própria VM e não haverá transferência de zona.

## 3. Prepare o secundário

Na **VM 2**, execute o mesmo script com `--install` e responda:

1. Mesmo domínio: `aluno.fiap`.
2. Papel: **2 — Secundário**.
3. IP desta VM: `192.168.56.20`.
4. IP do primário: `192.168.56.10`.
5. Mesma rede reversa: `192.168.56.0/24`.
6. Confira o resumo e digite **S**.

Aqui não aparece cadastro de registros: eles vêm do primário. O assistente espera
até 45 segundos pelas duas zonas e confere se os SOAs coincidem. Se falhar, leia
o log indicado e confira os IPs, domínio, rede /24, primário ativo e TCP/53.

As duas VMs recebem Apache e o template. `http://192.168.56.10/` mostra o site da
primeira; `http://192.168.56.20/`, o da segunda. `www.aluno.fiap` aponta para a
segunda VM neste exemplo. Para abrir por nome no navegador do cliente, ele precisa
consultar este DNS para a zona; usar `dig @IP` não muda a configuração desse cliente.

## 4. Mostre ao professor

Em **cada VM**, escolha a opção **5** ou execute:

```bash
sudo bash gs-linux.sh --status
```

O painel mostra comandos e respostas: serviços, portas, firewall, configuração,
DNS direto/reverso, SOAs das duas máquinas, HTTP e logs. No secundário, compara os
registros recebidos com os do primário e confirma os arquivos locais das duas zonas.
Verde indica teste aprovado; vermelho, falha; amarelo exige conferir a limitação.
No modo **6 / --report**, salva as evidências em texto e informa o caminho.

Para demonstrar manualmente a parte DNS, em uma VM ou cliente com as ferramentas:

```bash
nslookup -type=NS aluno.fiap 192.168.56.10
nslookup -type=SOA aluno.fiap 192.168.56.10
nslookup www.aluno.fiap 192.168.56.10
nslookup intranet.aluno.fiap 192.168.56.10
nslookup 192.168.56.20 192.168.56.10
nslookup -type=SOA aluno.fiap 192.168.56.20
nslookup www.aluno.fiap 192.168.56.20
```

Nos SOAs, procure o mesmo **serial**. Ele segue `AAAAMMDDnn`, por exemplo
`2026110400`, e aumenta ao reaplicar. Os outros valores seguem a atividade:
refresh `28800`, retry `14400`, expire `86400`, minimum `600`.

Se não cadastrou MX, uma consulta MX não deve inventar um servidor de e-mail.
Quando o enunciado pedir, cadastre primeiro um A `mail` e depois um MX `@` apontando
para `mail.aluno.fiap`, por exemplo com prioridade `10`.

Logs e porta, dentro de cada servidor:

```bash
sudo journalctl -u named -n 40 --no-pager
sudo ss -lntup
```

DNS precisa de **53/UDP e 53/TCP**; transferência usa TCP. HTTP precisa de **80/TCP**.
Faça também uma consulta e abra o site a partir de outra máquina: serviço ativo ou
regra local de firewall, isoladamente, não comprovam esse acesso.

## 5. Prove uma alteração chegando ao secundário

No **primário**, execute novamente `--install` e mantenha domínio, IPs e rede.
**Reaplicar substitui a lista: cadastre novamente todos os registros extras que
quiser conservar.** A base `@`, `ns1`, `www` e `intranet` é proposta novamente.

No menu de registros:

1. Escolha **1 — A**.
2. Nome: `webmail`.
3. IPv4: `10.200.200.200`.
4. Conclua com **0** e confirme com **S**.

O serial aumenta e o primário avisa o secundário por NOTIFY. Depois consulte:

```bash
nslookup webmail.aluno.fiap 192.168.56.10
nslookup webmail.aluno.fiap 192.168.56.20
```

Ambos devem responder `10.200.200.200`. Isso prova a publicação do registro, não
que exista um servidor acessível nesse endereço. Esse IP não pertence à reversa
`192.168.56.0/24`; portanto não recebe PTR nessa zona.

**Não edite o arquivo de zona recebido no secundário.** O BIND o mantém, às vezes
em formato binário. Faça as mudanças no primário e mostre a nova consulta nos dois.

## 6. Onde ficam os arquivos

| Papel | Debian | Rocky |
| --- | --- | --- |
| Primário | `/var/lib/bind/gs-linux/` | `/var/named/gs-linux/` |
| Secundário | `/var/cache/bind/gs-linux/` | `/var/named/slaves/gs-linux/` |

Dentro da pasta, os exemplos são `aluno.fiap.zone` e `56.168.192.in-addr.arpa`.
Configuração principal: `/etc/bind/named.conf` no Debian; `/etc/named.conf` no Rocky.
O secundário usa `type slave; masters { IP-PRIMARIO; };`, equivalentes aos termos
secondary/primary. No primário, `allow-transfer` permite somente o IP informado da
segunda VM; `also-notify` indica a quem avisar.

Esse roteiro cobre o bloco DNS das atividades. DHCP, backup por cron, SSH,
vsftpd, Squid e MySQL não foram automatizados por esta atualização.
