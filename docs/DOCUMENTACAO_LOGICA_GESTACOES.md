# 📚 Documentação Lógica - Histórico de Gestações

## 🎯 Visão Geral do Sistema

Este documento explica a lógica completa do sistema de rastreamento de gestações em pseudocódigo didático.

### Objetivo Principal
Criar um **snapshot histórico** das gestações (ativas e em puerpério) em uma data específica, permitindo análise temporal.

### Fluxo Macro do Sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUXO DE PROCESSAMENTO                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. COLETA DE DADOS                                            │
│     ↓                                                           │
│  2. IDENTIFICAÇÃO DE EVENTOS                                   │
│     ↓                                                           │
│  3. DEDUPLICAÇÃO E AGRUPAMENTO                                 │
│     ↓                                                           │
│  4. IDENTIFICAÇÃO DE DESFECHOS                                 │
│     ↓                                                           │
│  5. MONTAGEM DAS GESTAÇÕES                                     │
│     ↓                                                           │
│  6. CLASSIFICAÇÃO DE FASES                                     │
│     ↓                                                           │
│  7. ENRIQUECIMENTO COM EQUIPES                                 │
│     ↓                                                           │
│  8. GERAÇÃO DO SNAPSHOT FINAL                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Detalhamento das CTEs (Common Table Expressions)

### 1️⃣ CTE: `cadastro_paciente`

**Objetivo:** Buscar informações básicas das pacientes e calcular idade na data de referência.

**Pseudocódigo:**
```
PARA CADA paciente NO sistema:
    idade_gestante = data_referencia - data_nascimento (em anos)

    RETORNAR:
        - id_paciente
        - nome
        - idade_gestante
FIM
```

**Diagrama:**
```
┌──────────────┐
│  Paciente    │
│              │
│  Maria Silva │  Nasc: 1995-03-20
│              │  Ref:  2024-01-01
└──────┬───────┘
       │
       │ CALCULA IDADE
       │ 2024 - 1995 = 29 anos
       ↓
┌──────────────┐
│ Idade: 29    │
└──────────────┘
```

---

### 2️⃣ CTE: `eventos_brutos`

**Objetivo:** Buscar TODOS os eventos de gestação (CIDs Z321, Z34*, Z35*) dentro de uma janela temporal.

**Janela Temporal:**
```
┌────────────────────────────────────────────────────┐
│  [data_referencia - 340 dias] até [data_referencia] │
│                                                    │
│  ◄────────── 340 dias ──────────►                 │
│  │                              │                  │
│  └─ Início da janela    data_referencia ─┘       │
│                                                    │
│  Por quê 340 dias?                                │
│  • 299 dias (gestação máxima)                     │
│  • + 42 dias (puerpério)                          │
│  • = 341 dias de histórico possível               │
└────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA episódio_assistencial NO sistema:
    PARA CADA condição NO episódio:
        SE condição.cid EM ['Z321', 'Z34%', 'Z35%']:
            SE condição.situacao EM ['ATIVO', 'RESOLVIDO']:
                SE condição.data_diagnostico ENTRE [ref-340, ref]:

                    tipo_evento = 'gestacao'

                    RETORNAR:
                        - id_hci
                        - id_paciente
                        - cpf, nome, idade_gestante
                        - cid
                        - situacao_cid (ATIVO ou RESOLVIDO)
                        - data_evento
                        - tipo_evento
FIM
```

**Exemplo Visual:**
```
Timeline da Janela:
═══════════════════════════════════════════════════
2023-02-25        2023-08-01         2024-01-01
    │                 │                  │
    │◄── 340 dias ───►│                  │
    │                 │                  │
    └─ INCLUI ────────┴─ INCLUI ─────────┘
                                    data_referencia
```

---

### 3️⃣ CTE: `inicios_brutos`

**Objetivo:** Filtrar apenas os eventos de INÍCIO de gestação (CIDs ATIVOS).

**Pseudocódigo:**
```
PARA CADA evento EM eventos_brutos:
    SE evento.tipo_evento = 'gestacao':
        SE evento.situacao_cid = 'ATIVO':
            RETORNAR evento
FIM
```

**Diagrama de Filtro:**
```
┌─────────────────────────────────────┐
│     eventos_brutos (TODOS)          │
│                                     │
│  • Z321 ATIVO     ✓ (mantém)       │
│  • Z34  ATIVO     ✓ (mantém)       │
│  • Z35  RESOLVIDO ✗ (remove)       │
│  • Z34  RESOLVIDO ✗ (remove)       │
└─────────────────┬───────────────────┘
                  │
                  │ FILTRO: ATIVO
                  ↓
┌─────────────────────────────────────┐
│     inicios_brutos                  │
│  (Apenas ATIVO = Gestações ativas)  │
└─────────────────────────────────────┘
```

