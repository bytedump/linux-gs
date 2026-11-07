# Como colocar o projeto no clone Rocky sem interface gráfica

**Você só precisa do terminal.** Firefox e ambiente gráfico não são necessários.
O caminho mais simples é baixar o projeto com `git clone` dentro da VM. Se o
GitHub estiver bloqueado nela, há uma alternativa pelo Windows no final.

## 1. Entre no clone linkado

Crie e ligue o clone conforme a orientação da faculdade. Faça tudo **dentro do
clone**, preservando a máquina base. O clone linkado depende dos arquivos da base:
não apague nem mova a base para liberar espaço.

Na tela de texto, digite seu usuário e a senha fornecida pela faculdade. A senha
não aparece enquanto você digita; isso é normal. Depois do login, aparece uma linha
esperando comandos. Digite uma linha por vez e pressione Enter.

Os comandos com `sudo` pedem permissão administrativa. Se você entrou como `root`,
execute esses comandos sem a palavra `sudo`. Se aparecer “not in the sudoers file”,
use a conta administrativa fornecida pelo professor. Quando houver uma senha de
root disponível, `su -` abre uma sessão administrativa; não é a senha do GitHub.

## 2. Confira a rede

O clone precisa de Internet para baixar o projeto **e os pacotes BIND/Apache**.
No VirtualBox, confira nas configurações de rede do **clone desligado**:

- Um adaptador em **NAT**, com “Cabo conectado”, normalmente fornece Internet.
- Preserve a interface **Host-Only** ou **Rede Interna** exigida pelo professor.
  Ela serve para a rede do exercício e, sozinha, normalmente não fornece Internet.
- Se precisar acrescentar NAT, use um adaptador livre; não substitua a rede do
  laboratório. Ao criar clones, escolha gerar novos endereços MAC. Cada VM também
  precisa de um IP próprio na rede compartilhada; um clone pode herdar o IP da base.

Já no terminal da VM, estes comandos só consultam:

```bash
ip -br -4 addr
ip route
getent hosts github.com
```

Procure um IPv4 na interface NAT, uma rota começando com `default` e um endereço
como resposta para `github.com`. Isso verifica parte da rede; o download no próximo
passo confirma se o acesso HTTPS funciona. Ter IP não garante acesso à Internet.

Para o DNS do exercício, escolha depois o **IP estável da rede do laboratório**,
conforme o enunciado. O assistente não configura IP fixo nem adaptadores da VM.
Em duas VMs com NAT individual, `10.0.2.15` pode aparecer nas duas: esse endereço
não serve para elas conversarem entre si. Veja o [roteiro das duas VMs](atividade-dns.md).

## 3. Baixe o projeto pelo terminal (recomendado)

**Execute dentro do Rocky**, uma linha por vez. Se aparecer erro, pare naquela linha.

Instale o programa que baixa repositórios do GitHub:

```bash
sudo dnf install -y git
```

Vá para a pasta pessoal e baixe o projeto completo:

```bash
cd ~
git clone https://github.com/bytedump/linux-gs.git
cd linux-gs
ls
```

Você deve ver `gs-linux.sh`, `README.md`, `docs`, `tests` e **`template`**. Este
repositório é público: o download não precisa de conta ou senha do GitHub.
Se o comando pedir login, confira se digitou exatamente a URL acima.

`git clone` apenas baixa os arquivos; não instala DNS/Web. A pasta `template/`
contém a cópia de reserva do site e deve ficar ao lado do script.

**Se a pasta `linux-gs` já existir**, não a apague nem rode outro clone por cima.
Se ela veio de um `git clone` anterior, entre nela e atualize:

```bash
cd ~/linux-gs
git pull --ff-only
```

Se o Git reclamar de alterações locais, preserve suas edições e leia a mensagem;
não use `reset --hard` para tentar resolver. Uma pasta extraída de ZIP não pode ser
atualizada com `git pull`.

## 4. Treine e depois instale

Dentro da pasta do projeto, comece pelo treinamento:

