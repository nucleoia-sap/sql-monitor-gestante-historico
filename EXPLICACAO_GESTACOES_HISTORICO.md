# Explicação Detalhada: Query de Gestações Históricas

## 📋 Visão Geral

Esta query identifica e classifica gestações em um sistema de saúde, reconstruindo o histórico de cada gestação desde o início (DUM - Data da Última Menstruação) até o fim (parto/aborto), e classificando em que fase cada gestação estava em uma data específica.

**Objetivo**: Dado uma `data_referencia`, identificar todas as gestações que estavam ativas (Gestação) ou recém-finalizadas (Puerpério) naquela data.

---

## 🔧 Problema Resolvido pela Correção

### ❌ **Problema Original**
A query antiga aplicava filtro temporal **antes** de calcular a data de início da gestação:
- Filtrava eventos de CID nos últimos 340 dias
- **Problema**: Perdia gestações antigas cujo último registro de CID era antigo, mas que ainda estavam ativas

### ✅ **Solução Implementada**
A query corrigida:
1. **Primeiro** calcula a data de início (DUM) de TODAS as gestações
2. **Depois** aplica o filtro temporal sobre a data de início calculada
3. **Resultado**: Captura corretamente gestações ativas, mesmo que os CIDs sejam antigos

---

## 📊 Passo a Passo da Query

### **Passo 1: Cadastro de Pacientes** (linhas 12-22)
```sql
cadastro_paciente AS (...)
```

**O que faz**: Busca dados básicos de todos os pacientes
- Nome
- ID do paciente
- Idade calculada na data de referência

**Por que é importante**: Precisamos desses dados para enriquecer as gestações identificadas.

---

### **Passo 2: Eventos Brutos de Gestação** (linhas 29-63)

```sql
eventos_brutos AS (...)
```

**O que faz**: Busca **TODOS** os registros de CIDs relacionados a gestação

**CIDs de Gestação**:
- `Z32.1`: Gravidez confirmada
- `Z34%`: Supervisão de gravidez normal
- `Z35%`: Supervisão de gravidez de alto risco

**✅ Correção Importante**:
- **SEM filtro temporal aqui** (anteriormente filtrava por 340 dias)
- Considera CIDs com status `ATIVO` **E** `RESOLVIDO` (anteriormente só ATIVO)

**Por que**: Precisamos de TODOS os registros históricos para calcular corretamente a DUM.

---

### **Passo 3: Separar Eventos de Gestação** (linhas 68-72)

```sql
eventos_gestacao AS (...)
```

**O que faz**: Filtra apenas eventos do tipo 'gestacao'

---

### **Passo 4: Detectar Novas Gestações** (linhas 74-108)

```sql
eventos_com_periodo AS (...)
eventos_com_grupo_gestacao AS (...)
```

**O que faz**: Agrupa eventos da mesma gestação

**Lógica**:
- Se há mais de **60 dias** entre dois eventos → nova gestação
- Eventos dentro de 60 dias → mesma gestação
- Cada grupo recebe um `grupo_gestacao` único

**Exemplo**:
```
Paciente A:
- 2024-01-15 (CID Z34) → grupo_gestacao = 1
- 2024-02-10 (CID Z34) → grupo_gestacao = 1 (mesma gestação)
- 2024-08-01 (CID Z34) → grupo_gestacao = 2 (nova gestação, >60 dias)
```

---

### **Passo 5: Calcular DUM por MODA** (linhas 110-152)

```sql
frequencia_datas AS (...)
moda_por_grupo_gestacao AS (...)
inicios_por_moda AS (...)
```

**✅ NOVA LÓGICA CRÍTICA**: Data de início = **MODA** (valor mais frequente)

**Por que MODA?**

Em prontuários eletrônicos, a DUM evolui assim:

1. **1ª consulta** (sem ultrassom): DUM imprecisa baseada em memória da paciente
   - Registrada: `2024-01-15`

2. **2ª-4ª consultas** (antes do ultrassom): DUM ainda imprecisa, pode variar
   - Registrada: `2024-01-10`, `2024-01-20`, `2024-01-15`

3. **5ª consulta** (após ultrassom): DUM corrigida e validada
   - Registrada: `2024-01-12` ← **DUM correta**

4. **6ª-10ª consultas**: DUM **se repete** em todas as consultas seguintes
   - Registrada: `2024-01-12`, `2024-01-12`, `2024-01-12`, `2024-01-12`

**Resultado**: `2024-01-12` é a MODA (aparece 5x) → **DUM mais confiável**

**Algoritmo**:
1. Conta quantas vezes cada data aparece
2. Seleciona a data com maior frequência
3. Em caso de empate, usa a data mais recente

---

### **Passo 6: Identificar Finais de Gestação** (linhas 157-163)

```sql
finais AS (...)
```

**O que faz**: Busca CIDs de gestação com status `RESOLVIDO`

**Significado**: Quando um CID de gestação é marcado como `RESOLVIDO`, significa que a gestação terminou (parto ou aborto).

---

### **Passo 7: Montar Gestações Completas** (linhas 168-199)