---

### 4️⃣ CTE: `finais`

**Objetivo:** Filtrar eventos de FIM de gestação (CIDs RESOLVIDOS).

**Pseudocódigo:**
```
PARA CADA evento EM eventos_brutos:
    SE evento.tipo_evento = 'gestacao':
        SE evento.situacao_cid = 'RESOLVIDO':
            RETORNAR evento
FIM
```

**Diagrama:**
```
RESOLVIDO = Marcação administrativa de encerramento
             (menos preciso que CIDs O00-O99)

┌─────────────────────────────────────┐
│     eventos_brutos                  │
│                                     │
│  • Z321 RESOLVIDO ✓ (mantém)       │
│  • Z34  RESOLVIDO ✓ (mantém)       │
└─────────────────┬───────────────────┘
                  │
                  ↓
┌─────────────────────────────────────┐
│          finais                     │
│  (Gestações com marcação encerrada) │
└─────────────────────────────────────┘
```

---

### 5️⃣ CTE: `inicios_com_grupo`

**Objetivo:** Detectar quando eventos próximos são da MESMA gestação ou gestações DIFERENTES.

**Regra de Agrupamento:**
- Eventos com **menos de 60 dias** de diferença = **mesma gestação**
- Eventos com **60+ dias** de diferença = **nova gestação**

**Pseudocódigo:**
```
PARA CADA evento EM inicios_brutos (ORDENADO por id_paciente, data_evento):

    data_anterior = data do evento anterior desta paciente

    SE data_anterior NÃO EXISTE:
        nova_ocorrencia_flag = 1  // Primeira gestação da paciente

    SENÃO SE (data_evento - data_anterior) >= 60 dias:
        nova_ocorrencia_flag = 1  // Nova gestação

    SENÃO:
        nova_ocorrencia_flag = 0  // Mesma gestação

    RETORNAR evento + nova_ocorrencia_flag
FIM
```

**Exemplo Visual:**
```
Paciente: Maria Silva
═════════════════════════════════════════════════════

Evento 1: 2023-03-01  →  nova_ocorrencia_flag = 1 (primeira)
              │
              │ ◄── 45 dias ──►
              │
Evento 2: 2023-04-15  →  nova_ocorrencia_flag = 0 (mesma gestação)
              │
              │ ◄── 90 dias ──►
              │
Evento 3: 2023-07-14  →  nova_ocorrencia_flag = 1 (NOVA gestação)
              │
              │ ◄── 30 dias ──►
              │
Evento 4: 2023-08-13  →  nova_ocorrencia_flag = 0 (mesma gestação)

═════════════════════════════════════════════════════

Resultado:
  Gestação 1: Eventos 1 e 2 (agrupados)
  Gestação 2: Eventos 3 e 4 (agrupados)
```

---

### 6️⃣ CTE: `grupos_inicios`

**Objetivo:** Atribuir um ID de grupo para cada gestação.

**Pseudocódigo:**
```
PARA CADA evento EM inicios_com_grupo (ORDENADO por id_paciente, data_evento):

    grupo_id = SOMA_ACUMULADA(nova_ocorrencia_flag)

    RETORNAR evento + grupo_id
FIM
```

**Exemplo Visual:**
```
Paciente: Maria Silva
════════════════════════════════════════════════════

Data         nova_flag   SOMA_ACUM   grupo_id
────────────────────────────────────────────────────
2023-03-01      1           1           1
2023-04-15      0           1           1  ← mesma gestação
2023-07-14      1           2           2  ← nova gestação
2023-08-13      0           2           2  ← mesma gestação

════════════════════════════════════════════════════

Resultado:
  • Grupo 1 = Gestação iniciada em 2023-03-01
  • Grupo 2 = Gestação iniciada em 2023-07-14
```

---

### 7️⃣ CTE: `inicios_deduplicados`

**Objetivo:** Para cada grupo, pegar apenas a **data mais recente** como data oficial de início.

**Pseudocódigo:**
```
PARA CADA grupo (id_paciente + grupo_id):

    eventos_do_grupo = TODOS os eventos deste grupo

    evento_escolhido = evento com data_evento MAIS RECENTE

    RETORNAR evento_escolhido
FIM
```