```bash
bash gs-linux.sh --demo
```

Esse modo não instala pacotes nem altera configurações. Para estudar DNS,
registros e os outros assuntos pelo próprio terminal:

```bash
bash gs-linux.sh --learn
```

Com os IPs do laboratório preparados e os dados do enunciado em mãos, instale:

```bash
sudo bash gs-linux.sh --install
```

O assistente pergunta domínio, papel da VM, IP e registros, mostra um resumo e pede
confirmação. Para uma única VM, escolha **Primário** e informe **0** para o secundário.
Se houver duas, siga o [roteiro de primário e secundário](atividade-dns.md).

Não precisa executar `chmod +x`: usar `bash gs-linux.sh` já funciona.

## 5. Mostre o resultado ao professor

```bash
sudo bash gs-linux.sh --status
```

O painel consulta serviços, portas, DNS, HTTP, firewall e SELinux. Leia também os
avisos amarelos e as falhas vermelhas. Para salvar um relatório:

```bash
sudo bash gs-linux.sh --report
```

O site pode ser verificado pelo terminal, sem navegador. Por exemplo, **substitua
o IP pelo endereço da sua VM**:

```bash
curl -I http://192.168.56.10/
```

Isso mostra a resposta HTTP; o painel faz verificações adicionais do conteúdo.
Para ver a página visualmente, abra esse endereço no navegador do **computador
hospedeiro**, se ele alcançar a VM por Host-Only ou outra rede configurada. Abrir
por nome, como `aluno.fiap`, também exige que o cliente consulte o DNS do laboratório.

## Plano B: baixar no Windows e copiar para a VM

Use este caminho se o Windows acessa o GitHub, mas o clone não. A transferência usa
**SCP**, que copia arquivos por **SSH**. Não exige interface gráfica dentro do Rocky.
Ela resolve a entrega do projeto; a instalação dos pacotes ainda precisa de acesso
aos repositórios do Rocky. Uma instalação completamente offline não é suportada.

### A. No Windows, baixe o ZIP

