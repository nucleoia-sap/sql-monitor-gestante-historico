# Quick Start - Construir Histórico de Gestações

Guia rápido para gerar snapshots históricos usando o script automatizado em **5 minutos**.

---

## 🚀 Início Rápido (2 Passos)

### Passo 1: Tornar o Script Executável (uma vez apenas)

```bash
cd SQL_histórico/
chmod +x construir_historico.sh
```

### Passo 2: Executar com Suas Datas

**Opção A: Passar datas como argumentos (recomendado para teste)**

```bash
./construir_historico.sh 2024-10-31
```

**Opção B: Configurar múltiplas datas no script**

1. Edite `construir_historico.sh` (linhas 26-39):

```bash
DATAS_PROCESSAR=(
    "2024-01-31"
    "2024-02-29"
    "2024-03-31"
    # Adicione suas datas aqui
)
```

2. Execute:

```bash
./construir_historico.sh
```

**Pronto!** O script processará as 3 etapas para cada data:
1. `_hist_1_gestacoes.sql` → Identifica gestações (~28.000 registros)
2. `_hist_2_atd_prenatal_aps.sql` → Captura atendimentos pré-natal (~300.000 registros)
3. `_hist_6_linha_tempo.sql` → Agrega indicadores (~28.000 registros)

---

## 📋 Pré-requisitos

Antes de executar, certifique-se de ter:

1. **BigQuery CLI instalado**:
   ```bash
   gcloud components install bq
   ```

2. **Autenticação configurada**:
   ```bash
   gcloud auth login
   gcloud config set project rj-sms-sandbox
   ```

3. **Acesso ao projeto**: `rj-sms-sandbox.sub_pav_us`

---

## 📊 O que o Script Faz

### Pipeline Automático para Cada Data:

```
data_referencia (ex: 2024-10-31)
    ↓
[1/3] _hist_1_gestacoes.sql
    → Tabela: _gestacoes_historico
    → Identifica gestações ativas na data
    ↓
[2/3] _hist_2_atd_prenatal_aps.sql
    → Tabela: _atendimentos_prenatal_aps_historico
    → Captura consultas pré-natal com sinais vitais
    ↓
[3/3] _hist_6_linha_tempo.sql
    → Tabela: _linha_tempo_historico
    → Agrega todos os indicadores clínicos
    ↓
[4/4] Gera dashboard_data_completo.json (automático)
    → JSON com todos os snapshots para visualização
```

### Tabelas Geradas (por snapshot):

| Tabela | Descrição | Registros Típicos |
|--------|-----------|-------------------|
| `_gestacoes_historico` | Gestações e puerpérios | ~28.000 |
| `_atendimentos_prenatal_aps_historico` | Consultas pré-natal | ~300.000 |
| `_linha_tempo_historico` | Agregação completa | ~28.000 |

### Arquivo Gerado (após todas as datas):

| Arquivo | Descrição |
|---------|-----------|
| `../dashboard_data_completo.json` | JSON com todos os snapshots para dashboard |

---

## ✅ Saída Esperada

```
============================================================
Script de Construção de Histórico de Gestações
============================================================

✅ BigQuery CLI encontrado
✅ Autenticado no projeto: rj-sms-sandbox

📅 Datas a processar: 2024-10-31
📊 Total: 1 data(s)

============================================================
📆 Processando data: 2024-10-31
============================================================
   ⏳ 1/3 Gestações...
   ✅ 1/3 Gestações concluído
   ⏳ 2/3 Atendimentos Pré-Natal...
   ✅ 2/3 Atendimentos Pré-Natal concluído
   ⏳ 3/3 Linha do Tempo...
   ✅ 3/3 Linha do Tempo concluído

   ✅ Snapshot 2024-10-31 concluído com sucesso!
   ⏱️  Tempo: 87s

============================================================
📊 Gerando JSON do Dashboard
============================================================

⏳ Executando query de agregação...
✅ JSON gerado com sucesso!
📁 Arquivo: dashboard_data_completo.json
📊 Snapshots incluídos: 1

============================================================
✅ PIPELINE COMPLETO EXECUTADO COM SUCESSO!
============================================================

🌐 PRÓXIMOS PASSOS:
1. Abra o dashboard no navegador:
   http://localhost:8000/dashboard_prescricoes_v2.html

2. Se necessário, inicie o servidor HTTP:
   python3 -m http.server 8000
```

