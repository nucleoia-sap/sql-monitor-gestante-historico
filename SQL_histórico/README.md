# Pipeline Automatizado de Histórico de Pré-Natal

## 📋 Visão Geral

Sistema automatizado para construção de snapshots históricos do acompanhamento pré-natal na rede municipal de saúde do Rio de Janeiro. Este diretório contém scripts e ferramentas para processar múltiplas datas em lote, gerando dados históricos para análise temporal e visualização em dashboard.

**Diferencial**: Pipeline completo com geração automática de JSON para dashboard web.

## 🎯 Propósito

Construir série temporal de indicadores de pré-natal através de:
- ✅ Execução automatizada de múltiplos snapshots
- ✅ Validação de pré-requisitos (BigQuery CLI, autenticação)
- ✅ Processamento sequencial com controle de erros
- ✅ Geração automática de dados para dashboard
- ✅ Relatórios detalhados de execução

## 📁 Arquivos do Pipeline

### Scripts SQL

| Arquivo | Procedimento | Saída | Função |
|---------|--------------|-------|--------|
| `_hist_1_gestacoes.sql` | `proced_1_gestacoes_historico` | `_gestacoes_historico` | Identifica e classifica gestações (CIDs Z32.1, Z34%, Z35%) |
| `_hist_2_atd_prenatal_aps.sql` | `proced_2_atd_prenatal_aps_historico` | `_atendimentos_prenatal_aps_historico` | Atendimentos SOAP com medidas antropométricas |
| `_hist_6_linha_tempo.sql` | `proced_6_linha_tempo_historico` | `_linha_tempo_historico` | Agregação completa com todos os indicadores |

### Scripts Bash

| Arquivo | Tipo | Função |
|---------|------|--------|
| `construir_historico.sh` | **Script principal** | Executa pipeline completo + gera JSON do dashboard |
| `exemplo_uso.sh` | Exemplos | Demonstra diferentes padrões de uso |

### Documentação

| Arquivo | Conteúdo |
|---------|----------|
| `README_CONSTRUIR_HISTORICO.md` | Guia completo de uso do script automatizado |
| `README.md` | Esta documentação (overview do pipeline) |

## 🔄 Arquitetura do Pipeline

```
┌─────────────────────────────────────────────────────┐
│  ENTRADA: Lista de datas (YYYY-MM-DD)               │
└─────────────────────┬───────────────────────────────┘
                      ↓
        ┌─────────────────────────────┐
        │  Para cada data:            │
        │  1. _hist_1_gestacoes.sql   │ → INSERT INTO _gestacoes_historico
        │  2. _hist_2_atd_prenatal    │ → INSERT INTO _atendimentos_prenatal_aps_historico
        │  3. _hist_6_linha_tempo     │ → INSERT INTO _linha_tempo_historico
        └─────────────┬───────────────┘
                      ↓
        ┌─────────────────────────────┐
        │  Após processar todas:      │
        │  4. Query dashboard         │ → dashboard_data_completo.json
        └─────────────┬───────────────┘
                      ↓
        ┌─────────────────────────────┐
        │  SAÍDA:                     │
        │  • Snapshots em BigQuery    │
        │  • JSON para dashboard      │
        │  • Relatório de execução    │
        └─────────────────────────────┘
```

## 🚀 Quick Start

### 1. Pré-requisitos

```bash
# Verificar BigQuery CLI
bq version

# Se não instalado:
gcloud components install bq

# Autenticar
gcloud auth login
gcloud config set project rj-sms-sandbox
```

### 2. Executar Pipeline

**Opção A: Passar datas como argumentos** (Recomendado para testes)

```bash
cd SQL_histórico
./construir_historico.sh 2024-10-01
```

**Opção B: Configurar datas no script** (Recomendado para produção)

```bash
# Editar o script
nano construir_historico.sh

# Descomentar e preencher o array DATAS_PROCESSAR (linhas 26-39)
DATAS_PROCESSAR=(
    "2024-01-01"
    "2024-02-01"
    "2024-03-01"
    # ... adicionar suas datas
)

# Executar
./construir_historico.sh
```

### 3. Visualizar Resultados

```bash
# Iniciar servidor HTTP (se não estiver rodando)
cd ..  # Voltar para raiz do projeto
python3 -m http.server 8000

# Abrir no navegador
# http://localhost:8000/dashboard_prescricoes_v2.html
```

## 📊 Ordem de Execução Detalhada

### Fase 1: Processamento por Data

Para cada data especificada:

```
1. _hist_1_gestacoes.sql (1/3)
   ├─ Identifica gestações por CIDs obstétricos
   ├─ Agrupa inícios com janela de 60 dias
   ├─ Classifica fase: Gestação/Puerpério/Encerrada
   └─ INSERT INTO _gestacoes_historico

2. _hist_2_atd_prenatal_aps.sql (2/3)
   ├─ Depende: _gestacoes_historico com data_snapshot
   ├─ Extrai atendimentos SOAP em APS
   ├─ Calcula IMC, peso inicial, ganho de peso
   └─ INSERT INTO _atendimentos_prenatal_aps_historico

3. _hist_6_linha_tempo.sql (3/3)
   ├─ Depende: _gestacoes_historico + _atendimentos_prenatal_aps_historico
   ├─ Agrega condições clínicas, medicações, encaminhamentos
   ├─ Calcula indicadores de hipertensão, diabetes, prescrições
   └─ INSERT INTO _linha_tempo_historico
```

### Fase 2: Geração do Dashboard

Após processar todas as datas com sucesso:

```
4. query_dashboard_completo_clean.sql
   ├─ Agrega dados de TODOS os snapshots
   ├─ Calcula indicadores percentuais
   ├─ Exporta em formato JSON
   └─ Salva em: ../dashboard_data_completo.json
```

## 💡 Casos de Uso

### 1. Snapshot Único (Teste Inicial)

```bash
# Processar apenas última data disponível
./construir_historico.sh 2024-10-01

# ✅ Útil para: Validar pipeline, testar nova data
# ⏱️  Tempo esperado: ~1-2 minutos
```

### 2. Comparação Antes/Depois

```bash
# Dois pontos no tempo
./construir_historico.sh 2024-07-01 2024-10-01

# ✅ Útil para: Avaliar impacto de intervenções
# 📊 Dashboard: Mostra evolução entre períodos
```

### 3. Série Mensal Completa

```bash
# Todos os meses de 2024
./construir_historico.sh \
    2024-01-01 2024-02-01 2024-03-01 \
    2024-04-01 2024-05-01 2024-06-01 \
    2024-07-01 2024-08-01 2024-09-01 \
    2024-10-01 2024-11-01 2024-12-01

# ✅ Útil para: Análise temporal completa do ano
# ⏱️  Tempo esperado: ~12-24 minutos
# 📊 Dashboard: Gráficos de tendência anual
```

### 4. Série Trimestral

```bash
# Último dia de cada trimestre
./construir_historico.sh \
    2024-03-01 2024-06-01 2024-09-01 2024-12-01

# ✅ Útil para: Relatórios trimestrais, redução de processamento
# ⏱️  Tempo esperado: ~4-8 minutos
```

### 5. Série Semanal (Mês Específico)

```bash
# Todas as segundas de outubro/2024
./construir_historico.sh \
    2024-10-07 2024-10-14 2024-10-21 2024-10-28

# ✅ Útil para: Análise detalhada de curto prazo
# 📊 Dashboard: Granularidade semanal
```

### 6. Datas Customizadas (Eventos Específicos)

```bash
# Marcos temporais relevantes
./construir_historico.sh \
    2024-01-15 2024-04-22 2024-07-10 2024-10-31

# ✅ Útil para: Antes/depois de campanhas, mudanças de protocolo
```

## 🔍 Validação de Resultados

### Verificar Snapshots no BigQuery

```sql
-- Listar snapshots processados
SELECT DISTINCT data_snapshot
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
ORDER BY data_snapshot DESC;

-- Contagem por snapshot
SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS ativas,
    COUNTIF(fase_atual = 'Puerpério') AS puerperio
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
GROUP BY data_snapshot
ORDER BY data_snapshot DESC;
```

### Verificar JSON do Dashboard

```bash
# Contar snapshots no JSON
cat ../dashboard_data_completo.json | python3 -m json.tool | grep -c "data_snapshot"

# Ver datas incluídas
cat ../dashboard_data_completo.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
for row in data:
    print(row['data_snapshot'], '-', row['total_gestantes_ativas'], 'gestantes')
"
```

### Verificar Consistência Entre Tabelas

```sql
-- Garantir que todas as 3 tabelas têm dados para mesmas datas
WITH snapshots_por_tabela AS (
    SELECT DISTINCT data_snapshot, 'gestacoes' AS tabela
    FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
    UNION ALL
    SELECT DISTINCT data_snapshot, 'atendimentos'
    FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`
    UNION ALL
    SELECT DISTINCT data_snapshot, 'linha_tempo'
    FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
)
SELECT
    data_snapshot,
    COUNT(DISTINCT tabela) AS tabelas_com_dados,
    STRING_AGG(tabela, ', ') AS tabelas_presentes