```sql
gestacoes_unicas AS (...)
```

**O que faz**: Combina início (DUM) com fim (RESOLVIDO)

**Lógica**:
- Para cada início (MODA calculada)
- Busca o próximo final (CID RESOLVIDO) **após** essa data
- Cria ID único: `id_paciente-numero_gestacao`

**Exemplo**:
```
Paciente 12345:
- Gestação 1: 2023-05-10 → 2023-12-20 (id: 12345-1)
- Gestação 2: 2024-06-01 → NULL (id: 12345-2, ainda ativa)
```

---

### **Passo 8: Aplicar Regra de Auto-encerramento** (linhas 204-215)

```sql
gestacoes_com_status AS (...)
```

**O que faz**: Define `data_fim_efetiva`

**Lógica**:
- Se tem `data_fim` (CID RESOLVIDO) → usa `data_fim`
- Se NÃO tem `data_fim` **E** já passaram 299 dias → **auto-encerra** em 299 dias
- Senão → gestação ainda ativa (NULL)

**Por que 299 dias?**:
- Gestação normal: ~280 dias (40 semanas)
- Margem de segurança: até 299 dias (42 semanas e 5 dias)
- Após 299 dias sem parto registrado → assume que a gestação terminou

---

### **Passo 9: Classificar Fase Atual** (linhas 220-268)

```sql
gestacoes_com_fase AS (...)
```

**O que faz**: Determina se a gestação estava em **Gestação**, **Puerpério** ou **Encerrada** na `data_referencia`

**Lógica de Classificação**:

#### **🤰 Gestação**
```
Condições:
✅ data_inicio <= data_referencia
✅ data_fim >= data_referencia (ou data_fim é NULL)
✅ não excedeu 299 dias
```

**Exemplo**:
```
Gestação: 2025-05-01 → NULL
data_referencia: 2025-07-01
→ Fase: Gestação (ainda em curso)
```

#### **👶 Puerpério**
```
Condições:
✅ data_fim < data_referencia
✅ data_referencia <= data_fim + 42 dias
```

**Exemplo**:
```
Gestação: 2025-01-01 → 2025-09-15
data_referencia: 2025-10-20
→ Fase: Puerpério (15 set + 35 dias = 20 out)
```

**Por que 42 dias?**: Puerpério (resguardo) dura até 6 semanas (42 dias) após o parto.

#### **🏁 Encerrada**
```
Condições:
✅ data_fim + 42 dias < data_referencia
OU
✅ data_inicio + 299 dias < data_referencia (auto-encerrada)
```

**Trimestre e IG (Idade Gestacional)**:
- **1º trimestre**: 0-13 semanas
- **2º trimestre**: 14-27 semanas
- **3º trimestre**: ≥28 semanas

---

### **Passo 10: ✅ Filtro Temporal (NOVO)** (linhas 276-281)

```sql
filtrado_temporal AS (...)
```

**✅ CORREÇÃO CRÍTICA**: Filtro aplicado **APÓS** calcular `data_inicio`

**Lógica**:
```sql
WHERE data_inicio >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
  AND data_inicio <= data_referencia
```

**Por que 340 dias?**
- 299 dias (gestação máxima)
- \+ 42 dias (puerpério)
- \+ margem de segurança
- = **341 dias**

**O que captura**:
- Gestações que **começaram** nos últimos 340 dias
- Podem estar em qualquer fase: Gestação, Puerpério ou Encerrada

**O que NÃO captura**:
- Gestações que começaram há mais de 340 dias (já ultrapassaram puerpério)

---

### **Passo 11: Filtrar Apenas Gestação e Puerpério** (linhas 286-290)

```sql
filtrado AS (...)
```

**O que faz**: Remove gestações já "Encerradas"

**Resultado**: Apenas gestações **ativas** (Gestação) ou **recentes** (Puerpério) na `data_referencia`.

---

### **Passo 12: Identificar Equipe de Saúde** (linhas 295-329)

```sql
unnested_equipes AS (...)
equipe_durante_gestacao AS (...)
equipe_durante_final AS (...)
```

**O que faz**: Descobre qual equipe de saúde estava responsável pela paciente durante a gestação

**Lógica**:
1. Lista todas as equipes que a paciente teve
2. Filtra equipes ativas **até** a data de fim da gestação
3. Seleciona a equipe mais recente (última atualização)

**Resultado**:
- Nome da equipe
- Nome da clínica/unidade de saúde

---

### **Passo 13: Resultado Final** (linhas 334-355)

```sql
SELECT
    data_referencia AS data_snapshot,
    filtrado.id_gestacao,
    filtrado.id_paciente,
    filtrado.nome,
    filtrado.idade_gestante,
    filtrado.data_inicio,
    filtrado.data_fim,
    filtrado.fase_atual,
    filtrado.trimestre_atual_gestacao,
    filtrado.ig_atual_semanas,
    edf.equipe_nome,
    edf.clinica_nome
FROM filtrado
LEFT JOIN equipe_durante_final edf ON filtrado.id_gestacao = edf.id_gestacao;
```

