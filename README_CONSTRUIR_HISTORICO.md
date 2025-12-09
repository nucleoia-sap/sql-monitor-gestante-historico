# Construir Histórico - Guia de Uso

Script automatizado para executar os SQLs históricos na ordem correta usando BigQuery CLI.

## 📋 Pré-requisitos

1. **BigQuery CLI instalado**:
   ```bash
   gcloud components install bq
   ```

2. **Autenticação configurada**:
   ```bash
   gcloud auth login
   gcloud config set project rj-sms-sandbox
   ```

3. **Script executável** (apenas primeira vez):
   ```bash
   chmod +x construir_historico.sh
   ```

## 🚀 Opção 1: Passar Datas como Argumentos (Recomendado)

Forma mais rápida para processar algumas datas:

```bash
./construir_historico.sh 2024-07-01 2024-08-01
```

Ou múltiplas datas:

```bash
./construir_historico.sh 2024-01-31 2024-02-29 2024-03-31 2024-04-30
```

## 🚀 Opção 2: Configurar Datas no Script

Para processar muitas datas regularmente:

1. **Editar o script**:
   ```bash
   nano construir_historico.sh
   ```

2. **Descomentar e preencher o array** `DATAS_PROCESSAR`:
   ```bash
   DATAS_PROCESSAR=(
       "2024-01-31"
       "2024-02-29"
       "2024-03-31"
       "2024-04-30"
       "2024-05-31"
       "2024-06-30"
   )
   ```

3. **Executar**:
   ```bash
   ./construir_historico.sh
   ```

## 📊 Ordem de Execução

Para cada data, o script executa **na ordem**:

1. **`_hist_1_gestacoes.sql`**
   - → Tabela: `_gestacoes_historico`
   - Identifica e classifica gestações

2. **`_hist_2_atd_prenatal_aps.sql`**
   - → Tabela: `_atendimentos_prenatal_aps_historico`
   - Atendimentos de pré-natal com vitais

3. **`_hist_6_linha_tempo.sql`**
   - → Tabela: `_linha_tempo_historico`
   - Agregação completa com todos os indicadores

4. **Geração automática do JSON do dashboard** (após processar todas as datas)
   - → Arquivo: `dashboard_data_completo.json`
   - Executa `query_dashboard_completo_clean.sql`
   - Gera JSON com todos os snapshots para visualização no dashboard

## ✅ Saída Esperada

### Durante a Execução

```
============================================================
Script de Construção de Histórico de Gestações
============================================================

✅ BigQuery CLI encontrado
✅ Autenticado no projeto: rj-sms-sandbox

📅 Datas a processar: 2024-07-01 2024-08-01
📊 Total: 2 data(s)

============================================================
📆 Processando data: 2024-07-01
============================================================
   ⏳ 1/3 Gestações...
   ✅ 1/3 Gestações concluído
   ⏳ 2/3 Atendimentos Pré-Natal...
   ✅ 2/3 Atendimentos Pré-Natal concluído
   ⏳ 3/3 Linha do Tempo...
   ✅ 3/3 Linha do Tempo concluído

   ✅ Snapshot 2024-07-01 concluído com sucesso!
   ⏱️  Tempo: 87s

============================================================
📆 Processando data: 2024-08-01
============================================================
   ...

============================================================
📊 RELATÓRIO FINAL
============================================================
✅ Sucessos: 2
❌ Falhas: 0
⏱️  Tempo total: 174s

🎉 Processamento dos snapshots concluído com sucesso!

============================================================
📊 Gerando JSON do Dashboard
============================================================

⏳ Executando query de agregação...
✅ JSON gerado com sucesso!
📁 Arquivo: dashboard_data_completo.json
📊 Snapshots incluídos: 2

💡 Para visualizar, abra o arquivo dashboard_prescricoes_v2.html no navegador

============================================================
✅ PIPELINE COMPLETO EXECUTADO COM SUCESSO!
============================================================

📊 Dados processados:
   - 2 snapshot(s) histórico(s)
   - JSON do dashboard atualizado

🌐 PRÓXIMOS PASSOS:
1. Abra o dashboard no navegador:
   http://localhost:8000/dashboard_prescricoes_v2.html

2. Se necessário, inicie o servidor HTTP:
   python3 -m http.server 8000

3. Verifique os dados nas tabelas BigQuery:
   - rj-sms-sandbox.sub_pav_us._gestacoes_historico
   - rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico
   - rj-sms-sandbox.sub_pav_us._linha_tempo_historico
```

### Tabelas e Arquivos Gerados

Cada snapshot cria registros em 3 tabelas BigQuery:

| Tabela | Descrição | Registros Típicos |
|--------|-----------|-------------------|
| `_gestacoes_historico` | Gestações e puerpérios | ~28.000 |
| `_atendimentos_prenatal_aps_historico` | Consultas pré-natal | ~300.000 |
| `_linha_tempo_historico` | Agregação completa | ~28.000 |

Após processar todas as datas, é gerado automaticamente:

| Arquivo | Descrição | Conteúdo |
|---------|-----------|----------|
| `dashboard_data_completo.json` | Dados do dashboard | JSON com todos os snapshots e indicadores |

## 🔍 Verificar Resultados

### Consultar dados do snapshot

```sql
-- Resumo geral
SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS em_gestacao,
    COUNTIF(fase_atual = 'Puerpério') AS em_puerperio
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
GROUP BY data_snapshot
ORDER BY data_snapshot DESC;
```

### Verificar cobertura de atendimentos

```sql
-- Gestantes com consultas
SELECT
    l.data_snapshot,
    COUNT(DISTINCT l.id_gestacao) AS gestantes_com_consulta,
    COUNT(DISTINCT a.id_gestacao) AS gestantes_total
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico` l
LEFT JOIN `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico` a
    ON l.id_gestacao = a.id_gestacao
    AND l.data_snapshot = a.data_snapshot