FROM snapshots_por_tabela
GROUP BY data_snapshot
HAVING COUNT(DISTINCT tabela) < 3  -- Alerta se faltar alguma tabela
ORDER BY data_snapshot;
```

## ⚙️ Funcionamento Interno

### Substituição Dinâmica de Datas

O script usa `sed` para substituir a data em tempo de execução:

```bash
# Conteúdo original do SQL
DECLARE data_referencia DATE DEFAULT DATE('2024-07-01');

# Script substitui por:
DECLARE data_referencia DATE DEFAULT DATE('2024-10-01');  # Data atual do loop

# Arquivo temporário criado → executado → deletado
```

### Controle de Erros

```bash
# Interrompe se qualquer SQL falhar
set -e

# Rastreia sucessos e falhas
for DATA in "${DATAS_PROCESSAR[@]}"; do
    if executar_sql "1_gestacoes" && \
       executar_sql "2_atendimentos" && \
       executar_sql "6_linha_tempo"; then
        SUCESSO++
    else
        FALHAS++
        # Continua com próxima data
    fi
done
```

### Geração Condicional do JSON

```bash
# JSON só é gerado se TODAS as datas tiveram sucesso
if [ $FALHAS -eq 0 ]; then
    gerar_json_dashboard()
else
    echo "⚠️  Snapshots processados com falhas, JSON não gerado"
fi
```

## 📈 Indicadores Disponíveis no Dashboard

### Prescrições e Suplementação

| Indicador | Campo JSON | Descrição |
|-----------|-----------|-----------|
| Ácido Fólico | `perc_acido_folico` | % gestantes com prescrição de ácido fólico |
| Carbonato de Cálcio | `perc_carbonato_calcio` | % gestantes com prescrição de cálcio |

### Condições Clínicas

| Indicador | Campo JSON | Descrição |
|-----------|-----------|-----------|
| Hipertensão | `perc_hipertensao` | % gestantes com diagnóstico de hipertensão |
| Diabetes | `perc_diabetes` | % gestantes com diagnóstico de diabetes |
| Sífilis | `perc_sifilis` | % gestantes com diagnóstico de sífilis |

### Controle de Tratamento

| Indicador | Campo JSON | Descrição |
|-----------|-----------|-----------|
| Hipertensas Medicadas | `perc_hipertensas_medicadas` | % hipertensas com medicação segura |
| Diabéticas Medicadas | `perc_diabeticas_medicadas` | % diabéticas com antidiabético |

### Dados Agregados

| Campo | Descrição |
|-------|-----------|
| `total_gestantes_ativas` | Total de gestações ativas no snapshot |
| `gestantes_acido_folico` | Contagem absoluta com ácido fólico |
| `hipertensas_com_medicacao` | Contagem absoluta com anti-hipertensivos |

## ⚠️ Troubleshooting

### Erro: "bq command not found"

```bash
# Instalar BigQuery CLI
gcloud components install bq

# Verificar instalação
bq version
```

### Erro: "Not authenticated"

```bash
# Fazer login
gcloud auth login

# Configurar projeto
gcloud config set project rj-sms-sandbox

# Verificar autenticação
bq ls --project_id=rj-sms-sandbox
```

### Erro: "Permission denied"

```bash
# Tornar script executável (apenas primeira vez)
chmod +x construir_historico.sh

# Verificar permissões
ls -l construir_historico.sh
# Deve mostrar: -rwxr-xr-x
```

### Erro: "Table not found: _gestacoes_historico"

**Causa**: Tabelas históricas não foram criadas no BigQuery

**Solução**:
```sql
-- Criar tabela _gestacoes_historico
CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us._gestacoes_historico` (
    data_snapshot DATE,
    id_hci STRING,
    id_gestacao STRING,
    id_paciente STRING,
    -- ... outros campos conforme schema
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual;

-- Repetir para:
-- _atendimentos_prenatal_aps_historico
-- _linha_tempo_historico
```

### Script processa datas mas não gera JSON

**Sintomas**: Mensagem "⚠️ Snapshots processados, mas houve erro ao gerar JSON do dashboard"

**Causas Comuns**:
1. Arquivo `query_dashboard_completo_clean.sql` não encontrado
2. Erro na query do dashboard
3. Permissão de escrita no diretório

