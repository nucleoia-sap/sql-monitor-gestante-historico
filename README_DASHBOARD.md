# Dashboard Pré-Natal - Guia de Uso

## 📊 Visão Geral

Dashboard interativo para visualização de indicadores de pré-natal com suporte a snapshots históricos.

## 🚀 Início Rápido

### Opção 1: Dados de Exemplo (Imediato)

1. Abra o arquivo `dashboard_prescricoes_v2.html` no navegador
2. O dashboard carregará automaticamente com 3 datas de exemplo:
   - 2024-10-31
   - 2024-11-30
   - 2024-12-31

### Opção 2: Dados Reais do BigQuery

1. **Execute a query completa:**

```bash
bq query --format=json --use_legacy_sql=false -q "$(cat query_dashboard_completo_clean.sql)" > dashboard_data_completo.json
```

2. **Ou pelo dashboard:**
   - Clique no botão "Atualizar Dados"
   - Copie o comando exibido no modal
   - Execute no terminal
   - Recarregue a página

## 📁 Arquivos Necessários

### Principais
- `dashboard_prescricoes_v2.html` - Dashboard principal
- `query_dashboard_completo.sql` - Query SQL completa

### Gerados (após execução)
- `dashboard_data_completo.json` - Dados de todos os snapshots

## 📋 Estrutura da Query SQL

A query em `query_dashboard_completo.sql` retorna:

```sql
SELECT
    data_snapshot,                      -- Data do snapshot

    -- Total
    total_gestantes_ativas,            -- INT64

    -- Prescrições
    gestantes_acido_folico,            -- INT64
    perc_acido_folico,                 -- FLOAT64
    gestantes_carbonato_calcio,        -- INT64
    perc_carbonato_calcio,             -- FLOAT64

    -- Condições Clínicas
    gestantes_hipertensao,             -- INT64
    perc_hipertensao,                  -- FLOAT64
    gestantes_diabetes,                -- INT64
    perc_diabetes,                     -- FLOAT64
    gestantes_sifilis,                 -- INT64
    perc_sifilis,                      -- FLOAT64

    -- Adequação Terapêutica
    hipertensas_com_medicacao,         -- INT64
    perc_hipertensas_medicadas,        -- FLOAT64
    diabeticas_com_medicacao,          -- INT64
    perc_diabeticas_medicadas          -- FLOAT64

FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot
ORDER BY data_snapshot DESC;
```

## 📊 Formato do JSON Gerado

```json
[
  {
    "data_snapshot": "2024-10-31",
    "total_gestantes_ativas": "85633",
    "gestantes_acido_folico": "64274",
    "perc_acido_folico": "75.05",
    "gestantes_carbonato_calcio": "52413",
    "perc_carbonato_calcio": "61.20",
    "gestantes_hipertensao": "12847",
    "perc_hipertensao": "15.00",
    "gestantes_diabetes": "8563",
    "perc_diabetes": "10.00",
    "gestantes_sifilis": "856",
    "perc_sifilis": "1.00",
    "hipertensas_com_medicacao": "10278",
    "perc_hipertensas_medicadas": "80.00",
    "diabeticas_com_medicacao": "6850",
    "perc_diabeticas_medicadas": "80.00"
  },
  {
    "data_snapshot": "2024-11-30",
    ...
  }
]
```

**Nota:** BigQuery retorna números como strings no JSON. O dashboard converte automaticamente.

## 🎯 Funcionalidades do Dashboard

### Calendário Interativo
- ✅ Navegação entre meses (← →)
- ✅ Marcação visual de datas com dados disponíveis (verde)
- ✅ Seleção de data para visualização
- ✅ Destaque da data atual (borda dourada)
- ✅ Destaque da data selecionada (fundo branco)

### Seções
1. **Visão Geral** - Cards com indicadores principais
2. **Prescrições** - Cobertura de ácido fólico e carbonato de cálcio
3. **Condições** - Prevalência de hipertensão, diabetes e sífilis
4. **Adequação** - Taxas de medicação adequada
5. **Dados Completos** - Tabela consolidada

### Atualização de Dados
- Botão "Atualizar Dados" abre modal com instruções
- Comando BigQuery pré-formatado
- Função de copiar para área de transferência

## 🔧 Troubleshooting

### Calendário não mostra datas marcadas
**Causa:** Arquivo `dashboard_data_completo.json` não encontrado ou malformado

**Solução:**
1. Verifique se o arquivo existe na mesma pasta do HTML
2. Valide o JSON (use `jq` ou validador online)
3. Verifique se o formato corresponde ao esperado

### Dados não carregam ao clicar na data
**Causa:** Data não tem dados no JSON carregado

**Solução:**
1. Execute novamente a query para garantir que todas as datas estão incluídas
2. Verifique no console do navegador (F12) se há erros

### Query demora muito
**Causa:** Tabela `_linha_tempo_historico` muito grande

**Solução:**
- Adicione filtro por período na query:
```sql
WHERE fase_atual = 'Gestação'
  AND data_snapshot >= '2024-01-01'
GROUP BY data_snapshot
```

## 📈 Indicadores Calculados

### Prescrições (%)
- **Ácido Fólico:** `gestantes_com_prescricao / total_gestantes * 100`
- **Carbonato Cálcio:** `gestantes_com_prescricao / total_gestantes * 100`

### Condições (%)
- **Hipertensão:** `gestantes_hipertensas / total_gestantes * 100`
- **Diabetes:** `gestantes_diabeticas / total_gestantes * 100`
- **Sífilis:** `gestantes_com_sifilis / total_gestantes * 100`

### Adequação Terapêutica (%)
- **Hipertensas Medicadas:** `hipertensas_com_medicacao / total_hipertensas * 100`
- **Diabéticas Medicadas:** `diabeticas_com_medicacao / total_diabeticas * 100`

## 🎨 Design System

**Tipografia:**
- Display: Fraunces (serif)
- Interface: IBM Plex Sans (sans-serif)

**Cores:**
- Primary: Blue (#0369A1)
- Success: Green (#059669)
- Warning: Orange (#D97706)
- Danger: Red (#DC2626)

## 🔒 Segurança

- ⚠️ Dashboard lê apenas arquivos JSON locais
- ⚠️ Não envia dados para servidores externos
- ⚠️ Dados PHI/LGPD - usar apenas em ambiente autorizado

## 📞 Suporte

Para dúvidas sobre:
- **Query SQL:** Consulte `CLAUDE.md` no projeto
- **BigQuery:** Documentação oficial do GCP
- **Dashboard:** Inspecione console do navegador (F12)

## 📝 Changelog

### v2.0 (Atual)
- ✅ Calendário interativo com marcação de datas
- ✅ Query SQL unificada com todos os indicadores
- ✅ Carregamento de dados completo em arquivo único
- ✅ Layout de duas colunas (sidebar + conteúdo)
- ✅ Modal de instruções BigQuery
- ✅ Dados embarcados para demonstração

### v1.0
- Dashboard básico com dados estáticos
- Sem calendário
- Carregamento manual de dados