---

## 🎯 Casos de Uso Comuns

### Caso 1: Teste Inicial (1 data)

```bash
./construir_historico.sh 2024-10-31
```

**Tempo estimado**: 1-2 minutos
**Use para**: Validar configuração e testar pipeline

### Caso 2: Histórico Mensal 2024 (12 datas)

```bash
./construir_historico.sh \
    2024-01-31 2024-02-29 2024-03-31 \
    2024-04-30 2024-05-31 2024-06-30 \
    2024-07-31 2024-08-31 2024-09-30 \
    2024-10-31 2024-11-30 2024-12-31
```

**Tempo estimado**: 20-40 minutos
**Use para**: Série temporal completa do ano

### Caso 3: Atualização Mensal

```bash
./construir_historico.sh $(date -d "$(date +%Y-%m-01) -1 day" +%Y-%m-%d)
```

**Tempo estimado**: 1-2 minutos
**Use para**: Adicionar último dia do mês anterior

---

## 📊 Consultar Resultados

### Query Básica

```sql
SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') AS em_puerperio
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = DATE('2024-10-31')
GROUP BY data_snapshot;
```

### Evolução Temporal

```sql
SELECT
    data_snapshot,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(total_consultas_prenatal >= 6) AS com_6_consultas,
    ROUND(100.0 * COUNTIF(total_consultas_prenatal >= 6) /
          NULLIF(COUNTIF(fase_atual = 'Gestação'), 0), 2) AS perc_adequacao
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### Verificar Snapshots Disponíveis

```sql
SELECT DISTINCT data_snapshot
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
ORDER BY data_snapshot DESC;
```

---

## ⚠️ Problemas Comuns

### Erro: "bq command not found"
```bash
# Instalar BigQuery CLI
gcloud components install bq
```

### Erro: "Permission denied"
```bash
# Tornar script executável
chmod +x construir_historico.sh
```

### Erro: "Not authenticated"
```bash
# Fazer login
gcloud auth login
gcloud config set project rj-sms-sandbox
```

### Erro: "Data inválida"
- Use formato **YYYY-MM-DD**
- Exemplos válidos: `2024-10-31`, `2024-01-31`

### Script parou no meio
- Veja no log qual data foi processada
- Remova datas já processadas do array
- Execute novamente com datas restantes

---

## 🔧 Personalização

### Alterar Projeto/Dataset

Edite `construir_historico.sh` (linhas 44-45):

```bash
PROJETO="seu-projeto"
DATASET="seu-dataset"
```

### Processar Apenas 1 ou 2 Scripts

Comente linhas no script (linha 199-201):

```bash
if executar_sql "$SCRIPT_DIR/_hist_1_gestacoes.sql" "$DATA" "1/3 Gestações" && \
   # executar_sql "$SCRIPT_DIR/_hist_2_atd_prenatal_aps.sql" "$DATA" "2/3 Atendimentos" && \
   executar_sql "$SCRIPT_DIR/_hist_6_linha_tempo.sql" "$DATA" "3/3 Linha do Tempo"; then
```

### Logs Detalhados

Adicione no início do script:

```bash
set -x  # Debug mode
```

---

## 📚 Próximos Passos

Após executar o Quick Start, consulte:

- **`README_CONSTRUIR_HISTORICO.md`**: Documentação completa do script
- **`../README_HISTORICO_COMPLETO.md`**: Documentação do sistema completo
- **`../RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md`**: Resultados de testes

---

## 💡 Dica

**Sempre teste com 1 data primeiro!**

```bash
# Teste primeiro:
./construir_historico.sh 2024-10-31

# Se funcionar, processe múltiplas datas:
./construir_historico.sh 2024-01-31 2024-02-29 2024-03-31
```

---

## 🌐 Visualizar Dashboard

Após gerar os snapshots:

```bash
# 1. Voltar ao diretório raiz
cd ..

# 2. Iniciar servidor HTTP
python3 -m http.server 8000

# 3. Abrir no navegador
# http://localhost:8000/dashboard_prescricoes_v2.html
```

O dashboard carregará automaticamente o arquivo `dashboard_data_completo.json` gerado.

---

**Última atualização**: 2025-12-09
