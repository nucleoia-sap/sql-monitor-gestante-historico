# Guia: Publicar SQL_histórico/ no GitHub

Passo a passo para adicionar os arquivos do diretório `SQL_histórico/` ao repositório GitHub.

---

## 📋 Situação Atual

- **Repositório**: https://github.com/nucleoia-sap/sql-monitor-gestante-historico
- **Branch atual**: `1_gestacoes_historico`
- **Status**: Arquivos novos no diretório `SQL_histórico/` não estão no git

---

## 🚀 Passo a Passo Completo

### Passo 1: Verificar Estado Atual

```bash
cd "/Users/leonardolima/Library/CloudStorage/GoogleDrive-leolima.leitao@gmail.com/Outros computadores/PC SAP/Documents/Workspace/Histórico de atendimentos"

# Ver status atual
git status

# Ver branch atual
git branch
```

**Resultado esperado**: Deve mostrar branch `1_gestacoes_historico` e arquivos não rastreados.

---

### Passo 2: Adicionar Novos Arquivos do SQL_histórico/

```bash
# Adicionar todos os arquivos do diretório SQL_histórico/
git add "SQL_histórico/"

# Ou adicionar arquivos específicos:
git add "SQL_histórico/_hist_1_gestacoes.sql"
git add "SQL_histórico/_hist_2_atd_prenatal_aps.sql"
git add "SQL_histórico/_hist_6_linha_tempo.sql"
git add "SQL_histórico/construir_historico.sh"
git add "SQL_histórico/exemplo_uso.sh"
git add "SQL_histórico/QUICK_START.md"
git add "SQL_histórico/README.md"
git add "SQL_histórico/README_CONSTRUIR_HISTORICO.md"
```

---

### Passo 3: Adicionar Novos Arquivos da Raiz

```bash
# Adicionar documentações novas
git add README_DASHBOARD.md
git add README_EVOLUCAO_HISTORICA.md
git add README_VALIDACAO_GESTACOES.md
git add RELATORIO_CORRECAO_DESFECHO.md
git add EXPLICACAO_GESTACOES_HISTORICO.md

# Adicionar scripts e queries
git add validacao_gestacoes_historico.sql
git add query_dashboard_completo_clean.sql
git add analise_prescricoes_condicoes.sql

# Adicionar dashboard
git add dashboard_prescricoes_v2.html
git add dashboard_data_completo.json
```

---

### Passo 4: Limpar Arquivos Deletados

```bash
# Confirmar deleção de arquivos antigos
git add -u

# Isso registra as deleções de:
# - QUICK_START.md (movido para SQL_histórico/)
# - Arquivos duplicados de SQL_histórico/ com encoding diferente
# - executar_pipeline_datas_customizadas.sql (movido para Old/)
# - teste_procedimentos_3_a_6.sql (movido para Old/)
```

---

### Passo 5: Verificar Alterações Preparadas

```bash
# Ver o que será commitado
git status

# Ver diff detalhado
git diff --cached --stat
```

**Verifique se**:
- ✅ Novos arquivos do `SQL_histórico/` estão em "Changes to be committed"
- ✅ Novas documentações estão incluídas
- ✅ Arquivos antigos aparecem como deletados

---

### Passo 6: Criar Commit

```bash
git commit -m "feat: Add SQL_histórico directory with automated snapshot scripts

- Add 3 historical SQL scripts (_hist_1_gestacoes, _hist_2_atd_prenatal_aps, _hist_6_linha_tempo)
- Add construir_historico.sh automated execution script
- Add comprehensive documentation (QUICK_START, README_CONSTRUIR_HISTORICO)
- Add dashboard visualization (dashboard_prescricoes_v2.html)
- Add validation script (validacao_gestacoes_historico.sql)
- Add evolution and correction reports
- Move old files to Old/ directory
- Update typical record counts to ~28,000 pregnancies per snapshot

🤖 Generated with Claude Code
Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Passo 7: Enviar para GitHub

```bash
# Push para o branch atual
git push origin 1_gestacoes_historico
```

Se for a primeira vez fazendo push deste branch:

```bash
# Criar branch no remoto e fazer push
git push -u origin 1_gestacoes_historico
```

---

### Passo 8: Criar Pull Request (Opcional)

Se você quiser mesclar para `main`:

1. **Via GitHub Web**:
   - Acesse: https://github.com/nucleoia-sap/sql-monitor-gestante-historico
   - Clique em "Compare & pull request" para o branch `1_gestacoes_historico`
   - Preencha título e descrição
   - Clique em "Create pull request"

2. **Via CLI do GitHub** (se tiver `gh` instalado):

```bash
gh pr create \
  --title "feat: Add SQL_histórico automated snapshot system" \
  --body "$(cat <<'EOF'
## 📊 Resumo

Adiciona sistema automatizado de snapshots históricos com scripts SQL e dashboard interativo.

## 🆕 Novos Arquivos

