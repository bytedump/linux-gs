# Conteúdo dos slides ainda fora da automação

Comparação com o texto dos 16 arquivos recebidos. O material GUIA_DE_CONSULTA_VI contém apenas título; figuras ausentes do texto não puderam ser avaliadas.

- VI: modos de edição, movimentos, busca, cópia/remoção de linhas, substituição e gravação; exercícios em cópia de passwd.
- Rede/cliente DNS: configuração persistente de interfaces, rotas, hostname e resolvedor; preparação do VirtualBox; consultas públicas A/NS/SOA/MX/TXT, SPF e análise no MX Toolbox.
- Pacotes: pesquisa/listagem/remoção e gerenciamento geral, nmap/iptraf, instalação a partir de fontes e dependências de compilação (Squid/Snort).
- DNS: fundamentos, hierarquia, delegação, resolução recursiva/cache e interpretação de registros exigem estudo. O script entrega servidor autoritativo de uma zona e reversa /24; não configura resolvedor recursivo, IPv6/AAAA, delegação pública ou infraestrutura geral de DNS.
- HTTP: protocolo, códigos e tipos de conteúdo, leitura das diretivas e logs; configuração de outros sites/VirtualHosts, HTTPS e conteúdo dinâmico não são automatizados.
- FTP/SSH: FTP e TFTP, vsftpd, modos ativo/passivo, autenticação/permissões, SSH/OpenSSH, PuTTY, SCP/WinSCP e análise de login.
- Proxy: conceitos de cache e proxy reverso; Squid/ACLs, políticas de acesso, cliente usando proxy, NGINX/backend Apache, firewall/Web Filter/WAF.
- DHCP: conceitos de concessão e mensagens do protocolo precisam ser compreendidos; esta branch acrescenta o servidor ISC e reserva do exercício. Rede virtual, firewall, clientes e validação de concessões continuam manuais; Kea não implementado.
- Samba: serviço de diretório, domínio AD, provisionamento, DNS integrado, usuários/grupos, ingresso Windows, compartilhamento e permissões, RSAT e GPO.
- Backup/shell: mídias e planejamento, full/diferencial/incremental, compactação, cron; fundamentos Bash, variáveis, entrada/saída e interação. Falta script de backup datado GZIP com agendamento e validação de restauração.
- MySQL: instalação/administração, modelagem relacional básica, CREATE TABLE e CRUD, SQL Injection e prevenção com consultas parametrizadas/permissões.

Ter uma implementação Bash no projeto não substitui os exercícios de escrever scripts; backups da instalação não atendem à atividade de backup diário. O menu DHCP também não implementa os demais serviços dessa lista.
