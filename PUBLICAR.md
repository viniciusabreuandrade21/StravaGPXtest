# Meus pedais no GitHub Pages

Site: https://viniciusabreuandrade21.github.io/StravaGPXtest/

## Atualizar os pedais publicados

1. Coloque os GPX que deseja compartilhar na pasta `GPX`.
2. Conecte-se à internet para consultar o vento dos novos pedais.
3. Execute `Gerar site publico.cmd`. Ele consulta automaticamente o vento que estiver faltando e gera a pasta `docs` com a lista e os mapas. Aguarde a mensagem final.
4. No VS Code, faça commit das mudanças e envie com Push/Sincronizar.
5. Aguarde a publicação do GitHub Pages terminar.

Os arquivos gerados não precisam de PowerShell no navegador. Os dados de vento já salvos são reutilizados e ficam incorporados. Se uma consulta falhar, o gerador informa quais pedais ficaram sem vento; execute novamente para tentar outra vez. O mapa continua funcionando sem vento. Não edite `docs` manualmente: altere os arquivos em `sistema` e gere de novo.

## Configuração no GitHub

Em **Settings → Pages**, escolha **Deploy from a branch**, branch **main**, pasta **/docs**, e salve. A pasta contém `.nojekyll` para servir os arquivos diretamente.

## Versão local

`Abrir meus pedais.cmd` continua funcionando normalmente. Todos os GPX da pasta são incluídos no site público ao gerar. O repositório público também disponibiliza os arquivos e seu histórico.