**Exemplo Visual:**
```
ANTES (grupos_inicios):
┌──────────────────────────────────────┐
│ Grupo 1 para Maria Silva             │
│                                      │
│  2023-03-01  CID: Z321              │
│  2023-03-05  CID: Z34               │
│  2023-04-15  CID: Z35   ← MAIS RECENTE│
└──────────────────────────────────────┘

DEPOIS (inicios_deduplicados):
┌──────────────────────────────────────┐
│ Grupo 1 para Maria Silva             │
│                                      │
│  2023-04-15  CID: Z35   ✓           │
│  (Data mais recente escolhida)       │
└──────────────────────────────────────┘

Por quê a mais recente?
→ Informação mais atualizada do prontuário
→ Ajustes e correções tendem a ser mais tardios
```

---

### 8️⃣ CTE: `eventos_desfecho`

**Objetivo:** Buscar eventos CONCRETOS de desfecho obstétrico (CIDs O00-O99).

**Tipos de Desfecho:**
```
┌─────────────────────────────────────────────────┐
│         CLASSIFICAÇÃO DE DESFECHOS              │
├─────────────────────────────────────────────────┤
│                                                 │
│  O00-O08  →  ABORTO                            │
│  O80-O84  →  PARTO                             │
│  O85-O92  →  PUERPÉRIO CONFIRMADO              │
│  Outros   →  OUTRO DESFECHO                    │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA episódio_assistencial NO sistema:
    PARA CADA condição NO episódio:

        SE condição.cid ENTRE 'O00' E 'O99':
            SE condição.data ENTRE [ref-365, ref]:

                // Classificar tipo de desfecho
                SE cid ENTRE 'O00' E 'O08':
                    tipo_desfecho = 'aborto'

                SENÃO SE cid ENTRE 'O80' E 'O84':
                    tipo_desfecho = 'parto'

                SENÃO SE cid ENTRE 'O85' E 'O92':
                    tipo_desfecho = 'puerperio_confirmado'

                SENÃO:
                    tipo_desfecho = 'outro_desfecho'

                RETORNAR:
                    - id_paciente
                    - data_desfecho
                    - cid_desfecho
                    - tipo_desfecho
FIM
```

**Exemplo Visual:**
```
Timeline de Busca de Desfechos:
═══════════════════════════════════════════════════
2023-01-01                              2024-01-01
    │                                        │
    │◄────────── 365 dias ──────────────────►│
    │                                        │
    └─ Início da busca          data_referencia ─┘

Exemplos de CIDs:
  O03 → aborto espontâneo
  O80 → parto normal
  O86 → complicação puerperal
```

---

### 9️⃣ CTE: `primeiro_desfecho`

**Objetivo:** Associar cada gestação ao seu PRIMEIRO desfecho (se houver).

**Regras de Matching:**
1. Desfecho deve ser da MESMA paciente
2. Desfecho deve ocorrer DEPOIS do início da gestação
3. Desfecho deve ocorrer em ATÉ 320 dias (gestação máxima)
4. Se múltiplos desfechos, pegar o PRIMEIRO cronologicamente

**Pseudocódigo:**
```
PARA CADA inicio EM inicios_deduplicados:

    desfechos_possiveis = BUSCAR eventos_desfecho ONDE:
        - mesma id_paciente
        - data_desfecho > data_inicio
        - (data_desfecho - data_inicio) <= 320 dias

    SE desfechos_possiveis EXISTE:
        primeiro = desfecho com MENOR data_desfecho

        RETORNAR:
            - id_hci (do início)
            - id_paciente
            - data_inicio
            - data_fim = primeiro.data_desfecho
            - tipo_desfecho = primeiro.tipo_desfecho
            - cid_desfecho = primeiro.cid_desfecho

    SENÃO:
        RETORNAR:
            - id_hci, id_paciente, data_inicio
            - data_fim = NULL (sem desfecho registrado)
FIM
```

**Exemplo Visual:**
```
Gestação de Maria Silva:
═════════════════════════════════════════════════════

Início: 2023-03-01
   │
   │  ◄──── Busca desfechos até 320 dias após ────►
   │
   │  2023-10-15: O80 (parto)        ← PRIMEIRO ✓
   │  2023-10-20: O86 (puerpério)    ← ignora
   │  2023-11-25: O90 (puerpério)    ← ignora
   │
   └─ data_fim = 2023-10-15 (primeiro desfecho)
      tipo_desfecho = 'parto'
      cid_desfecho = 'O80'

═════════════════════════════════════════════════════

Por quê 320 dias?
→ Gestação máxima: ~294 dias (42 semanas)
→ Margem de segurança para dados
```

---

### 🔟 CTE: `gestacoes_unicas`

**Objetivo:** Criar registros únicos de gestações com numeração sequencial.