**O que retorna**: Uma linha para cada gestação **ativa ou em puerpério** na `data_referencia`

---

## 📊 Exemplo Completo

### Cenário
```
data_referencia: 2025-07-01

Paciente: Maria Silva (ID: 12345)
Eventos de CID Z34:
- 2025-01-10 (1x)
- 2025-01-15 (8x) ← MODA
- 2025-02-12 (2x)
- 2025-03-20 (1x)
```

### Processamento

**1. Cálculo da DUM**:
- MODA = `2025-01-15` (aparece 8 vezes)
- `data_inicio = 2025-01-15`

**2. Data de fim**:
- Nenhum CID RESOLVIDO encontrado
- `data_fim = NULL` (gestação ainda ativa)

**3. Classificação na data_referencia (2025-07-01)**:
- `data_inicio (01/15) <= data_referencia (07/01)` ✅
- `data_fim é NULL` ✅
- `299 dias não excedidos` ✅ (167 dias decorridos)
- **Fase: Gestação**

**4. Trimestre e IG**:
- Semanas decorridas: 24 semanas
- **Trimestre: 2º trimestre** (14-27 semanas)
- **IG: 24 semanas**

**5. Filtro Temporal**:
- `data_inicio (01/15) >= data_referencia - 340 dias (08/26/2024)` ✅
- **Incluída** no resultado

**6. Resultado Final**:
```
data_snapshot: 2025-07-01
id_gestacao: 12345-1
nome: Maria Silva
data_inicio: 2025-01-15
data_fim: NULL
fase_atual: Gestação
trimestre: 2º trimestre
ig_atual_semanas: 24
equipe_nome: Equipe ESF Centro
clinica_nome: UBS Centro
```

---

## 🎯 Casos de Uso

### **Uso 1: Dashboard de Gestações Ativas**
Execute para `data_referencia = CURRENT_DATE()` para obter snapshot atual.

### **Uso 2: Análise Temporal**
Execute para múltiplas datas (ex: todo dia 1º do mês) para construir série histórica.

### **Uso 3: Indicadores de Cobertura**
- Quantas gestantes ativas por equipe?
- Quantas estão no 1º trimestre (ideal para início do pré-natal)?

---

## ⚠️ Considerações Importantes

### **Limitações**

1. **Dependência de Registro de CID**:
   - Se a paciente não teve CID registrado, não será identificada
   - CIDs registrados incorretamente afetam a DUM

2. **Auto-encerramento em 299 dias**:
   - Gestações sem registro de parto são forçadamente encerradas
   - Pode gerar falsos negativos se houver atraso no registro

3. **Janela de 60 dias para Agrupamento**:
   - Se houver >60 dias entre consultas da MESMA gestação, pode criar gestações duplicadas
   - Trade-off: janela maior pode mesclar gestações diferentes

### **Qualidade dos Dados**

Para resultados confiáveis, é essencial:
- ✅ Registro consistente de CIDs de gestação
- ✅ DUM atualizada após ultrassom
- ✅ Marcação de CID como RESOLVIDO após parto/aborto
- ✅ Registro de parto em até 299 dias

---

## 🔄 Fluxo Visual Simplificado

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Buscar TODOS os CIDs de gestação (sem filtro temporal)  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Agrupar eventos da mesma gestação (janela 60 dias)      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Calcular DUM por MODA (data mais frequente)             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Identificar data de fim (CID RESOLVIDO)                 │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Auto-encerrar se >299 dias sem fim                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Classificar fase (Gestação/Puerpério/Encerrada)         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. ✅ FILTRAR por data_inicio (últimos 340 dias)           │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. Manter apenas Gestação e Puerpério                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 9. Adicionar equipe de saúde                                │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
                RESULTADO FINAL
```

---

## 📖 Glossário

| Termo | Significado |
|-------|-------------|
| **DUM** | Data da Última Menstruação - marca início da gestação |
| **MODA** | Valor mais frequente em um conjunto de dados |
| **IG** | Idade Gestacional - quantas semanas desde o início |
| **DPP** | Data Provável do Parto - 40 semanas após DUM |
| **CID** | Classificação Internacional de Doenças (código de diagnóstico) |
| **Puerpério** | Período de 42 dias após o parto (resguardo) |
| **Auto-encerramento** | Gestação sem fim registrado é encerrada após 299 dias |

---

## ✅ Resumo da Correção

### **Antes (❌ Incorreto)**
```sql
WHERE c.data_diagnostico >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
```
- Filtrava **eventos de CID** por data
- **Perdia** gestações antigas com CIDs antigos mas ainda ativas

### **Depois (✅ Correto)**
```sql
WHERE data_inicio >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
```
- Filtra **gestações** por data de início (DUM)
- **Captura** todas as gestações ativas corretamente

---

## 💡 Dica de Uso

Para testar a query com diferentes datas:

```sql
-- Altere apenas esta linha
DECLARE data_referencia DATE DEFAULT DATE('2025-07-01');
```

Execute a query completa no BigQuery para obter o snapshot daquela data específica.