Abra [o repositório](https://github.com/bytedump/linux-gs) no navegador do Windows,
clique em **Code → Download ZIP** e salve `linux-gs-main.zip` em **Downloads**.
Se o navegador acrescentar `(1)` ao nome, renomeie o arquivo baixado ou ajuste o
nome no comando de cópia. Transfira o ZIP inteiro, não apenas o `.sh`.

### B. No Rocky, prepare o recebimento

```bash
sudo dnf install -y openssh-server unzip
sudo systemctl enable --now sshd
sudo systemctl status sshd --no-pager
whoami
```

O serviço deve mostrar `active (running)`. Anote o usuário mostrado por `whoami`;
use uma conta normal com senha para a transferência. Não habilite login remoto de
root para isso. Caso só tenha acesso como root, peça ao professor a conta de aluno.

Se o firewalld estiver ativo, consulte a zona da interface que receberá a conexão:

```bash
sudo firewall-cmd --get-active-zones
```

Se essa zona for `public`, libere SSH nela durante esta sessão:

```bash
sudo firewall-cmd --zone=public --add-service=ssh
```

Troque `public` pela zona exibida para sua interface NAT, se for diferente. A regra
acima é temporária e não desativa o firewall. Se o serviço estiver inativo, não
precisa ativá-lo só para executar esse comando.

### C. No VirtualBox, encaminhe uma porta da NAT

Desligue o clone normalmente (`sudo poweroff`). No VirtualBox, selecione **o clone**
e abra **Configurações → Rede → adaptador em NAT → Avançado → Redirecionamento de portas**.
Crie esta regra e depois ligue o clone novamente:

| Campo | Valor |
| --- | --- |
| Nome | `SSH-GS` |
| Protocolo | `TCP` |
| IP do hospedeiro | `127.0.0.1` |
| Porta do hospedeiro | `2222` |
| IP do convidado | Deixe vazio para a NAT com DHCP padrão |
| Porta do convidado | `22` |

Se o IP da interface NAT foi configurado manualmente, informe esse IP no campo do
convidado. Esta regra é para o modo **NAT** do adaptador, não “Rede NAT”.
O IP `127.0.0.1` limita a entrada ao próprio computador Windows. Se já houver outra
VM usando a porta `2222`, escolha outra porta livre e ajuste o comando abaixo.

**Após ligar a VM, repita a liberação temporária de SSH do passo B**, se necessária;
a regra temporária do firewall se perde ao reiniciar.

### D. No PowerShell do Windows, copie o ZIP

Abra **PowerShell no Windows**, não no Rocky. Troque `usuario` pelo login da VM:

```powershell
cd "$HOME\Downloads"
scp -P 2222 .\linux-gs-main.zip usuario@127.0.0.1:linux-gs-main.zip
```

Na primeira conexão, o SSH mostra a identidade do servidor. Você pode comparar a
impressão digital com a exibida no console da VM por:

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Confirmada a identidade, digite `yes` no PowerShell e informe a senha **do usuário
da VM**. Nada aparece ao digitar a senha. Se `scp` não existir no Windows, instale o
recurso opcional **Cliente OpenSSH** nas configurações do Windows, ou peça ao
responsável pelo computador da faculdade.

### E. No terminal da VM, extraia e execute

Entre com o mesmo usuário que recebeu o arquivo:

Se já existir uma pasta `linux-gs-main` com trabalho seu, extraia o novo ZIP em
outra pasta, preservando a anterior. Em um clone sem essa pasta, execute:

```bash
cd ~
unzip linux-gs-main.zip
cd linux-gs-main
ls
bash gs-linux.sh --demo
```

Confira se `template/` está presente. Depois, continue pelos passos **4 e 5** para
instalar e comprovar.

Terminada a transferência, você pode remover a regra `SSH-GS` do VirtualBox quando
desligar o clone. Não é necessário deixá-la para o instalador DNS/Web funcionar.

## Se algo der errado

| Mensagem ou situação | O que conferir |
| --- | --- |
| `git: command not found` | O `dnf install -y git` terminou com sucesso? |
| `Could not resolve host` | DNS da VM: confira `ip route` e `getent hosts github.com`. Se o erro for num mirror, confira o nome indicado na mensagem. |
| Erro ao acessar repositórios no `dnf` | NAT, rota e DNS; se a rede da faculdade exige proxy, use os dados fornecidos por ela. O ZIP não substitui esses pacotes. |
| `SSL certificate problem` | Confira `date` e os certificados da faculdade. Não desative a verificação TLS para contornar o erro. |
| `No such file or directory` ao executar | Use `pwd` e `ls`: você precisa estar na pasta que contém `gs-linux.sh`. |
| Debian: `a2ensite: command not found`, mesmo com Apache instalado | Atualize para 1.2.4 ou posterior. Nas versões anteriores, já como root, execute `export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` e rode o assistente novamente. Se continuar, confira `ls -l /usr/sbin/a2ensite`: arquivo ausente indica outro problema na instalação do Apache. |
| SCP: `Connection refused` ou demora até falhar | Clone ligado, regra NAT correta, porta `2222`, `sshd` ativo e SSH permitido na zona certa do firewall. |
| SCP: `Permission denied` | Login e senha da VM, não do GitHub; confira a conta fornecida pelo professor. |
| Não consigo colar no console do VirtualBox | O console de texto pode não ter área de transferência integrada. Digite as linhas; com SSH configurado, `ssh -p 2222 usuario@127.0.0.1` no PowerShell abre um terminal em que você pode colar. |
| Tenho apenas a rede isolada e nenhum acesso aos pacotes | Prepare o clone com antecedência ou peça o acesso de instalação ao professor. Este projeto não fornece todos os pacotes offline. |

Se uma etapa falhar, guarde a mensagem completa e resolva essa etapa antes de
continuar. Não é necessário instalar Firefox para nenhum desses procedimentos.
