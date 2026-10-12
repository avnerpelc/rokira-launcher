# Rokira Launcher

O launcher verifica o servidor, confere as versões e instala em sequência o cliente base e os patches do Rokira. Ele não libera **Jogar** se a instalação, a versão ou a conexão com o servidor falhar.

## Distribuição recomendada

- Mantenha no GitHub o código do launcher, scripts de build e exemplos de manifesto.
- Publique os pacotes grandes em uma pasta/armazenamento separado do diretório da aplicação e do banco do servidor. O launcher precisa de URLs HTTPS de leitura para `manifest.json`, `news.json`, `base/*.zip` e `patch/*.zip`; a área de download pode ser somente leitura e não deve expor listagem de diretórios nem aceitar uploads públicos.
- Nunca coloque contas, `.env`, senhas, backups, banco vivo, chaves ou scripts de administração nos pacotes. O verificador do launcher rejeita esses caminhos antes de extrair.
- Mantenha os arquivos do jogador em um pacote de cliente separado. Logins de GM são contas normais com privilégios no servidor; não devem ser distribuídos no cliente, em arquivos de configuração, scripts ou repositórios.
- Não inclua o cliente oficial da Gravity nos pacotes sem confirmar os direitos de redistribuição. O launcher mantém o link oficial e permite selecionar a instalação local.
- Não coloque token de bot Discord no launcher. Um bot no servidor pode ler o canal `#anúncios` e publicar somente título/texto em `news.json`; o launcher consome esse JSON público. Sem o bot configurado, `launcher/news.json` é o conteúdo de reserva.

Não é necessário criar outro repositório para os binários. O `rokira-rag` pode guardar o código e a documentação. Um repositório privado separado só faria sentido para o processo de build; os pacotes publicados continuam fora do Git.

## Manifesto de produção

Use `manifest-v2.example.json` como modelo. O manifesto real deve ter `format: 2`, o host/portas públicas do jogo e objetos `base` e `patch`. Cada pacote precisa de versão, `contentPolicy`, URL HTTPS, tamanho exato e SHA-256. Copie os metadados gerados pelo build para os objetos correspondentes; nunca use o manifesto antigo de um único ZIP.

As políticas aceitas são `rokira-base-v1` e `rokira-patch-v1`. A área de atualização deve entregar os arquivos por HTTPS e não pode redirecionar para HTTP. `server` é o endereço público de conexão do jogo, não o endereço administrativo da VPS.

## Gerar os pacotes

`Build-Client-Release.ps1` cria um ZIP com caminhos permitidos e interrompe a geração se detectar arquivo de conta, `.env`, banco, logs, backups, chaves, acesso SSH, arquivo de GM/admin ou diretório administrativo. Para o pacote base, a origem deve conter `cliente-windows/Ragnarok Classico.exe` e `client-assets/index.html`. Para patches, use uma pasta de origem com somente os arquivos alterados, mantendo os caminhos relativos (`client-assets/`, `client-browser/`, `catalogo/`, `localization/`, `patch/` ou `cliente-windows/`). Revise a lista de arquivos do pacote antes de publicar.

Depois de publicar os dois ZIPs e o manifesto, configure `launcher/launcher-config.json` com os endereços HTTPS reais e gere o launcher. Esse arquivo é ignorado pelo Git porque o endereço de distribuição é definido no ambiente de release.

## Notícias do Discord

O launcher consulta `newsUrl` do manifesto ou `newsUrl` da configuração local. Um serviço de bot com acesso somente de leitura ao canal de anúncios pode atualizar esse JSON. A estrutura esperada é:

```json
[
  { "tag": "EVENTO", "title": "Título", "body": "Resumo curto da notícia" }
]
```