**Pseudocódigo:**
```
PARA CADA registro EM primeiro_desfecho:

    // Juntar com inicios_deduplicados para recuperar todas as informações
    info_completa = JOIN com inicios_deduplicados

    // Numerar gestações da paciente
    numero_gestacao = ROW_NUMBER() PARTICIONADO por id_paciente
                      ORDENADO por data_inicio

    // Criar ID único da gestação
    id_gestacao = id_paciente + '-' + numero_gestacao

    RETORNAR:
        - id_hci
        - id_paciente, cpf, nome, idade_gestante
        - data_inicio, data_fim
        - tipo_desfecho, cid_desfecho
        - numero_gestacao
        - id_gestacao
FIM
```

**Exemplo Visual:**
```
Paciente: Maria Silva (ID: 12345)
═════════════════════════════════════════════════════

Gestação 1:
  data_inicio: 2022-05-10
  data_fim: 2023-01-15
  numero_gestacao: 1
  id_gestacao: "12345-1"
  tipo_desfecho: "parto"

Gestação 2:
  data_inicio: 2023-08-20
  data_fim: NULL (em andamento)
  numero_gestacao: 2
  id_gestacao: "12345-2"
  tipo_desfecho: NULL

═════════════════════════════════════════════════════

Numeração sempre respeita ordem cronológica!
```

---

### 1️⃣1️⃣ CTE: `gestacoes_com_status`

**Objetivo:** Calcular data de fim efetiva (considerando auto-encerramento) e DPP.

**Regras de Auto-Encerramento:**
- Gestação SEM desfecho registrado é auto-encerrada após **294 dias** (42 semanas)

**Pseudocódigo:**
```
PARA CADA gestacao EM gestacoes_unicas:

    // Data de fim efetiva
    SE gestacao.data_fim EXISTE:
        data_fim_efetiva = gestacao.data_fim

    SENÃO SE (data_inicio + 294 dias) <= data_referencia:
        data_fim_efetiva = data_inicio + 294 dias  // AUTO-ENCERRADA

    SENÃO:
        data_fim_efetiva = NULL  // Ainda em andamento

    // Data Provável do Parto (DPP)
    dpp = data_inicio + 40 semanas (280 dias)

    RETORNAR gestacao + data_fim_efetiva + dpp
FIM
```

**Exemplo Visual:**
```
Cenário 1: Com desfecho registrado
═════════════════════════════════════════════════════
Início: 2023-03-01
Fim: 2023-10-15 (parto registrado)
data_fim_efetiva = 2023-10-15  ✓
dpp = 2023-03-01 + 280 dias = 2023-12-06

Cenário 2: Sem desfecho, passou 294 dias
═════════════════════════════════════════════════════
Início: 2023-01-01
data_referencia: 2024-01-01
Passou 365 dias > 294 dias
data_fim_efetiva = 2023-01-01 + 294 dias = 2023-10-22 ✓
(AUTO-ENCERRADA)

Cenário 3: Sem desfecho, ainda em andamento
═════════════════════════════════════════════════════
Início: 2023-11-01
data_referencia: 2024-01-01
Passou 61 dias < 294 dias
data_fim_efetiva = NULL  ✓
(GESTAÇÃO ATIVA)
```

---

### 1️⃣2️⃣ CTE: `gestacoes_com_fase`

**Objetivo:** Classificar a fase da gestação na data de referência.

**Fases Possíveis:**
```
┌─────────────────────────────────────────────────┐
│            CLASSIFICAÇÃO DE FASES               │
├─────────────────────────────────────────────────┤
│                                                 │
│  GESTAÇÃO   → Em curso na data de referência   │
│  PUERPÉRIO  → Até 42 dias após o parto         │
│  ENCERRADA  → Mais de 42 dias após o parto     │
│                                                 │
└─────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA gestacao EM gestacoes_com_status:

    // ═══════════════════════════════════════════
    // REGRA 1: GESTAÇÃO (em curso)
    // ═══════════════════════════════════════════
    SE data_inicio <= data_referencia:
        SE (data_fim é NULL OU data_fim >= data_referencia):
            SE (data_inicio + 294 dias) >= data_referencia:
                fase_atual = 'Gestação'

    // ═══════════════════════════════════════════
    // REGRA 2: PUERPÉRIO (até 42 dias após parto)
    // ═══════════════════════════════════════════
    SE data_fim EXISTE:
        SE data_fim < data_referencia:
            SE (data_fim + 42 dias) >= data_referencia:
                fase_atual = 'Puerpério'

    // ═══════════════════════════════════════════
    // REGRA 3: ENCERRADA (após puerpério)
    // ═══════════════════════════════════════════
    SE data_fim EXISTE:
        SE (data_fim + 42 dias) < data_referencia:
            fase_atual = 'Encerrada'

    // Auto-encerrada (sem desfecho mas passou 294 dias)
    SE data_fim é NULL:
        SE (data_inicio + 294 dias) < data_referencia:
            fase_atual = 'Encerrada'

    // ═══════════════════════════════════════════
    // CÁLCULOS ADICIONAIS
    // ═══════════════════════════════════════════

    // Trimestre atual
    semanas_gestacao = (data_referencia - data_inicio) em semanas

    SE semanas_gestacao <= 13:
        trimestre = '1º trimestre'
    SENÃO SE semanas_gestacao ENTRE 14 E 27:
        trimestre = '2º trimestre'
    SENÃO SE semanas_gestacao >= 28:
        trimestre = '3º trimestre'

    // Idade gestacional
    ig_atual_semanas = semanas_gestacao

    SE data_fim EXISTE:
        ig_final_semanas = (data_fim - data_inicio) em semanas

    RETORNAR gestacao + fase_atual + trimestre + ig_atual + ig_final
FIM
```