**Soluções**:
```bash
# Verificar existência da query
ls -l ../query_dashboard_completo_clean.sql

# Gerar JSON manualmente
cd ..
bq query --format=json --use_legacy_sql=false < query_dashboard_completo_clean.sql > dashboard_data_completo.json

# Verificar permissões de escrita
touch dashboard_data_completo.json
rm dashboard_data_completo.json
```

### Dashboard não mostra todos os snapshots

**Sintomas**: JSON tem 3 snapshots mas dashboard mostra apenas 2

**Causa**: Cache do navegador

**Solução**:
```bash
# Hard refresh no navegador
# Windows/Linux: Ctrl + Shift + R
# Mac: Cmd + Shift + R

# Se persistir, limpar cache completo
# Ctrl + Shift + Delete (ou Cmd + Shift + Delete)
# Marcar "Imagens e arquivos em cache"
```

### Performance muito lenta

**Sintomas**: Cada data leva > 5 minutos para processar

**Causas**:
- Volume grande de dados
- Horário de pico do BigQuery
- Conexão de rede lenta

**Soluções**:
```bash
# Processar em horários de baixo uso (madrugada, finais de semana)
# Reduzir número de datas por execução
# Verificar status do BigQuery: https://status.cloud.google.com/

# Monitorar jobs no BigQuery Console
# https://console.cloud.google.com/bigquery?project=rj-sms-sandbox
```

### Falha em data específica

**Sintomas**: Algumas datas processam, outras falham

**Causa**: Dados inconsistentes ou faltantes naquela data

**Solução**:
```bash
# Executar SQL manualmente para investigar
bq query --use_legacy_sql=false < _hist_1_gestacoes.sql

# Verificar logs de erro detalhados
# Procurar mensagens específicas do BigQuery

# Remover data problemática da lista e reprocessar demais
```

## 🎯 Boas Práticas

### ✅ Recomendações

1. **Teste com 1 data primeiro**: Valide pipeline antes de processar série completa
   ```bash
   ./construir_historico.sh 2024-10-01  # Teste
   ```

2. **Use datas do último dia útil do período**: Para snapshots mensais
   ```bash
   # ✅ BOM: Último dia do mês
   ./construir_historico.sh 2024-01-31 2024-02-29
   ```

3. **Processe em horários de baixo uso**: Melhor performance
   - Madrugada: 00h-06h
   - Finais de semana

4. **Monitore o relatório final**: Verifique sucessos/falhas
   ```bash
   ============================================================
   📊 RELATÓRIO FINAL
   ============================================================
   ✅ Sucessos: 12
   ❌ Falhas: 0
   ⏱️  Tempo total: 1847s
   ```

5. **Valide consistência**: Execute queries de verificação
   ```sql
   -- Ver SQL de validação na seção anterior
   ```

6. **Mantenha backups**: Antes de grandes reprocessamentos
   ```bash
   # Exportar tabela atual
   bq extract \
     rj-sms-sandbox:sub_pav_us._linha_tempo_historico \
     gs://seu-bucket/backup/linha_tempo_historico_$(date +%Y%m%d).json
   ```

### ❌ Evitar

1. **Não execute múltiplas instâncias simultaneamente**: Causa conflitos de INSERT
2. **Não misture datas aleatórias**: Prefira séries contínuas para análise temporal
3. **Não ignore falhas**: Investigue e corrija antes de continuar
4. **Não processe em horários de pico**: Performance degradada
5. **Não execute manualmente cada SQL**: Use o script automatizado

## 🔐 Segurança e Compliance

### Dados Protegidos (LGPD/HIPAA)

⚠️ **ATENÇÃO**: Este pipeline processa dados de saúde protegidos (PHI)

**Obrigações**:
- ✅ Acesso restrito a profissionais autorizados
- ✅ Logs de acesso habilitados
- ✅ Dados anonimizados em dashboards públicos
- ✅ Retenção conforme políticas institucionais

**Boas práticas**:
```bash
# Nunca compartilhar credenciais
# Usar contas de serviço com permissões mínimas
# Revisar periodicamente acessos
# Monitorar uso indevido
```

## 📊 Estrutura de Dados

### Tabelas Históricas

Todas as tabelas usam este padrão:

```sql
CREATE TABLE `_[nome]_historico` (
    data_snapshot DATE,        -- ← Particionamento
    id_paciente STRING,        -- ← Clustering
    fase_atual STRING,         -- ← Clustering
    -- demais campos específicos
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual;
```