WHERE l.fase_atual = 'Gestação'
GROUP BY l.data_snapshot;
```

### Visualizar no Dashboard

Após a execução bem-sucedida, o arquivo `dashboard_data_completo.json` é gerado automaticamente.

**Para visualizar:**

1. **Inicie o servidor HTTP** (se ainda não estiver rodando):
   ```bash
   cd ..  # Voltar para o diretório raiz
   python3 -m http.server 8000
   ```

2. **Abra o dashboard no navegador**:
   ```
   http://localhost:8000/dashboard_prescricoes_v2.html
   ```

3. **Navegue pelos snapshots**:
   - Use o calendário para selecionar diferentes datas
   - Visualize a evolução temporal nos gráficos
   - Compare indicadores entre períodos

**Atualização automática do cache**:
- Se o dashboard não mostrar todos os snapshots, faça **hard refresh**:
  - Windows/Linux: `Ctrl + Shift + R`
  - Mac: `Cmd + Shift + R`

## ⚠️ Solução de Problemas

### Erro: "bq command not found"

```bash
# Instalar BigQuery CLI
gcloud components install bq
```

### Erro: "Permission denied"

```bash
# Tornar o script executável
chmod +x construir_historico.sh
```

### Erro: "Not authenticated"

```bash
# Fazer login
gcloud auth login

# Configurar projeto
gcloud config set project rj-sms-sandbox
```

### Erro: "Table not found"

Certifique-se que as tabelas base existem:
- `_gestacoes_historico`
- `_atendimentos_prenatal_aps_historico`
- `_linha_tempo_historico`

Crie-as com:

```sql
-- Criar tabela 1
CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us._gestacoes_historico` (
    data_snapshot DATE,
    -- outros campos conforme schema
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual;

-- Repetir para as outras 2 tabelas
```

### Erro ao gerar JSON do dashboard

Se o script processar os snapshots mas falhar ao gerar o JSON:

```bash
# Gerar JSON manualmente
cd ..  # Voltar para o diretório raiz
bq query --format=json --use_legacy_sql=false < query_dashboard_completo_clean.sql > dashboard_data_completo.json
```

**Arquivo query_dashboard_completo_clean.sql não encontrado:**
- Certifique-se de que o arquivo existe no diretório raiz do projeto
- O script espera encontrar o arquivo em: `../query_dashboard_completo_clean.sql`

**Dashboard não mostra todos os snapshots:**
- Limpe o cache do navegador (Ctrl+Shift+R ou Cmd+Shift+R)
- Verifique o console do navegador (F12) para erros de carregamento
- Confirme que o JSON foi gerado corretamente:
  ```bash
  cat ../dashboard_data_completo.json | python3 -m json.tool | grep -c "data_snapshot"
  ```

### Script trava ou demora muito

- **Tempo esperado**: ~1-2 minutos por data
- **Se > 5 minutos**: Verificar conexão de rede
- **Se > 10 minutos**: Cancelar (Ctrl+C) e verificar BigQuery Console

## 📈 Casos de Uso

### Histórico Mensal (2024)

```bash
./construir_historico.sh \
    2024-01-31 2024-02-29 2024-03-31 \
    2024-04-30 2024-05-31 2024-06-30 \
    2024-07-31 2024-08-31 2024-09-30 \
    2024-10-31 2024-11-30 2024-12-31
```

### Histórico Semanal (Janeiro 2024)

```bash
./construir_historico.sh \
    2024-01-07 2024-01-14 2024-01-21 2024-01-28
```

### Snapshot Único (Última Data)

```bash
./construir_historico.sh 2024-10-31
```

### Comparação Trimestral

```bash
./construir_historico.sh \
    2024-03-31 2024-06-30 2024-09-30 2024-12-31
```

## 🔧 Personalização

### Alterar Projeto/Dataset

Editar no início do script:

```bash
PROJETO="seu-projeto"
DATASET="seu-dataset"
```

### Adicionar Logs Detalhados

Descomentar a linha no script:

```bash
# set -x  # Debug mode
```

### Processar Apenas 1 ou 2 Scripts

Comentar linhas no bloco de execução:

```bash
if executar_sql "$SCRIPT_DIR/_hist_1_gestacoes.sql" "$DATA" "1/3 Gestações" && \
   # executar_sql "$SCRIPT_DIR/_hist_2_atd_prenatal_aps.sql" "$DATA" "2/3 Atendimentos" && \
   executar_sql "$SCRIPT_DIR/_hist_6_linha_tempo.sql" "$DATA" "3/3 Linha do Tempo"; then
```

## 📚 Arquivos Relacionados

- **Scripts SQL**:
  - `_hist_1_gestacoes.sql` - Identificação de gestações
  - `_hist_2_atd_prenatal_aps.sql` - Atendimentos pré-natal
  - `_hist_6_linha_tempo.sql` - Agregação final

- **Documentação**:
  - `../QUICK_START.md` - Guia rápido do sistema
  - `../README_HISTORICO_COMPLETO.md` - Documentação completa

## 🎯 Próximos Passos

Após gerar os snapshots históricos:

1. **Exportar para JSON** (para dashboard):
   ```bash
   bq query --format=json --use_legacy_sql=false < query_dashboard.sql > dados.json
   ```

2. **Criar série temporal** para análise:
   ```sql
   SELECT data_snapshot, COUNT(*) as total
   FROM _linha_tempo_historico
   GROUP BY data_snapshot
   ORDER BY data_snapshot;
   ```

3. **Visualizar evolução** no dashboard HTML desenvolvido