**Exemplo Visual - Timeline de Fases:**
```
Gestação de Maria Silva
═════════════════════════════════════════════════════

Início                Fim              +42 dias
  │                    │                   │
  ├────────────────────┼───────────────────┤
  │                    │                   │
2023-03-01        2023-10-15          2023-11-26
  │                    │                   │
  │◄── GESTAÇÃO ──────►│◄── PUERPÉRIO ────►│◄─ ENCERRADA
  │                    │                   │
  │                    │                   │

Classificação na data_referencia (2024-01-01):
  • 2024-01-01 > 2023-11-26
  • fase_atual = 'Encerrada' ✓

═════════════════════════════════════════════════════

Exemplo de Gestação Ativa:
═════════════════════════════════════════════════════

Início                                   data_ref
  │                                         │
2023-11-01                              2024-01-01
  │                                         │
  │◄────────── GESTAÇÃO (61 dias) ─────────►│
  │                                         │

Classificação:
  • 61 dias < 294 dias (não auto-encerrada)
  • sem data_fim
  • fase_atual = 'Gestação' ✓
  • ig_atual_semanas = 8
  • trimestre = '1º trimestre'
```

---

### 1️⃣3️⃣ CTE: `filtrado`

**Objetivo:** Excluir gestações encerradas, mantendo apenas ativas e em puerpério.

**Pseudocódigo:**
```
PARA CADA gestacao EM gestacoes_com_fase:

    SE gestacao.fase_atual EM ['Gestação', 'Puerpério']:
        RETORNAR gestacao

    // Gestações 'Encerrada' são descartadas
FIM
```

**Diagrama de Filtro:**
```
┌─────────────────────────────────────────┐
│    gestacoes_com_fase (TODAS)           │
│                                         │
│  Gestação 1: fase = 'Gestação'      ✓  │
│  Gestação 2: fase = 'Puerpério'     ✓  │
│  Gestação 3: fase = 'Encerrada'     ✗  │
│  Gestação 4: fase = 'Gestação'      ✓  │
│  Gestação 5: fase = 'Encerrada'     ✗  │
└─────────────────┬───────────────────────┘
                  │
                  │ FILTRO: IN ('Gestação', 'Puerpério')
                  ↓
┌─────────────────────────────────────────┐
│           filtrado                      │
│  (Apenas gestações ativas/puerpério)    │
│                                         │
│  • 3 gestações mantidas                 │
│  • 2 gestações removidas                │
└─────────────────────────────────────────┘

Por quê excluir 'Encerrada'?
→ Foco em gestações que requerem acompanhamento
→ Snapshot apenas de casos ativos
```

---

### 1️⃣4️⃣ CTE: `unnested_equipes`

**Objetivo:** "Desempacotar" o array de equipes de saúde dos pacientes.

**Pseudocódigo:**
```
PARA CADA paciente NO sistema:
    PARA CADA equipe NO array equipe_saude_familia:

        RETORNAR:
            - id_paciente
            - datahora_ultima_atualizacao (da equipe)
            - equipe_nome
            - clinica_nome
FIM
```

**Exemplo Visual:**
```
ANTES (array aninhado):
┌──────────────────────────────────────────────────┐
│ Paciente: Maria Silva (ID: 12345)                │
│                                                  │
│ equipe_saude_familia: [                          │
│   {                                              │
│     nome: "Equipe A",                            │
│     clinica: "CF Centro",                        │
│     datahora_atualizacao: "2023-01-15"           │
│   },                                             │
│   {                                              │
│     nome: "Equipe B",                            │
│     clinica: "CF Norte",                         │
│     datahora_atualizacao: "2023-06-20"           │
│   }                                              │
│ ]                                                │
└──────────────────────────────────────────────────┘

DEPOIS (unnested_equipes - linhas separadas):
┌──────────────────────────────────────────────────┐
│ id_paciente | equipe_nome | clinica_nome | data  │
├──────────────────────────────────────────────────┤
│ 12345       | Equipe A    | CF Centro    | 01/15 │
│ 12345       | Equipe B    | CF Norte     | 06/20 │
└──────────────────────────────────────────────────┘

Agora podemos filtrar e ordenar facilmente!
```