**Benefícios**:
- 🚀 Queries rápidas com filtro por `data_snapshot`
- 💰 Custo reduzido (scanning otimizado)
- 📦 Dados organizados por data e paciente

### JSON do Dashboard

```json
[
  {
    "data_snapshot": "2024-10-01",
    "total_gestantes_ativas": 27312,
    "gestantes_acido_folico": 17614,
    "perc_acido_folico": 64.49,
    "gestantes_hipertensao": 1069,
    "perc_hipertensao": 3.91,
    // ... outros indicadores
  },
  // ... outros snapshots
]
```

## 🚀 Integração com Dashboard

### Fluxo Completo

```
1. Executar script → processa datas → INSERT BigQuery
                                           ↓
2. Query dashboard → agrega indicadores → JSON
                                           ↓
3. Navegador → carrega JSON → renderiza gráficos
```

### Atualização Automática

Após executar o script:

```bash
# Script já fez:
# ✅ Processou todas as datas
# ✅ Gerou dashboard_data_completo.json
# ✅ Dashboard automaticamente carrega novos dados

# Você só precisa:
# 1. Hard refresh no navegador (Ctrl+Shift+R)
# 2. Navegar pelas datas no calendário
```

### Customização do Dashboard

Para adicionar novos indicadores:

1. **Editar query do dashboard**: `../query_dashboard_completo_clean.sql`
   ```sql
   -- Adicionar nova coluna
   COUNTIF(condicao_nova = 1) AS novo_indicador,
   ```

2. **Reprocessar JSON**: Script faz automaticamente
   ```bash
   ./construir_historico.sh 2024-10-01
   ```

3. **Atualizar HTML do dashboard**: `../dashboard_prescricoes_v2.html`
   ```javascript
   // Adicionar na função processCompleteData()
   novo_indicador: parseInt(row.novo_indicador || 0)
   ```

## 📚 Referências

### Documentação Relacionada

| Arquivo | Descrição |
|---------|-----------|
| `../README_HISTORICO_COMPLETO.md` | Sistema completo de procedimentos históricos |
| `../CLAUDE.md` | Conceitos de negócio e lógica clínica |
| `README_CONSTRUIR_HISTORICO.md` | Guia detalhado do script bash |
| `exemplo_uso.sh` | Exemplos práticos de execução |

### Documentação Técnica

- **BigQuery CLI**: https://cloud.google.com/bigquery/docs/bq-command-line-tool
- **SQL Parametrizado**: https://cloud.google.com/bigquery/docs/parameterized-queries
- **Bash Scripting**: https://www.gnu.org/software/bash/manual/

### Referências Clínicas

- **Pré-Natal**: Ministério da Saúde - Cadernos de Atenção Básica nº 32
- **CID-10**: Capítulo XV (O00-O99) - Gravidez, parto e puerpério
- **ICD Obstétrico**: Z32.1, Z34%, Z35% (gestação confirmada, supervisão)

## 🎯 Roadmap

### Próximas Melhorias

- [ ] Adicionar flag `--parallel` para processar datas em paralelo
- [ ] Implementar retry automático para falhas temporárias
- [ ] Adicionar exportação para CSV além de JSON
- [ ] Criar dashboards específicos por indicador (HAS, DM, etc.)
- [ ] Implementar versionamento de schemas
- [ ] Adicionar testes automatizados de consistência
- [ ] Criar notificações por email em caso de falha
- [ ] Adicionar suporte para processar apenas tabelas específicas

### Melhorias no Dashboard

- [ ] Filtros por região/clínica
- [ ] Comparação de períodos lado a lado
- [ ] Exportação de gráficos como imagem
- [ ] Alertas visuais para indicadores críticos
- [ ] Previsão de tendências (machine learning)

## 💬 Suporte

Para questões sobre:
- **Uso do script**: Consulte `README_CONSTRUIR_HISTORICO.md`
- **Lógica de negócio**: Consulte `../README_HISTORICO_COMPLETO.md`
- **Performance**: Verifique plano de execução no BigQuery Console
- **Erros**: Consulte seção de Troubleshooting acima

## 📝 Licença

Este projeto faz parte do sistema de informação em saúde da Secretaria Municipal de Saúde do Rio de Janeiro.

**Uso restrito**: Dados protegidos por LGPD (Lei Geral de Proteção de Dados).

---

**Última atualização**: Dezembro 2024
**Versão**: 2.0 - Pipeline automatizado com geração de JSON do dashboard