### Diretório SQL_histórico/
- `_hist_1_gestacoes.sql` - Identificação de gestações histórico
- `_hist_2_atd_prenatal_aps.sql` - Atendimentos pré-natal histórico
- `_hist_6_linha_tempo.sql` - Agregação completa histórico
- `construir_historico.sh` - Script de execução automatizada
- `QUICK_START.md` - Guia rápido de 5 minutos
- `README_CONSTRUIR_HISTORICO.md` - Documentação completa

### Documentações Novas
- `README_DASHBOARD.md` - Dashboard de prescrições
- `README_EVOLUCAO_HISTORICA.md` - Análise de evolução temporal
- `README_VALIDACAO_GESTACOES.md` - Validação de gestações
- `RELATORIO_CORRECAO_DESFECHO.md` - Correção do desfecho gestacional
- `EXPLICACAO_GESTACOES_HISTORICO.md` - Explicação do sistema

### Scripts e Visualização
- `validacao_gestacoes_historico.sql` - Validação completa
- `dashboard_prescricoes_v2.html` - Dashboard interativo
- `query_dashboard_completo_clean.sql` - Query do dashboard

## 📈 Melhorias

- ✅ Números corrigidos: ~28.000 gestações por snapshot
- ✅ Pipeline automatizado de 3 etapas
- ✅ Geração automática de JSON para dashboard
- ✅ Documentação abrangente em português
- ✅ Organização de arquivos antigos em Old/

## 🧪 Testado

- ✅ Script testado com data 2024-10-31
- ✅ Pipeline completo executado com sucesso
- ✅ Dashboard renderizando dados corretamente

## 🔗 Referências

- Baseado em correções do modo DUM (MODE de data_evento)
- Corrige problema de datas futuras no desfecho gestacional
- Mantém compatibilidade com tabelas BigQuery existentes

🤖 Generated with Claude Code
EOF
)"
```

---

## ⚠️ Problemas Comuns

### Erro: "Permission denied"

```bash
# Se o script não for executável
chmod +x "SQL_histórico/construir_historico.sh"
chmod +x "SQL_histórico/exemplo_uso.sh"

# Adicionar novamente
git add "SQL_histórico/*.sh"
```

### Erro: "Conflito de encoding no nome do diretório"

Se aparecer `SQL_histo\314\201rico` e `SQL_histórico`:

```bash
# Remover versões com encoding problemático
git rm -r "SQL_histo\314\201rico/" --cached

# Adicionar versão correta
git add "SQL_histórico/"
```

### Erro: "fatal: pathspec did not match any files"

```bash
# Verificar se o diretório existe
ls -la "SQL_histórico/"

# Usar path absoluto se necessário
git add "/Users/leonardolima/Library/CloudStorage/GoogleDrive-leolima.leitao@gmail.com/Outros computadores/PC SAP/Documents/Workspace/Histórico de atendimentos/SQL_histórico/"
```

### Erro: "Updates were rejected"

```bash
# Atualizar branch local com remoto primeiro
git pull origin 1_gestacoes_historico

# Resolver conflitos se houver
# Depois tentar push novamente
git push origin 1_gestacoes_historico
```

---

## 🔍 Verificações Pós-Publicação

Após o push, verifique no GitHub:

1. **Arquivos visíveis**:
   - https://github.com/nucleoia-sap/sql-monitor-gestante-historico/tree/1_gestacoes_historico/SQL_histórico

2. **Conteúdo correto**:
   - QUICK_START.md mostra instruções do script shell
   - Scripts SQL estão completos
   - construir_historico.sh está marcado como executável

3. **Commit aparece corretamente**:
   - Mensagem de commit descritiva
   - Co-autoria do Claude presente
   - Data e hora corretas

---

## 📚 Próximos Passos

Depois de publicar:

1. **Atualizar README principal**:
   - Adicionar link para SQL_histórico/QUICK_START.md
   - Mencionar o script automatizado
   - Atualizar números de registros típicos

2. **Criar tag de versão** (opcional):
   ```bash
   git tag -a v2.0.0 -m "Sistema histórico automatizado"
   git push origin v2.0.0
   ```

3. **Criar release no GitHub** (opcional):
   - Acessar: https://github.com/nucleoia-sap/sql-monitor-gestante-historico/releases
   - "Draft a new release"
   - Escolher tag v2.0.0
   - Adicionar notas de release

---

## ✅ Checklist Final

Antes de fazer o push:

- [ ] Testei o construir_historico.sh localmente
- [ ] Verifiquei que todos os arquivos novos estão em `git status`
- [ ] Li a mensagem de commit e está clara
- [ ] Confirmei o nome do branch: `1_gestacoes_historico`
- [ ] Verifiquei que não há arquivos sensíveis (senhas, credenciais)
- [ ] Revisei os arquivos deletados (estão corretos)
- [ ] Atualizei a data nos READMEs (2025-12-09)

---

**Última atualização**: 2025-12-09