---

### 1️⃣5️⃣ CTE: `equipe_durante_gestacao`

**Objetivo:** Encontrar a equipe MAIS RECENTE que atendeu cada gestação.

**Regras:**
1. Equipe deve ter sido atualizada ANTES ou NO MÁXIMO na data de fim da gestação
2. Entre as equipes válidas, pegar a MAIS RECENTE

**Pseudocódigo:**
```
PARA CADA gestacao EM filtrado:

    equipes_possiveis = BUSCAR unnested_equipes ONDE:
        - mesma id_paciente
        - data_atualizacao_equipe <= data_fim_efetiva (ou data_referencia se sem fim)

    SE equipes_possiveis EXISTE:
        // Ordenar por data de atualização (mais recente primeiro)
        // Numerar com ROW_NUMBER
        ranking = ordenar equipes_possiveis por datahora DESC

        RETORNAR:
            - id_gestacao
            - equipe_nome
            - clinica_nome
            - rn (ranking: 1 = mais recente)
FIM
```

**Exemplo Visual:**
```
Gestação de Maria Silva:
═════════════════════════════════════════════════════

data_inicio: 2023-03-01
data_fim_efetiva: 2023-10-15
data_referencia: 2024-01-01

Equipes do histórico:
  1. Equipe A (atualizada em 2022-12-10) ← ANTES da gestação ✓
  2. Equipe B (atualizada em 2023-05-20) ← DURANTE gestação ✓
  3. Equipe C (atualizada em 2023-09-15) ← DURANTE gestação ✓
  4. Equipe D (atualizada em 2023-11-01) ← DEPOIS da gestação ✗

Equipes válidas (antes/durante):
  • 2023-09-15: Equipe C  ← rn = 1 (ESCOLHIDA) ✓
  • 2023-05-20: Equipe B  ← rn = 2
  • 2022-12-10: Equipe A  ← rn = 3

Equipe final: Equipe C (mais recente durante a gestação)
```

---

### 1️⃣6️⃣ CTE: `equipe_durante_final`

**Objetivo:** Pegar apenas a equipe de ranking 1 (mais recente).

**Pseudocódigo:**
```
PARA CADA registro EM equipe_durante_gestacao:

    SE registro.rn = 1:
        RETORNAR:
            - id_gestacao
            - equipe_nome
            - clinica_nome
FIM
```

**Diagrama:**
```
┌─────────────────────────────────────────┐
│    equipe_durante_gestacao              │
│                                         │
│  Gestação 1: Equipe C (rn=1)        ✓  │
│  Gestação 1: Equipe B (rn=2)        ✗  │
│  Gestação 1: Equipe A (rn=3)        ✗  │
│  Gestação 2: Equipe X (rn=1)        ✓  │
│  Gestação 2: Equipe Y (rn=2)        ✗  │
└─────────────────┬───────────────────────┘
                  │
                  │ FILTRO: rn = 1
                  ↓
┌─────────────────────────────────────────┐
│      equipe_durante_final               │
│  (Uma equipe por gestação)              │
│                                         │
│  Gestação 1: Equipe C                   │
│  Gestação 2: Equipe X                   │
└─────────────────────────────────────────┘
```

---

## 🎯 SELECT FINAL - Montagem do Snapshot

**Objetivo:** Combinar todas as informações em um snapshot histórico.

**Pseudocódigo:**
```
PARA CADA gestacao EM filtrado:

    // Buscar equipe correspondente
    equipe = BUSCAR equipe_durante_final ONDE id_gestacao = gestacao.id_gestacao

    RETORNAR:
        // Metadados do snapshot
        - data_snapshot = data_referencia

        // Identificadores
        - id_hci
        - id_gestacao
        - id_paciente
        - cpf

        // Dados da gestante
        - nome
        - idade_gestante
        - numero_gestacao

        // Datas da gestação
        - data_inicio
        - data_fim
        - data_fim_efetiva
        - dpp

        // Desfecho
        - tipo_desfecho
        - cid_desfecho

        // Classificação
        - fase_atual
        - trimestre_atual_gestacao
        - ig_atual_semanas
        - ig_final_semanas

        // Equipe de saúde
        - equipe_nome
        - clinica_nome
FIM
```

