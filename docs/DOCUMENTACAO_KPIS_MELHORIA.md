# Documentação: KPIs de Indicadores de Melhoria - Gestantes

## Visão Geral

Este documento descreve os 6 KPIs de indicadores de melhoria para acompanhamento de gestantes em série histórica. Esses indicadores focam em **lacunas de cuidado** que representam oportunidades de melhoria no acompanhamento pré-natal.

> **Nota:** KPIs com baixo nível de maturidade, em evolução contínua.

---

## KPIs Implementados

### KPI 1: Gestantes com indicação de AAS sem prescrição

**Objetivo:** Identificar gestantes que têm indicação clínica para uso de AAS (Ácido Acetilsalicílico) para prevenção de pré-eclâmpsia, mas não receberam a prescrição.

**Definição:**
- **Numerador:** Gestantes com `tem_indicacao_aas = 1` E `tem_prescricao_aas = 0`
- **Denominador:** Total de gestantes com `tem_indicacao_aas = 1`

**Critérios de Indicação de AAS:**
- 1 ou mais fatores de ALTO risco para pré-eclâmpsia:
  - Histórico de pré-eclâmpsia
  - Gravidez gemelar
  - Obesidade (IMC ≥ 30)
  - Hipertensão crônica
  - Diabetes prévio
  - Doença renal
  - Doença autoimune
  - Reprodução assistida
  - Pré-eclâmpsia/hipertensão gestacional atual
- OU 2 ou mais fatores MODERADOS:
  - Nuliparidade
  - Idade ≥ 35 anos

**Campos Utilizados:**
- `tem_indicacao_aas` (INT64)
- `tem_prescricao_aas` (INT64)

**Meta Sugerida:** < 10%

---

### KPI 2: Gestantes com critérios de alto risco não encaminhadas

**Objetivo:** Identificar gestantes que possuem condições clínicas que requerem encaminhamento para pré-natal de alto risco, mas que não foram encaminhadas.

**Definição:**
- **Numerador:** Gestantes com `deve_encaminhar` preenchido E `houve_encaminhamento != 'Sim'`
- **Denominador:** Total de gestantes com `deve_encaminhar` preenchido

**Critérios de Alto Risco (campo `deve_encaminhar`):**
- Baseado na tabela `_cids_risco_gestacional_cat_encam`
- Condições como: diabetes prévio, hipertensão grave, cardiopatias, gemelaridade, etc.

**Campos Utilizados:**
- `deve_encaminhar` (STRING) - indica se há critério para encaminhamento
- `houve_encaminhamento` (STRING) - 'Sim' ou 'Não'
- `categorias_risco` (STRING) - categorias de risco identificadas

**Meta Sugerida:** < 5%

---

### KPI 3: Gestantes com sífilis com tratamento inadequado

**Objetivo:** Identificar gestantes diagnosticadas com sífilis que não receberam tratamento adequado conforme protocolo.

**Status:** ⚠️ **AGUARDANDO TABELA EXTERNA**

**Definição Esperada:**
- **Numerador:** Gestantes com `sifilis = 1` E tratamento inadequado (tabela externa)
- **Denominador:** Total de gestantes com `sifilis = 1`

**Critérios de Tratamento Adequado (a serem definidos na tabela externa):**
- Penicilina Benzatina aplicada conforme protocolo
- Número adequado de doses
- Parceiro tratado
- Exames de controle realizados

**Campos Utilizados:**
- `sifilis` (INT64) - flag de diagnóstico
- Tabela externa de adequação (a ser fornecida)

**Meta Sugerida:** 0% (todas devem ter tratamento adequado)

---

### KPI 4: Gestantes com mais de 30 dias sem consulta

**Objetivo:** Identificar gestantes que estão há mais de 30 dias sem atendimento pré-natal, indicando possível perda de seguimento.

**Definição:**
- **Numerador:** Gestantes com `mais_de_30_sem_atd = 'sim'`
- **Denominador:** Total de gestantes ativas

**Campos Utilizados:**
- `mais_de_30_sem_atd` (STRING) - 'sim' ou 'não'
- `dias_desde_ultima_consulta` (INT64) - dias desde última consulta

**Observações:**
- Protocolo recomenda consultas a cada 4 semanas no início
- Frequência aumenta no terceiro trimestre

**Meta Sugerida:** < 15%

---

### KPI 5: Gestantes sem prescrição de Carbonato de cálcio

**Objetivo:** Identificar gestantes que não receberam prescrição de Carbonato de cálcio, suplementação recomendada para prevenção de pré-eclâmpsia e outras complicações.

**Definição:**
- **Numerador:** Gestantes com `prescricao_carbonato_calcio = 'não'` OU `NULL`
- **Denominador:** Total de gestantes ativas

**Campos Utilizados:**
- `prescricao_carbonato_calcio` (STRING) - 'sim' ou 'não'

**Indicação Clínica:**
- Recomendado para todas as gestantes
- Especialmente importante em populações com baixa ingesta de cálcio
- Dose: 1.5-2g/dia

**Meta Sugerida:** < 20%

---

### KPI 6: Gestantes sem prescrição de ácido fólico

**Objetivo:** Identificar gestantes que não receberam prescrição de ácido fólico, suplementação essencial para prevenção de defeitos do tubo neural.

**Definição:**
- **Numerador:** Gestantes com `prescricao_acido_folico = 'não'` OU `NULL`
- **Denominador:** Total de gestantes ativas

**Campos Utilizados:**
- `prescricao_acido_folico` (STRING) - 'sim' ou 'não'

**Indicação Clínica:**
- Obrigatório para todas as gestantes
- Ideal: iniciar antes da concepção
- Deve ser mantido durante toda a gestação
- Dose: 0.4-5mg/dia (dependendo de fatores de risco)

**Meta Sugerida:** < 5%

---

## Estrutura dos Dados

### Tabela Fonte
`rj-sms-sandbox.sub_pav_us._linha_tempo_historico`

### Filtros Aplicados
- `fase_atual = 'Gestação'` (apenas gestações ativas)

### Granularidade
- **Série Histórica:** Por `data_snapshot`
- **Drill-down:** Por unidade (`clinica_nome`), área programática, equipe

---

## Queries Disponíveis

### 1. KPIs Agregados por Snapshot
Retorna os 6 KPIs para cada data_snapshot, permitindo análise de série histórica.

### 2. Drill-down por Paciente
Lista nominada de pacientes em cada indicador, para ação da equipe de saúde.

### 3. KPIs por Unidade
Comparação de desempenho entre diferentes unidades/equipes.

---

## Uso no Painel

Os KPIs são exibidos no painel de gestações com:
- Gráfico de linha mostrando evolução temporal
- Cards com valores atuais e variação
- Tabela de drill-down por unidade
- Lista de pacientes para busca ativa

---

## Limitações Conhecidas

1. **KPI de Sífilis:** Aguardando tabela externa com adequação de tratamento
2. **Prescrições:** Dependem da qualidade do registro no prontuário
3. **Encaminhamentos:** Baseado em dados do SISREG/SER, pode haver defasagem

---

## Histórico de Versões

| Data | Versão | Alterações |
|------|--------|------------|
| 2026-01-14 | 1.0 | Versão inicial com 5 KPIs + placeholder sífilis |

---

## Referências

- Protocolo de Pré-natal SMS-Rio
- Caderno de Atenção Básica - Pré-natal de Baixo Risco (MS)
- Linha-guia de Pré-natal de Alto Risco