**Estrutura Final:**
```
┌───────────────────────────────────────────────────┐
│              SNAPSHOT DE GESTAÇÕES                │
│              data_snapshot: 2024-01-01            │
├───────────────────────────────────────────────────┤
│                                                   │
│  Gestação 12345-1 (Maria Silva)                  │
│  ├─ Fase: Puerpério                              │
│  ├─ Início: 2023-03-01                           │
│  ├─ Fim: 2023-10-15 (parto)                      │
│  ├─ IG: 32 semanas                               │
│  └─ Equipe: Equipe C / CF Centro                 │
│                                                   │
│  Gestação 67890-2 (Ana Costa)                    │
│  ├─ Fase: Gestação                               │
│  ├─ Início: 2023-11-01                           │
│  ├─ Fim: NULL (em andamento)                     │
│  ├─ IG: 8 semanas (1º trimestre)                 │
│  └─ Equipe: Equipe X / CF Sul                    │
│                                                   │
└───────────────────────────────────────────────────┘
```

---

## 📊 Resumo do Fluxo Completo

```
┌────────────────────────────────────────────────────────────┐
│                    PIPELINE COMPLETO                       │
└────────────────────────────────────────────────────────────┘

1. COLETA DE DADOS BASE
   └─► cadastro_paciente: Informações das gestantes

2. IDENTIFICAÇÃO DE EVENTOS
   └─► eventos_brutos: CIDs de gestação (janela 340 dias)
       ├─► inicios_brutos: Apenas CIDs ATIVOS
       └─► finais: Apenas CIDs RESOLVIDOS

3. DEDUPLICAÇÃO E AGRUPAMENTO
   └─► inicios_com_grupo: Detecta eventos da mesma gestação
       └─► grupos_inicios: Atribui IDs de grupo
           └─► inicios_deduplicados: Uma data por gestação

4. IDENTIFICAÇÃO DE DESFECHOS
   └─► eventos_desfecho: CIDs O00-O99 (aborto, parto, puerpério)
       └─► primeiro_desfecho: Associa desfechos às gestações

5. MONTAGEM DAS GESTAÇÕES
   └─► gestacoes_unicas: Registros únicos com numeração
       └─► gestacoes_com_status: Calcula datas efetivas e DPP

6. CLASSIFICAÇÃO DE FASES
   └─► gestacoes_com_fase: Classifica em Gestação/Puerpério/Encerrada
       └─► filtrado: Remove gestações encerradas

7. ENRIQUECIMENTO COM EQUIPES
   └─► unnested_equipes: Desempacota arrays de equipes
       └─► equipe_durante_gestacao: Ranqueia equipes por data
           └─► equipe_durante_final: Seleciona equipe mais recente

8. GERAÇÃO DO SNAPSHOT
   └─► SELECT FINAL: Combina tudo em snapshot histórico
```

---

## 🔍 Conceitos-Chave Explicados

### Janela Temporal
```
Por quê 340 dias?
═════════════════════════════════════════════════════

Gestação máxima: 299 dias (~42 semanas)
Puerpério:        42 dias
                ─────
Total:            341 dias

Usamos 340 dias para ter margem de segurança e
capturar todas as gestações que possam estar em
andamento ou puerpério na data de referência.
```

### Auto-Encerramento
```
Por quê 294 dias?
═════════════════════════════════════════════════════

294 dias = 42 semanas = limite máximo de gestação

Se uma gestação não tem desfecho registrado e já
passou desse prazo, assumimos que foi encerrada
(parto não registrado ou perda de acompanhamento).
```

### Deduplicação por Data Mais Recente
```
Por quê usar a data MAIS RECENTE do grupo?
═════════════════════════════════════════════════════

Prontuários frequentemente têm:
  • Registros retroativos
  • Correções de data
  • Atualizações de informação

A data mais recente tende a ser a informação
mais correta e atualizada.
```

### Primeiro Desfecho
```
Por quê usar o PRIMEIRO desfecho?
═════════════════════════════════════════════════════

Após o parto (primeiro desfecho), pode haver:
  • CIDs de puerpério
  • CIDs de complicações
  • Outros eventos

O PRIMEIRO desfecho marca o FIM da gestação.
Os demais eventos são posteriores ao término.
```

---

## ⚠️ Pontos de Atenção

### 1. Qualidade dos Dados
```
⚠️ CIDs ATIVOS vs RESOLVIDOS
───────────────────────────────────────────────────

A marcação pode estar desatualizada!
  • Gestações finalizadas ainda marcadas como ATIVO
  • Gestações ativas marcadas como RESOLVIDO

Solução: Cruzar com CIDs de desfecho (O00-O99)
```

### 2. Gestações Sem Desfecho
```
⚠️ NULL em data_fim
───────────────────────────────────────────────────

Pode significar:
  ✓ Gestação realmente em andamento
  ✗ Parto não registrado no sistema
  ✗ Perda de acompanhamento

Solução: Auto-encerramento após 294 dias
```

### 3. Múltiplos Episódios Assistenciais
```
⚠️ Múltiplos id_hci para mesma gestação
───────────────────────────────────────────────────

Uma gestação pode ter vários episódios:
  • Consultas diferentes
  • Internações
  • Atendimentos de urgência

Solução: Agrupar por paciente + janela de 60 dias
```

---

## 📈 Exemplo Completo - Caso Real

```
═══════════════════════════════════════════════════════════
CASO: Maria Silva (ID: 12345)
data_referencia: 2024-01-01
═══════════════════════════════════════════════════════════

📋 DADOS CADASTRAIS
───────────────────────────────────────────────────────────
Nome: Maria Silva
Nascimento: 1995-03-20
Idade em 2024-01-01: 28 anos

📅 EVENTOS REGISTRADOS (janela: 2023-02-25 a 2024-01-01)
───────────────────────────────────────────────────────────
2023-03-01: Z321 ATIVO   (id_hci: 1001)
2023-03-15: Z34  ATIVO   (id_hci: 1002)  ← mesmo grupo
2023-04-10: Z35  ATIVO   (id_hci: 1003)  ← mesmo grupo
2023-10-15: O80  (parto normal)
2023-10-20: O86  (complicação puerperal)

🔄 PROCESSAMENTO
───────────────────────────────────────────────────────────

PASSO 1: Agrupar eventos próximos
  Eventos de 2023-03-01 a 2023-04-10: < 60 dias
  → Todos no grupo_id = 1

PASSO 2: Deduplicar grupo
  Data mais recente: 2023-04-10
  → data_inicio oficial = 2023-04-10

PASSO 3: Identificar desfecho
  Primeiro desfecho: 2023-10-15 (O80 - parto)
  → data_fim = 2023-10-15
  → tipo_desfecho = 'parto'

PASSO 4: Calcular status
  data_fim_efetiva = 2023-10-15 (tem desfecho)
  dpp = 2023-04-10 + 280 dias = 2024-01-15
  ig_final = 27 semanas (189 dias de gestação)

PASSO 5: Classificar fase em 2024-01-01
  data_fim: 2023-10-15
  Fim + 42 dias: 2023-11-26
  2024-01-01 > 2023-11-26
  → fase_atual = 'Encerrada'

PASSO 6: Filtrar
  fase = 'Encerrada'
  → REMOVIDO do snapshot ✗

═══════════════════════════════════════════════════════════
RESULTADO FINAL
═══════════════════════════════════════════════════════════

Esta gestação NÃO aparece no snapshot de 2024-01-01
porque está encerrada (fora do puerpério).

Se a data_referencia fosse 2023-11-01:
  → fase_atual = 'Puerpério' ✓
  → INCLUÍDO no snapshot
```

---

## 🎓 Glossário de Termos

| Termo | Significado |
|-------|-------------|
| **CTE** | Common Table Expression - "tabela temporária" na consulta |
| **CID** | Classificação Internacional de Doenças |
| **Z321, Z34, Z35** | CIDs de acompanhamento de gestação |
| **O00-O99** | CIDs de eventos obstétricos concretos |
| **DPP** | Data Provável do Parto (início + 280 dias) |
| **IG** | Idade Gestacional (em semanas) |
| **Puerpério** | Período de 42 dias após o parto |
| **id_hci** | ID do episódio assistencial |
| **id_gestacao** | ID único da gestação (paciente + número) |
| **data_referencia** | Data do snapshot (ponto no tempo) |
| **data_fim_efetiva** | Data de fim real ou auto-encerrada |

---

## 📚 Referências e Observações

### Critérios Clínicos
- **Gestação máxima**: 42 semanas (294 dias)
- **Puerpério**: 6 semanas (42 dias) após o parto
- **Trimestres**: 1º (0-13 sem), 2º (14-27 sem), 3º (28+ sem)
- **DPP**: Data da última menstruação + 280 dias

### Decisões de Design
1. **Data mais recente** para deduplicação (não moda)
2. **Primeiro desfecho** como fim de gestação
3. **Auto-encerramento** aos 294 dias sem desfecho
4. **Janela de 340 dias** para captura histórica
5. **60 dias** como limite para agrupar eventos

---

**Última atualização:** 2024-12-10
**Versão:** 1.0
**Autor:** Sistema de Documentação - Claude Code
