# 📚 Documentação Lógica - Linha do Tempo de Gestações

## 🎯 Visão Geral do Sistema

Este documento explica a lógica completa do sistema de **Linha do Tempo de Gestações**, que consolida TODAS as informações relevantes de cada gestação em uma única linha.

### Objetivo Principal
Criar um **snapshot consolidado** com TODAS as informações clínicas, administrativas e de risco de cada gestação, funcionando como um "prontuário resumido" para análises e monitoramento.

### Características Especiais
- **40+ CTEs** organizadas em blocos temáticos
- **Agregação de múltiplas fontes**: prontuário, SISREG, SER, estoque, etc.
- **Cálculos derivados**: riscos, classificações, flags
- **Uma linha por gestação** com dezenas de colunas

### Fluxo Macro do Sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUXO DE PROCESSAMENTO                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  BLOCO 1: DADOS BASE                                           │
│  ├─ Gestações do snapshot                                      │
│  ├─ Informações de pacientes                                   │
│  └─ Condições clínicas (CIDs)                                  │
│                                                                 │
│  BLOCO 2: RISCOS E CATEGORIAS                                  │
│  ├─ Categorias de risco gestacional                            │
│  ├─ Flags de condições (diabetes, HIV, etc)                    │
│  └─ Análise de fatores de risco                               │
│                                                                 │
│  BLOCO 3: EQUIPES E MUDANÇAS                                   │
│  ├─ Equipe durante gestação                                    │
│  ├─ Equipe anterior                                            │
│  └─ Detecção de mudança de equipe                             │
│                                                                 │
│  BLOCO 4: EVENTOS DE PARTO                                     │
│  ├─ Identificação de partos/abortos                            │
│  └─ Associação com gestação                                    │
│                                                                 │
│  BLOCO 5: AGREGAÇÕES DE CONSULTAS                              │
│  ├─ Total de consultas pré-natal                               │
│  ├─ Última consulta                                            │
│  ├─ Prescrições (ácido fólico, cálcio)                        │
│  └─ Maior pressão arterial                                     │
│                                                                 │
│  BLOCO 6: VISITAS ACS                                          │
│  ├─ Total de visitas                                           │
│  └─ Última visita                                              │
│                                                                 │
│  BLOCO 7: ANÁLISE DE HIPERTENSÃO (NOVO)                       │
│  ├─ Análise de pressão arterial                                │
│  ├─ Prescrições anti-hipertensivos                             │
│  ├─ Encaminhamentos para alto risco                            │
│  ├─ Dispensação de aparelho de PA                              │
│  └─ Classificação de hipertensão gestacional                   │
│                                                                 │
│  BLOCO 8: ANÁLISE DE DIABETES                                  │
│  ├─ Prescrições antidiabéticos                                 │
│  └─ Classificação de diabetes                                  │
│                                                                 │
│  BLOCO 9: UNIDADES DE CADASTRO E ATENDIMENTO                   │
│  ├─ Unidade de vínculo (cadastro)                              │
│  └─ Unidade de atendimento prioritária                         │
│                                                                 │
│  BLOCO 10: CONSOLIDAÇÃO FINAL                                  │
│  └─ União de todas as CTEs em uma única linha                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 BLOCO 1: Dados Base

### 1️⃣ CTE: `filtrado`

**Objetivo:** Carregar gestações do snapshot específico (base de tudo).

**Pseudocódigo:**
```
PARA CADA gestacao EM _gestacoes_historico:
    SE gestacao.data_snapshot = data_referencia:
        RETORNAR gestacao
FIM
```

**Diagrama:**
```
┌──────────────────────────────────────┐
│  _gestacoes_historico                │
│  (Gerado pelo arquivo 1)             │
│                                      │
│  Snapshot 2024-07-01: 1500 gestações │
│  Snapshot 2024-08-01: 1520 gestações │
└──────────────┬───────────────────────┘
               │
               │ FILTRO: data_snapshot
               ↓
┌──────────────────────────────────────┐
│          filtrado                    │
│  (Base para todas as outras CTEs)    │
│                                      │
│  1500 gestações do snapshot          │
└──────────────────────────────────────┘

Esta CTE é a CHAVE PRIMÁRIA de todo o processo!
Todas as outras CTEs fazem JOIN com ela.
```

---

### 2️⃣ CTE: `condicoes_gestantes_raw`

**Objetivo:** Coletar TODAS as condições (CIDs) de TODAS as gestantes, sem filtro de data.

**Pseudocódigo:**
```
PARA CADA episodio EM episodios_assistenciais:
    PARA CADA condicao NO episodio:
        SE condicao.situacao EM ['ATIVO', 'RESOLVIDO']:
            SE condicao.cid NÃO É NULL:
                SE condicao.data_diagnostico NÃO É NULL:

                    data_diag = PARSE_DATE(condicao.data_diagnostico)

                    RETORNAR:
                        - id_paciente
                        - cid
                        - data_diagnostico
                        - situacao
FIM
```

**Exemplo Visual:**
```
Paciente: Maria (ID: 12345)
═══════════════════════════════════════════════════════

Todos os CIDs históricos:
  2020-03-15: I10 (Hipertensão)         ATIVO
  2022-08-20: E11 (Diabetes tipo 2)     ATIVO
  2023-11-10: Z34 (Gestação normal)     ATIVO
  2024-01-20: O14 (Pré-eclâmpsia)       ATIVO
  2024-03-15: O80 (Parto normal)        RESOLVIDO

Todos são incluídos nesta CTE!
(Filtros temporais serão aplicados depois)
```

**Por quê sem filtro temporal?**
```
┌────────────────────────────────────────────────────────┐
│  Diferentes condições têm DIFERENTES janelas:          │
│                                                        │
│  • Diabetes prévio: ANTES do fim da gestação          │
│  • Diabetes gestacional: DURANTE a gestação           │
│  • HIV: ATÉ o fim da gestação                         │
│  • Sífilis: 30 dias ANTES até fim                     │
│  • Tuberculose: 6 MESES antes até fim                 │
│                                                        │
│  Solução: Coletar TUDO, filtrar depois!              │
└────────────────────────────────────────────────────────┘
```

---

### 3️⃣ CTE: `pacientes_info`

**Objetivo:** Consolidar informações básicas de pacientes com deduplicação.

**Pseudocódigo:**
```
// Subquery: Deduplica pacientes
PARA CADA paciente EM tabela_paciente:
    ranking = ROW_NUMBER() PARTICIONADO por id_paciente
              ORDENADO por cpf_particao DESC

// Query principal
PARA CADA paciente_dedup ONDE ranking = 1:

    idade_atual = data_referencia - data_nascimento (em anos)

    // Classificar faixa etária
    SE idade_atual <= 15:
        faixa_etaria = '≤15 anos'
    SENÃO SE idade_atual <= 20:
        faixa_etaria = '16-20 anos'
    SENÃO SE idade_atual <= 30:
        faixa_etaria = '21-30 anos'
    SENÃO SE idade_atual <= 40:
        faixa_etaria = '31-40 anos'
    SENÃO:
        faixa_etaria = '>40 anos'

    RETORNAR:
        - id_paciente, cpf, cns, nome
        - data_nascimento
        - id_cnes (clínica família)
        - idade_atual, faixa_etaria
        - raca
        - obito_indicador, obito_data
FIM
```

**Diagrama de Deduplicação:**
```
ANTES (múltiplos registros):
┌──────────────────────────────────────────────────────┐
│ id_paciente: 12345                                   │
│                                                      │
│  Registro 1: cpf_particao = 202401 (mais recente)   │
│  Registro 2: cpf_particao = 202312                  │
│  Registro 3: cpf_particao = 202305                  │
└──────────────────────────────────────────────────────┘
       │
       │ ROW_NUMBER() ORDER BY cpf_particao DESC
       ↓
┌──────────────────────────────────────────────────────┐
│ Registro 1: rn = 1  ✓ (selecionado)                 │
│ Registro 2: rn = 2  ✗                                │
│ Registro 3: rn = 3  ✗                                │
└──────────────────────────────────────────────────────┘

DEPOIS (1 linha por paciente):
  Usa dados da partição mais recente
```

**Faixas Etárias:**
```
┌────────────────────────────────────────┐
│     CLASSIFICAÇÃO DE IDADE             │
├────────────────────────────────────────┤
│                                        │
│  0-15 anos   →  ≤15 anos  (adolescente)│
│  16-20 anos  →  16-20 anos            │
│  21-30 anos  →  21-30 anos            │
│  31-40 anos  →  31-40 anos            │
│  >40 anos    →  >40 anos (risco↑)     │
│                                        │
└────────────────────────────────────────┘
```

---

### 4️⃣ CTE: `pacientes_todos_cns`

**Objetivo:** Agregar todos os CNS (Cartão Nacional de Saúde) de cada paciente em uma string.

**Pseudocódigo:**
```
PARA CADA paciente EM tabela_paciente:
    PARA CADA cns NO array_cns_paciente:
        SE cns NÃO É NULL E cns != '':
            coletar cns

    cns_string = CONCATENAR(cns únicos, '; ')

    RETORNAR:
        - id_paciente
        - cns_string
FIM
```

**Exemplo Visual:**
```
ANTES (array de CNS):
┌──────────────────────────────────────────────┐
│ Paciente: Ana (ID: 67890)                    │
│                                              │
│ cns: [                                       │
│   "123456789012345",                         │
│   "987654321098765",                         │
│   "123456789012345"  (duplicado)             │
│ ]                                            │
└──────────────────────────────────────────────┘
       │
       │ STRING_AGG(DISTINCT ...)
       ↓
┌──────────────────────────────────────────────┐
│ cns_string:                                  │
│ "123456789012345; 987654321098765"           │
│                                              │
│ (Duplicados removidos, separados por ;)     │
└──────────────────────────────────────────────┘

Por quê concatenar?
→ Alguns pacientes têm múltiplos CNS
→ Facilita busca e análise
```

---

## 📋 BLOCO 2: Riscos e Categorias

### 5️⃣ CTE: `categorias_risco_gestacional`

**Objetivo:** Identificar categorias de risco gestacional baseadas em CIDs específicos.

**Fonte:** Tabela de referência `_cids_risco_gestacional_cat_encam`

**Pseudocódigo:**
```
PARA CADA gestacao EM filtrado:
    PARA CADA episodio DO paciente:
        SE episodio.data ENTRE [inicio, fim_efetivo]:
            PARA CADA condicao NO episodio:
                SE condicao.cid NA tabela_risco:

                    coletar:
                        - categoria (ex: "GEMELARIDADE", "NEFROPATIAS")
                        - cid
                        - encaminhamento_alto_risco
                        - justificativa_condicao

    // Agregar todas as categorias
    categorias_risco = STRING_AGG(DISTINCT categorias, '; ')
    cid_alto_risco = STRING_AGG(DISTINCT cids, '; ')
    encaminhamento = STRING_AGG(DISTINCT encaminhamentos, '; ')
    justificativa = STRING_AGG(DISTINCT justificativas, '; ')

    RETORNAR por id_gestacao
FIM
```

**Exemplo Visual:**
```
Gestação de Maria (2024-03-01 a 2024-09-20)
═══════════════════════════════════════════════════════

Episódios DURANTE a gestação:
  2024-03-15: CID Z35.3 (Gemelaridade)
  2024-05-20: CID O24.0 (Diabetes prévia)
  2024-07-10: CID N18.1 (Nefropatia)

Cruzamento com tabela de risco:
┌──────────────────────────────────────────────────────┐
│ CID     | Categoria      | Encaminhamento           │
├──────────────────────────────────────────────────────┤
│ Z35.3   | GEMELARIDADE   | Alto Risco               │
│ O24.0   | DIABETES       | Alto Risco               │
│ N18.1   | NEFROPATIAS    | Especialista             │
└──────────────────────────────────────────────────────┘

Resultado agregado:
  categorias_risco: "DIABETES; GEMELARIDADE; NEFROPATIAS"
  cid_alto_risco: "N18.1; O24.0; Z35.3"
  encaminhamento_alto_risco: "Alto Risco; Especialista"
```

---

### 6️⃣ CTE: `condicoes_flags`

**Objetivo:** Criar flags (0/1) para condições clínicas específicas com regras temporais diferentes.

**Condições Monitoradas:**
```
┌────────────────────────────────────────────────────────┐
│         CONDIÇÕES E SUAS JANELAS TEMPORAIS             │
├────────────────────────────────────────────────────────┤
│                                                        │
│  DIABETES:                                            │
│  • Prévio (E10-E14, O24.0-O24.3): ANTES do fim        │
│  • Gestacional (O24.4): DURANTE gestação              │
│  • Não especificado (O24.9): DURANTE gestação         │
│                                                        │
│  HIPERTENSÃO:                                         │
│  • Prévia (I10-I15, O10): ANTES do fim                │
│  • Pré-eclâmpsia (O11, O14): DURANTE gestação         │
│  • Não especificada (O16): DURANTE gestação           │
│                                                        │
│  INFECÇÕES:                                           │
│  • HIV (B20-B24, Z21): ATÉ o fim                      │
│  • Sífilis (A51-A53): 30 dias ANTES até fim           │
│  • Tuberculose (A15-A19): 6 MESES antes até fim       │
│                                                        │
│  OUTRAS:                                              │
│  • Doença autoimune (M32, D68.6): DURANTE             │
│  • Reprodução assistida (Z312-Z319): DURANTE          │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo (Exemplo: Diabetes Prévio):**
```
PARA CADA gestacao EM filtrado:

    diabetes_previo = 0  // Inicializa

    PARA CADA condicao DO paciente:

        SE condicao.cid EM ['E10'-'E14'] OU ['O24.0'-'O24.3']:
            SE condicao.data_diagnostico < fim_efetivo:
                diabetes_previo = 1
                SAIR DO LOOP  // Já encontrou

    RETORNAR diabetes_previo
FIM
```

**Exemplo Visual - Timeline:**
```
Gestação de Ana (2024-03-01 a 2024-09-20)
═══════════════════════════════════════════════════════

Timeline:
═══════════════════════════════════════════════════════
        ◄── 6 meses ──►◄── 30d ──►│         │
                                   │         │
                              data_inicio  data_fim
                              2024-03-01  2024-09-20

Condições da paciente:
  2022-05-10: E11 (Diabetes tipo 2)
    → ANTES do fim ✓
    → diabetes_previo = 1

  2024-04-15: O24.4 (Diabetes gestacional)
    → DURANTE gestação ✓
    → diabetes_gestacional = 1

  2023-12-01: A51 (Sífilis)
    → 90 dias ANTES do início (dentro da janela de 30d)
    → sifilis = 1

  2023-06-10: A15 (Tuberculose)
    → 8 meses ANTES (dentro da janela de 6 meses)
    → tuberculose = 1

Flags finais:
  diabetes_previo = 1 ✓
  diabetes_gestacional = 1 ✓
  sifilis = 1 ✓
  tuberculose = 1 ✓
```

**Por quê janelas diferentes?**
```
┌────────────────────────────────────────────────────────┐
│  HIV:                                                  │
│  • Condição crônica                                   │
│  • Importa se tem ATÉ o fim da gestação               │
│                                                        │
│  Sífilis:                                             │
│  • Pode ser adquirida pouco antes da gestação         │
│  • Janela de 30 dias captura infecções recentes       │
│                                                        │
│  Tuberculose:                                         │
│  • Tratamento dura 6 meses                            │
│  • Janela de 6 meses captura casos em tratamento     │
│                                                        │
│  Diabetes/Hipertensão Prévia:                         │
│  • Condições crônicas                                 │
│  • Diagnóstico ANTES do fim = preexistente            │
│                                                        │
│  Diabetes/Hipertensão Gestacional:                    │
│  • Surgem DURANTE a gestação                          │
│  • Diagnóstico dentro do período gestacional          │
└────────────────────────────────────────────────────────┘
```

---

## 📋 BLOCO 3: Equipes e Mudanças

### 7️⃣ CTE: `unnested_equipes`

**Objetivo:** "Desempacotar" o array de equipes de saúde da família.

**Pseudocódigo:**
```
PARA CADA paciente EM tabela_paciente:
    PARA CADA equipe NO array_equipe_saude_familia:
        RETORNAR:
            - id_paciente
            - datahora_ultima_atualizacao
            - equipe_nome
            - clinica_nome
FIM
```

**Exemplo Visual:**
```
ANTES (array aninhado):
┌──────────────────────────────────────────────────────┐
│ Paciente: Maria (ID: 12345)                          │
│                                                      │
│ equipe_saude_familia: [                              │
│   {                                                  │
│     nome: "Equipe Verde",                            │
│     clinica: "CF Zona Norte",                        │
│     atualizacao: "2023-01-15 10:00"                  │
│   },                                                 │
│   {                                                  │
│     nome: "Equipe Azul",                             │
│     clinica: "CF Centro",                            │
│     atualizacao: "2023-08-20 14:30"                  │
│   },                                                 │
│   {                                                  │
│     nome: "Equipe Verde",                            │
│     clinica: "CF Zona Norte",                        │
│     atualizacao: "2024-02-10 09:15"                  │
│   }                                                  │
│ ]                                                    │
└──────────────────────────────────────────────────────┘

DEPOIS (linhas separadas):
┌──────────────────────────────────────────────────────┐
│ id  | equipe      | clinica       | atualizacao     │
├──────────────────────────────────────────────────────┤
│ 123 | Equipe Verde| CF Zona Norte | 2023-01-15      │
│ 123 | Equipe Azul | CF Centro     | 2023-08-20      │
│ 123 | Equipe Verde| CF Zona Norte | 2024-02-10      │
└──────────────────────────────────────────────────────┘
```

---

### 8️⃣ CTE: `equipe_durante_gestacao`

**Objetivo:** Identificar a equipe MAIS RECENTE durante o período da gestação.

**Pseudocódigo:**
```
PARA CADA gestacao EM filtrado:

    equipes_validas = BUSCAR unnested_equipes ONDE:
        - mesma id_paciente
        - data_atualizacao_equipe <= fim_efetivo (ou data_ref)

    SE equipes_validas EXISTE:
        // Ordenar por data de atualização
        ranking = ROW_NUMBER() ORDENADO por data_atualizacao DESC

        RETORNAR equipe com ranking = 1
FIM
```

**Exemplo Visual:**
```
Gestação de Maria (2024-03-01 a 2024-09-20)
═══════════════════════════════════════════════════════

Equipes do histórico:
  2023-01-15: Equipe Verde  ← ANTES (mas válida)
  2023-08-20: Equipe Azul   ← ANTES (mas válida)
  2024-02-10: Equipe Verde  ← ANTES (mas válida)
  2024-06-15: Equipe Laranja ← DURANTE ✓ (MAIS RECENTE)
  2024-10-01: Equipe Rosa   ← DEPOIS (inválida)

Equipes válidas (até fim_efetivo):
┌──────────────────────────────────────────────────────┐
│ Data        | Equipe         | Ranking              │
├──────────────────────────────────────────────────────┤
│ 2024-06-15  | Equipe Laranja | 1 ← ESCOLHIDA       │
│ 2024-02-10  | Equipe Verde   | 2                    │
│ 2023-08-20  | Equipe Azul    | 3                    │
│ 2023-01-15  | Equipe Verde   | 4                    │
└──────────────────────────────────────────────────────┘

Equipe durante: Equipe Laranja ✓
```

---

### 9️⃣ CTE: `equipe_anterior_gestacao`

**Objetivo:** Identificar a equipe ANTES do início da gestação.

**Pseudocódigo:**
```
PARA CADA gestacao EM filtrado:

    equipes_anteriores = BUSCAR unnested_equipes ONDE:
        - mesma id_paciente
        - data_atualizacao_equipe < data_inicio  // ESTRITAMENTE ANTES

    SE equipes_anteriores EXISTE:
        ranking = ROW_NUMBER() ORDENADO por data_atualizacao DESC

        RETORNAR equipe com ranking = 1
FIM
```

**Exemplo Visual:**
```
Gestação de Maria (início: 2024-03-01)
═══════════════════════════════════════════════════════

                        │
                        │ data_inicio
                        │ 2024-03-01
                        │
────────────────────────┼───────────────────────────────
    ANTES (válido)      │      DURANTE/DEPOIS
                        │
2023-01-15: Verde       │  2024-03-15: Laranja
2023-08-20: Azul        │  2024-06-15: Laranja
2024-02-10: Verde  ← ✓ │  (não conta aqui)
                        │

Equipe anterior: Equipe Verde (2024-02-10) ✓
(Mais recente ANTES do início)
```

---

### 🔟 CTE: `mudanca_equipe`

**Objetivo:** Detectar se houve mudança de equipe durante a gestação.

**Pseudocódigo:**
```
PARA CADA gestacao:

    equipe_durante = buscar em equipe_durante_final
    equipe_anterior = buscar em equipe_anterior_final

    SE equipe_durante != equipe_anterior:
        mudanca_equipe_durante_pn = 1
    SENÃO:
        mudanca_equipe_durante_pn = 0

    RETORNAR:
        - id_gestacao
        - mudanca_equipe_durante_pn
FIM
```

**Exemplo Visual:**
```
Cenário 1: SEM mudança
═══════════════════════════════════════════════════════
ANTES            │ DURANTE
Equipe Verde     │ Equipe Verde
                 │
→ mudanca = 0 ✓

Cenário 2: COM mudança
═══════════════════════════════════════════════════════
ANTES            │ DURANTE
Equipe Verde     │ Equipe Laranja
                 │
→ mudanca = 1 ✓

Cenário 3: Retorno à equipe antiga
═══════════════════════════════════════════════════════
Histórico:
  2023-01: Verde
  2023-08: Azul (← anterior)
  2024-06: Verde (← durante)

→ mudanca = 1 ✓
(Azul → Verde é mudança, mesmo sendo retorno)

Por quê isso importa?
→ Mudança de equipe pode indicar:
  • Mudança de endereço
  • Reordenamento territorial
  • Perda de vínculo (preocupante!)
```

---

## 📋 BLOCO 4: Eventos de Parto

### 1️⃣1️⃣ CTE: `eventos_parto`

**Objetivo:** Identificar eventos de parto/aborto registrados no sistema **VITAI**.

**CIDs de Parto/Aborto:**
```
┌────────────────────────────────────────────────────────┐
│         CLASSIFICAÇÃO DE EVENTOS OBSTÉTRICOS           │
├────────────────────────────────────────────────────────┤
│                                                        │
│  PARTO:                                               │
│  • O80-O84: Parto (normal, cesárea, instrumental)    │
│  • Z37: Resultado do parto (nascido vivo/morto)       │
│  • Z39: Cuidado pós-parto                             │
│                                                        │
│  ABORTO:                                              │
│  • O00-O04: Aborto (espontâneo, induzido, etc)        │
│                                                        │
│  OUTRO:                                               │
│  • Z38: Nascido vivo (pode estar no prontuário mãe)   │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA episodio EM episodios_assistenciais:

    SE episodio.data >= '2021-01-01':  // Filtro de relevância
        SE episodio.fornecedor = 'vitai':  // Sistema hospitalar
            PARA CADA condicao NO episodio:

                SE condicao.cid EM lista_partos_abortos:

                    // Classificar tipo
                    SE cid EM ['O80'-'O84', 'Z37', 'Z39']:
                        tipo = 'Parto'
                    SENÃO SE cid EM ['O00'-'O04']:
                        tipo = 'Aborto'
                    SENÃO:
                        tipo = 'Outro'

                    RETORNAR:
                        - id_paciente
                        - data_parto
                        - estabelecimento_parto
                        - motivo_atendimento_parto
                        - desfecho_atendimento_parto
                        - tipo_parto
                        - cid_parto
FIM
```

**Exemplo Visual:**
```
Sistema VITAI (Hospitalar)
═══════════════════════════════════════════════════════

Episódio 1:
  Data: 2024-09-15
  Estabelecimento: Hospital Municipal XYZ
  CID: O80.0 (Parto normal espontâneo)
  → tipo_parto = 'Parto' ✓

Episódio 2:
  Data: 2024-03-20
  Estabelecimento: Maternidade ABC
  CID: O03 (Aborto espontâneo)
  → tipo_parto = 'Aborto' ✓

Por quê apenas VITAI?
→ Sistema hospitalar (onde partos acontecem)
→ VITACARE = APS (não registra partos)
→ VITAI = Hospital (registra partos/abortos)
```

---

### 1️⃣2️⃣ CTE: `partos_associados`

**Objetivo:** Associar o evento de parto **mais próximo** à data de fim efetiva da gestação.

**Janela de Associação:**
```
┌────────────────────────────────────────────────────────┐
│  JANELA DE BUSCA DE PARTO                              │
│                                                        │
│  [data_inicio] até [data_fim_efetiva + 15 dias]       │
│                                                        │
│  Por quê +15 dias?                                    │
│  • Parto pode ser registrado dias após o evento       │
│  • Atraso administrativo no sistema                   │
│  • Margem de segurança para matching                  │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA gestacao EM filtrado:

    partos_na_janela = BUSCAR eventos_parto ONDE:
        - mesma id_paciente
        - data_parto ENTRE [inicio, fim_efetivo + 15 dias]

    SE partos_na_janela EXISTE:

        // Pegar o parto MAIS PRÓXIMO da data_fim_efetiva
        parto_escolhido = ARRAY_AGG(
            partos
            ORDENADO por ABS(data_parto - data_fim_efetiva)
            LIMIT 1
        )[0]

        RETORNAR:
            - id_gestacao
            - parto_escolhido (como struct)
FIM
```

**Exemplo Visual:**
```
Gestação de Ana (2024-03-01 a 2024-09-20)
═══════════════════════════════════════════════════════

Janela de busca:
═══════════════════════════════════════════════════════
2024-03-01              2024-09-20    2024-10-05
    │                       │             │
    └─────── GESTAÇÃO ──────┴──── +15d ──┘

Eventos de parto encontrados:
  2024-09-18: O80 (Parto normal) → |2 dias| ← MAIS PRÓXIMO ✓
  2024-09-25: Z39 (Pós-parto)    → |5 dias|
  2024-10-02: Z38 (Nascido vivo) → |12 dias|

Parto associado:
  data_parto: 2024-09-18
  tipo_parto: "Parto"
  estabelecimento: "Maternidade Municipal XYZ"
  cid: "O80"

Por quê o MAIS PRÓXIMO?
→ Pode haver múltiplos registros (pós-parto, etc)
→ O mais próximo é o evento principal
→ Outros são acompanhamentos
```

---

## 📋 BLOCO 5: Agregações de Consultas

Este bloco agrega informações das consultas pré-natais (da tabela `_atendimentos_prenatal_aps_historico`).

### 1️⃣3️⃣ CTE: `consultas_prenatal`

**Objetivo:** Contar total de consultas pré-natal por gestação.

**Pseudocódigo:**
```
PARA CADA consulta EM atendimentos_prenatal_aps_historico:
    SE consulta.data_snapshot = data_referencia:
        AGRUPAR por id_gestacao
        CONTAR(*)

RETORNAR:
    - id_gestacao
    - total_consultas_prenatal
FIM
```

**Exemplo Visual:**
```
Gestação 12345-1:
  Consulta 1: 2024-03-15
  Consulta 2: 2024-04-20
  Consulta 3: 2024-06-10
  Consulta 4: 2024-07-25

  total_consultas_prenatal = 4 ✓

Gestação 67890-2:
  Consulta 1: 2024-05-10
  Consulta 2: 2024-07-15

  total_consultas_prenatal = 2 ✓
```

---

### 1️⃣4️⃣ CTE: `status_prescricoes`

**Objetivo:** Verificar se houve prescrição de **ácido fólico** e **carbonato de cálcio**.

**Pseudocódigo:**
```
PARA CADA consulta EM atendimentos_prenatal_aps:

    // Buscar ácido fólico
    SE REGEX(prescricoes, 'f[oó]lico'):
        tem_folico = 'sim'

    // Buscar carbonato de cálcio
    SE REGEX(prescricoes, 'c[aá]lcio'):
        tem_calcio = 'sim'

AGRUPAR por id_gestacao:
    prescricao_acido_folico = MAX(tem_folico)  // Se alguma teve
    prescricao_carbonato_calcio = MAX(tem_calcio)

RETORNAR por id_gestacao
FIM
```

**Exemplo Visual:**
```
Gestação de Maria:
═══════════════════════════════════════════════════════

Consulta 1:
  Prescrições: "Ácido Fólico 5mg"
  → tem_folico = 'sim'

Consulta 2:
  Prescrições: "Ácido Fólico 5mg, Sulfato Ferroso"
  → tem_folico = 'sim'

Consulta 3:
  Prescrições: "Sulfato Ferroso 40mg"
  → (não tem fólico nem cálcio)

Consulta 4:
  Prescrições: "Carbonato de Cálcio 500mg"
  → tem_calcio = 'sim'

Resultado (MAX):
  prescricao_acido_folico = 'sim' ✓
  prescricao_carbonato_calcio = 'sim' ✓

Por quê MAX()?
→ Se ALGUMA consulta teve a prescrição = 'sim'
→ Se NENHUMA teve = 'não' (default)
```

---

### 1️⃣5️⃣ CTE: `ultima_consulta_prenatal`

**Objetivo:** Data da última consulta pré-natal.

**Pseudocódigo:**
```
PARA CADA gestacao:
    data_ultima_consulta = MAX(data_consulta)

RETORNAR:
    - id_gestacao
    - data_ultima_consulta
FIM
```

---

### 1️⃣6️⃣ CTE: `maior_pa_por_gestacao`

**Objetivo:** Identificar a **maior pressão arterial** registrada durante a gestação.

**Pseudocódigo:**
```
PARA CADA consulta COM pressao:

    ranking = ROW_NUMBER() PARTICIONADO por id_gestacao
              ORDENADO por (pressao_sistolica DESC, pressao_diastolica DESC)

SE ranking = 1:
    RETORNAR:
        - id_gestacao
        - pressao_sistolica (maior)
        - pressao_diastolica (maior)
        - data_consulta (quando foi medida)
FIM
```

**Exemplo Visual:**
```
Gestação de Ana:
═══════════════════════════════════════════════════════

PAs medidas:
  2024-03-15: 120/80  → Sistólica: 120
  2024-04-20: 130/85  → Sistólica: 130
  2024-06-10: 145/95  → Sistólica: 145 ← MAIOR ✓
  2024-07-25: 138/88  → Sistólica: 138

Maior PA:
  pressao_sistolica: 145
  pressao_diastolica: 95
  data_consulta: 2024-06-10

Por quê a MAIOR?
→ Identificar picos de pressão
→ Avaliar controle hipertensivo
→ Detectar risco de pré-eclâmpsia
```

---

## 📋 BLOCO 6: Visitas ACS

### 1️⃣7️⃣ CTE: `visitas_acs_por_gestacao`

**Objetivo:** Contar visitas de Agente Comunitário de Saúde (ACS) durante a gestação.

**Pseudocódigo:**
```
PARA CADA visita EM _visitas_acs_gestacao_historico:
    SE visita.data_snapshot = data_referencia:
        AGRUPAR por id_gestacao
        CONTAR(*)

RETORNAR:
    - id_gestacao
    - total_visitas_acs
FIM
```

---

### 1️⃣8️⃣ CTE: `ultima_visita_acs`

**Objetivo:** Data da última visita do ACS.

**Pseudocódigo:**
```
PARA CADA gestacao:
    data_ultima_visita = MAX(entrada_data)

RETORNAR:
    - id_gestacao
    - data_ultima_visita
FIM
```

---

## 📋 BLOCO 7: Análise de Hipertensão (NOVO - Complexo)

Este bloco é **extenso e detalhado**, com análise aprofundada de hipertensão gestacional.

### 1️⃣9️⃣ CTE: `analise_pressao_arterial`

**Objetivo:** Analisar cada medição de PA e classificar conforme critérios clínicos.

**Critérios de Classificação:**
```
┌────────────────────────────────────────────────────────┐
│      CLASSIFICAÇÃO DE PRESSÃO ARTERIAL                 │
├────────────────────────────────────────────────────────┤
│                                                        │
│  PA CONTROLADA:                                       │
│    Sistólica < 140 E Diastólica < 90                  │
│                                                        │
│  PA ALTERADA:                                         │
│    Sistólica ≥ 140 OU Diastólica ≥ 90                 │
│                                                        │
│  PA GRAVE:                                            │
│    Sistólica > 160 OU Diastólica > 110                │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA consulta COM pressao:

    // Classificar PA alterada
    SE sistolica >= 140 OU diastolica >= 90:
        pa_alterada = 1
    SENÃO:
        pa_alterada = 0

    // Classificar PA grave
    SE sistolica > 160 OU diastolica > 110:
        pa_grave = 1
    SENÃO:
        pa_grave = 0

    // Classificar PA controlada
    SE sistolica < 140 E diastolica < 90:
        pa_controlada = 1
    SENÃO:
        pa_controlada = 0

    RETORNAR:
        - id_gestacao
        - data_consulta
        - pressao_sistolica, pressao_diastolica
        - pa_alterada, pa_grave, pa_controlada
FIM
```

**Exemplo Visual:**
```
Gestação de Carla:
═══════════════════════════════════════════════════════

Consulta 1: 120/80
  → pa_controlada = 1 ✓
  → pa_alterada = 0
  → pa_grave = 0

Consulta 2: 145/95
  → pa_controlada = 0
  → pa_alterada = 1 ✓
  → pa_grave = 0

Consulta 3: 165/105
  → pa_controlada = 0
  → pa_alterada = 1 ✓
  → pa_grave = 1 ✓ (ATENÇÃO!)

Consulta 4: 135/85
  → pa_controlada = 1 ✓
  → pa_alterada = 0
  → pa_grave = 0

Gráfico de Evolução:
──────────────────────────────────────────────────
PA (mmHg)
180 │
170 │              ●  (165/105 - GRAVE!)
160 │              │
150 │         ●    │  (145/95)
140 │─────────┼────┼──────────────────── Limite
130 │         │    │         ●  (135/85)
120 │    ●    │    │         │
110 │────┼────┴────┴─────────┴────────── Normal
    │    C1   C2   C3        C4
```

---

### 2️⃣0️⃣ CTE: `resumo_controle_pressorico`

**Objetivo:** Resumir o controle pressórico de toda a gestação.

**Pseudocódigo:**
```
PARA CADA gestacao:

    qtd_pas_alteradas = COUNT(pa_alterada = 1)
    teve_pa_grave = MAX(pa_grave)  // 1 se alguma foi grave
    total_medicoes_pa = COUNT(*)

    // Percentual de controle
    qtd_controladas = COUNT(pa_controlada = 1)
    percentual_pa_controlada = (qtd_controladas / total_medicoes) * 100

    RETORNAR:
        - id_gestacao
        - qtd_pas_alteradas
        - teve_pa_grave
        - total_medicoes_pa
        - percentual_pa_controlada
FIM
```

**Exemplo Visual:**
```
Gestação de Carla:
═══════════════════════════════════════════════════════

Medições:
  C1: 120/80  → Controlada ✓
  C2: 145/95  → Alterada ✗
  C3: 165/105 → Alterada ✗ (Grave!)
  C4: 135/85  → Controlada ✓

Resumo:
  qtd_pas_alteradas = 2
  teve_pa_grave = 1 (sim!)
  total_medicoes_pa = 4
  percentual_pa_controlada = (2/4) * 100 = 50.0%

Interpretação:
┌────────────────────────────────────────────┐
│  50% de controle = PREOCUPANTE            │
│  • Teve PA grave                           │
│  • Metade das medições alteradas          │
│  • Necessita intervenção!                 │
└────────────────────────────────────────────┘
```

---

### 2️⃣1️⃣ CTE: `ultima_pa_aferida`

**Objetivo:** Informações da última PA medida.

**Pseudocódigo:**
```
PARA CADA medicao:
    ranking = ROW_NUMBER() ORDENADO por data_consulta DESC

SE ranking = 1:
    RETORNAR:
        - id_gestacao
        - data_ultima_pa
        - ultima_sistolica, ultima_diastolica
        - ultima_pa_controlada (0 ou 1)
FIM
```

---

### 2️⃣2️⃣ CTE: `prescricoes_anti_hipertensivos`

**Objetivo:** Identificar prescrição de medicamentos anti-hipertensivos.

**Medicamentos Monitorados:**
```
┌────────────────────────────────────────────────────────┐
│     ANTI-HIPERTENSIVOS MONITORADOS                     │
├────────────────────────────────────────────────────────┤
│                                                        │
│  SEGUROS NA GESTAÇÃO:                                 │
│  • Metildopa (primeira linha)                         │
│  • Hidralazina (emergências)                          │
│  • Nifedipina (segunda linha)                         │
│                                                        │
│  CONTRAINDICADOS/USO COM CAUTELA:                     │
│  • Enalapril, Captopril (IECA - contraindicados!)     │
│  • Losartana (BRA - contraindicado!)                  │
│  • Atenolol, Propranolol (beta-bloq - cautela)        │
│  • Anlodipina, Verapamil (calc-bloq - cautela)        │
│  • Hidroclorotiazida, Furosemida (diuréticos)         │
│  • Espironolactona (diurético)                        │
│  • Carvedilol (beta-bloq)                             │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA consulta COM prescricoes:

    // Verificar cada medicamento individualmente
    tem_metildopa = REGEX(prescricoes, 'METILDOPA') ? 1 : 0
    tem_hidralazina = REGEX(prescricoes, 'HIDRALAZINA') ? 1 : 0
    tem_nifedipina = REGEX(prescricoes, 'NIFEDIPINA') ? 1 : 0
    tem_enalapril = REGEX(prescricoes, 'ENALAPRIL') ? 1 : 0
    ... (continua para todos)

    // Flag geral
    tem_anti_hipertensivo = (algum medicamento encontrado) ? 1 : 0

AGRUPAR por id_gestacao:
    // MAX para cada medicamento (se alguma consulta teve)
    RETORNAR flags individuais e flag geral
FIM
```

---

### 2️⃣3️⃣ CTE: `classificacao_anti_hipertensivos`

**Objetivo:** Classificar anti-hipertensivos em SEGUROS vs CONTRAINDICADOS.

**Pseudocódigo:**
```
PARA CADA gestacao COM anti-hipertensivos:

    // Verificar se tem algum SEGURO
    SE tem_metildopa OU tem_hidralazina OU tem_nifedipina:
        tem_anti_hipertensivo_seguro = 1

        // Listar quais
        lista_seguros = STRING_AGG([
            'METILDOPA' se tem_metildopa,
            'HIDRALAZINA' se tem_hidralazina,
            'NIFEDIPINA' se tem_nifedipina
        ], '; ')

    // Verificar se tem algum CONTRAINDICADO
    SE tem_enalapril OU tem_losartana OU ... (outros):
        tem_anti_hipertensivo_contraindicado = 1

        // Listar quais
        lista_contraindicados = STRING_AGG([...], '; ')

    RETORNAR:
        - id_gestacao
        - tem_anti_hipertensivo_seguro
        - tem_anti_hipertensivo_contraindicado
        - anti_hipertensivos_seguros (lista)
        - anti_hipertensivos_contraindicados (lista)
FIM
```

**Exemplo Visual:**
```
Gestação de Paula:
═══════════════════════════════════════════════════════

Prescrições encontradas:
  C1: "METILDOPA 250MG"
  C2: "METILDOPA 250MG, ENALAPRIL 10MG"
  C3: "METILDOPA 250MG, NIFEDIPINA 20MG"

Classificação:
  tem_anti_hipertensivo = 1 ✓

  SEGUROS:
    tem_metildopa = 1 ✓
    tem_nifedipina = 1 ✓
    anti_hipertensivos_seguros = "METILDOPA; NIFEDIPINA"

  CONTRAINDICADOS:
    tem_enalapril = 1 ✗ ALERTA!
    anti_hipertensivos_contraindicados = "ENALAPRIL"

⚠️ SITUAÇÃO PREOCUPANTE:
  • Tem medicamento CONTRAINDICADO (Enalapril)
  • Enalapril é IECA (pode causar malformações!)
  • Necessita substituição urgente!
```

---

### 2️⃣4️⃣ CTE: `encaminhamento_hipertensao_sisreg`

**Objetivo:** Identificar encaminhamentos para pré-natal de alto risco por hipertensão via **SISREG**.

**Pseudocódigo:**
```
PARA CADA gestacao:

    encaminhamentos = BUSCAR em tabela_sisreg ONDE:
        - mesma id_paciente (via CPF)
        - procedimento = '0703844' (Obstetrícia Alto Risco)
        - CID de hipertensão (O10, I10-I15, O11, O13-O16)
        - data_solicitacao ENTRE [inicio, fim_efetivo]

    SE encaminhamentos EXISTE:
        // Pegar o PRIMEIRO cronologicamente
        ranking = ROW_NUMBER() ORDENADO por data_solicitacao ASC

        RETORNAR encaminhamento com ranking = 1
FIM
```

---

### 2️⃣5️⃣ CTE: `encaminhamento_hipertensao_SER`

**Objetivo:** Identificar encaminhamentos via sistema **SER** (similar ao SISREG, mas sistema diferente).

**Pseudocódigo:** Similar ao SISREG, mas usando campos do SER.

---

### 2️⃣6️⃣ CTE: `resumo_encaminhamento_has`

**Objetivo:** Consolidar encaminhamentos de SISREG e SER em um único resumo.

**Pseudocódigo:**
```
// União de encaminhamentos de ambas as fontes
encaminhamentos_unidos =
    SELECT de SISREG
    UNION ALL
    SELECT de SER

PARA CADA gestacao:
    tem_encaminhamento_has = (existe encaminhamento) ? 1 : 0
    data_primeiro = MIN(data_encaminhamento)
    cids = STRING_AGG(DISTINCT cids)

RETORNAR:
    - id_gestacao
    - tem_encaminhamento_has
    - data_primeiro_encaminhamento_has
    - cids_encaminhamento_has
FIM
```

---

### 2️⃣7️⃣ CTE: `dispensacao_aparelho_pa`

**Objetivo:** Identificar dispensação de aparelho de pressão arterial para uso domiciliar.

**IDs de Material:**
- `65159513221`: Aparelho de PA digital
- `65159506608`: Aparelho de PA aneróide

**Pseudocódigo:**
```
PARA CADA gestacao:

    dispensacoes = BUSCAR em movimento_estoque ONDE:
        - cpf_paciente = cpf_gestante
        - id_material EM ['65159513221', '65159506608']
        - data_dispensacao ENTRE [inicio, fim_efetivo]

    SE dispensacoes EXISTE:
        tem_aparelho_pa_dispensado = 1
        data_primeira_dispensacao = MIN(data)
        qtd_aparelhos = COUNT(*)
    SENÃO:
        tem_aparelho_pa_dispensado = 0

RETORNAR:
    - id_gestacao
    - tem_aparelho_pa_dispensado
    - data_primeira_dispensacao_pa
    - qtd_aparelhos_pa_dispensados
FIM
```

**Exemplo Visual:**
```
Gestação de Fernanda (HAS prévia):
═══════════════════════════════════════════════════════

Movimentações de estoque:
  2024-04-10: Aparelho PA digital (65159513221)
  2024-07-15: Aparelho PA digital (65159513221) [reposição]

Resultado:
  tem_aparelho_pa_dispensado = 1 ✓
  data_primeira_dispensacao_pa = 2024-04-10
  qtd_aparelhos_pa_dispensados = 2

Por quê isso importa?
→ Monitoramento domiciliar de hipertensas
→ Permite acompanhamento mais próximo
→ Indica gestação de risco sob controle ativo
```

---

### 2️⃣8️⃣ CTE: `hipertensao_gestacional_completa`

**Objetivo:** **CONSOLIDAR** toda a análise de hipertensão em uma única CTE.

**Inclui:**
- Controle pressórico (resumo_controle_pressorico)
- Última PA (ultima_pa_aferida)
- Medicamentos (classificacao_anti_hipertensivos)
- Encaminhamentos (resumo_encaminhamento_has)
- Aparelho de PA (dispensacao_aparelho_pa)
- **Lógica especial**: "Provável hipertensa sem diagnóstico"

**Lógica "Provável Hipertensa Sem Diagnóstico":**
```
┌────────────────────────────────────────────────────────┐
│  CRITÉRIOS PARA "PROVÁVEL HIPERTENSA SEM DIAGNÓSTICO"  │
├────────────────────────────────────────────────────────┤
│                                                        │
│  CONDIÇÃO 1 - Tem EVIDÊNCIA de hipertensão:           │
│    • 2+ PAs alteradas (≥140/90) OU                    │
│    • Teve PA grave (>160/110) OU                      │
│    • Tem prescrição de anti-hipertensivo OU           │
│    • Tem encaminhamento HAS OU                        │
│    • Tem aparelho de PA dispensado                    │
│                                                        │
│  E                                                     │
│                                                        │
│  CONDIÇÃO 2 - NÃO tem diagnóstico formal:             │
│    • Sem CID de hipertensão prévia (I10-I15, O10)     │
│    • Sem CID de pré-eclâmpsia (O11, O14)              │
│    • Sem CID de hipertensão não especificada (O16)    │
│                                                        │
│  → Provável subdiagnóstico ou falta de registro!      │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Exemplo Visual:**
```
Caso: Gestante Júlia
═══════════════════════════════════════════════════════

EVIDÊNCIAS:
  ✓ 3 PAs alteradas (145/95, 150/98, 142/90)
  ✓ Prescrição de METILDOPA
  ✓ Aparelho de PA dispensado

DIAGNÓSTICOS FORMAIS:
  ✗ Sem CID I10-I15 (hipertensão prévia)
  ✗ Sem CID O10 (hipertensão prévia gestacional)
  ✗ Sem CID O11/O14 (pré-eclâmpsia)
  ✗ Sem CID O16 (hipertensão não especificada)

RESULTADO:
  provavel_hipertensa_sem_diagnostico = 1 ✓

⚠️ ALERTA:
  • Gestante está sendo TRATADA para hipertensão
  • Mas NÃO tem diagnóstico registrado!
  • Possível falha de codificação
  • Necessita revisão do prontuário
```

---

## 📋 BLOCO 8: Análise de Diabetes

### 2️⃣9️⃣ CTE: `prescricoes_antidiabeticos`

**Objetivo:** Identificar prescrição de medicamentos antidiabéticos.

**Medicamentos Monitorados:**
- Metformina
- Insulina
- Glibenclamida
- Gliclazida

**Pseudocódigo:**
```
PARA CADA consulta COM prescricoes:

    SE REGEX(prescricoes, 'METFORMINA|INSULINA|GLIBENCLAMIDA|GLICLAZIDA'):
        tem_antidiabetico = 1

        // Identificar qual(is)
        SE REGEX('METFORMINA'): lista.add('METFORMINA')
        SE REGEX('INSULINA'): lista.add('INSULINA')
        SE REGEX('GLIBENCLAMIDA'): lista.add('GLIBENCLAMIDA')
        SE REGEX('GLICLAZIDA'): lista.add('GLICLAZIDA')

AGRUPAR por id_gestacao:
    tem_antidiabetico = MAX(tem_antidiabetico)
    antidiabeticos_lista = STRING_AGG(DISTINCT medicamentos, '; ')

RETORNAR por id_gestacao
FIM
```

---

## 📋 BLOCO 9: Unidades de Cadastro e Atendimento

### 3️⃣0️⃣ CTE: `cad_e_atd` (Complexa - Múltiplas Sub-CTEs)

**Objetivo:** Determinar a **unidade de vínculo (cadastro)** e a **unidade de atendimento** prioritária para cada gestante.

Esta CTE é **muito complexa** com lógica de priorização sofisticada. Vou simplificar:

**Sub-CTEs Internas:**
```
┌────────────────────────────────────────────────────────┐
│  FLUXO INTERNO DA CTE cad_e_atd                        │
├────────────────────────────────────────────────────────┤
│                                                        │
│  1. linha_tempo_base                                  │
│     └─ Relaciona gestações com CPF                    │
│                                                        │
│  2. linha_cadastro                                    │
│     └─ Busca cadastros por CPF                        │
│                                                        │
│  3. cadastro_filtrado                                 │
│     └─ Filtra apenas cadastros ATIVOS                 │
│                                                        │
│  4. cadastro_normalizado                              │
│     └─ Normaliza nomes de unidades                    │
│                                                        │
│  5. atendimentos_por_unidade                          │
│     └─ Conta atendimentos por unidade                 │
│                                                        │
│  6. unidade_atendimento_prioritaria                   │
│     └─ Seleciona unidade com MAIS atendimentos        │
│                                                        │
│  7. cadastro_enriquecido                              │
│     └─ Adiciona dados de atendimentos ao cadastro     │
│                                                        │
│  8. cadastro_classificado                             │
│     └─ Classifica cadastros (permanente vs temp)      │
│                                                        │
│  9. cadastro_prioritario                              │
│     └─ Seleciona O cadastro prioritário               │
│                                                        │
│  10. SELECT FINAL                                     │
│      └─ Combina cadastro + unidade atendimento        │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Lógica de Priorização de Cadastro:**
```
┌────────────────────────────────────────────────────────┐
│  CRITÉRIOS DE PRIORIDADE (em ordem):                   │
├────────────────────────────────────────────────────────┤
│                                                        │
│  Prioridade 1: ÚNICO cadastro permanente              │
│    → Se tem apenas 1 cadastro permanente, usa ele     │
│                                                        │
│  Prioridade 2: MÚLTIPLOS cadastros permanentes        │
│    → Entre eles, escolhe:                             │
│      a) Unidade com MAIS atendimentos                 │
│      b) Unidade com atendimento MAIS RECENTE          │
│      c) Cadastro mais recente (data_atualizacao)      │
│                                                        │
│  Prioridade 3: SEM cadastro permanente                │
│    → Entre cadastros temporários:                     │
│      a) Atendimento MAIS RECENTE                      │
│      b) Cadastro mais recente                         │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Exemplo Visual:**
```
Gestante: Roberta
═══════════════════════════════════════════════════════

Cadastros:
  Cadastro A: CF Norte (permanente)
    • 8 atendimentos
    • Último: 2024-08-01

  Cadastro B: CF Sul (permanente)
    • 3 atendimentos
    • Último: 2024-07-15

  Cadastro C: CF Centro (temporário)
    • 1 atendimento
    • Último: 2024-06-10

Priorização:
  1. Múltiplos cadastros permanentes (A e B)
  2. A tem MAIS atendimentos (8 > 3)
  3. A tem atendimento MAIS RECENTE

RESULTADO:
  unidade_vinculo_cadastro = "CF Norte" ✓
  unidade_atendimento = "CF Norte" ✓
  total_atendimentos = 8
```

---

## 🎯 SELECT FINAL - Consolidação Completa

**Objetivo:** Juntar TODAS as CTEs em uma única linha por gestação.

**Estrutura:**
```
SELECT
    data_referencia AS data_snapshot,  -- Metadado do snapshot

    -- BLOCO: Identificação
    f.id_gestacao,
    f.id_paciente,
    pi.cpf,
    pi.cns,
    ptcns.cns_string,  -- Todos os CNS
    pi.nome,

    -- BLOCO: Demografia
    pi.idade_atual,
    pi.faixa_etaria,
    pi.raca,
    pi.obito_indicador,
    pi.obito_data,

    -- BLOCO: Dados da Gestação
    f.numero_gestacao,
    f.data_inicio,
    f.data_fim,
    f.data_fim_efetiva,
    f.dpp,
    f.fase_atual,
    f.trimestre_atual_gestacao,
    f.ig_atual_semanas,
    f.ig_final_semanas,

    -- BLOCO: Riscos e Categorias
    crg.categorias_risco,
    crg.cid_alto_risco,
    crg.encaminhamento_alto_risco,

    -- BLOCO: Flags de Condições
    cf.diabetes_previo,
    cf.diabetes_gestacional,
    cf.diabetes_nao_especificado,
    cf.hipertensao_previa,
    cf.preeclampsia,
    cf.hipertensao_nao_especificada,
    cf.hiv,
    cf.sifilis,
    cf.tuberculose,
    cf.doenca_autoimune_cid,
    cf.reproducao_assistida_cid,

    -- BLOCO: Equipes
    edf.equipe_nome,
    edf.clinica_nome,
    me.mudanca_equipe_durante_pn,

    -- BLOCO: Parto
    pa.evento_parto_associado.data_parto,
    pa.evento_parto_associado.tipo_parto,
    pa.evento_parto_associado.estabelecimento_parto,

    -- BLOCO: Consultas
    cp.total_consultas_prenatal,
    ucp.data_ultima_consulta,
    sp.prescricao_acido_folico,
    sp.prescricao_carbonato_calcio,

    -- BLOCO: Visitas ACS
    vacs.total_visitas_acs,
    uvacs.data_ultima_visita,

    -- BLOCO: Pressão Arterial
    mpa.pressao_sistolica AS maior_sistolica,
    mpa.pressao_diastolica AS maior_diastolica,
    mpa.data_consulta AS data_maior_pa,

    -- BLOCO: Hipertensão (Análise Completa)
    hgc.qtd_pas_alteradas,
    hgc.teve_pa_grave,
    hgc.total_medicoes_pa,
    hgc.percentual_pa_controlada,
    hgc.data_ultima_pa,
    hgc.ultima_sistolica,
    hgc.ultima_diastolica,
    hgc.ultima_pa_controlada,
    hgc.tem_anti_hipertensivo,
    hgc.tem_anti_hipertensivo_seguro,
    hgc.tem_anti_hipertensivo_contraindicado,
    hgc.anti_hipertensivos_seguros,
    hgc.anti_hipertensivos_contraindicados,
    hgc.tem_encaminhamento_has,
    hgc.data_primeiro_encaminhamento_has,
    hgc.provavel_hipertensa_sem_diagnostico,

    -- BLOCO: Diabetes
    pad.tem_antidiabetico,
    pad.antidiabeticos_lista,

    -- BLOCO: Outros
    paas.tem_prescricao_aas,
    og.tem_obesidade,
    dap.tem_aparelho_pa_dispensado,

    -- BLOCO: Unidades
    cea.unidade_vinculo_cadastro,
    cea.unidade_atendimento,
    cea.ap,
    cea.id_cnes

FROM filtrado f

-- JOINs com TODAS as CTEs
LEFT JOIN pacientes_info pi ON f.id_paciente = pi.id_paciente
LEFT JOIN pacientes_todos_cns ptcns ON f.id_paciente = ptcns.id_paciente
LEFT JOIN categorias_risco_gestacional crg ON f.id_gestacao = crg.id_gestacao
LEFT JOIN condicoes_flags cf ON f.id_gestacao = cf.id_gestacao
LEFT JOIN equipe_durante_final edf ON f.id_gestacao = edf.id_gestacao
LEFT JOIN mudanca_equipe me ON f.id_gestacao = me.id_gestacao
LEFT JOIN partos_associados pa ON f.id_gestacao = pa.id_gestacao
LEFT JOIN consultas_prenatal cp ON f.id_gestacao = cp.id_gestacao
LEFT JOIN ultima_consulta_prenatal ucp ON f.id_gestacao = ucp.id_gestacao
LEFT JOIN status_prescricoes sp ON f.id_gestacao = sp.id_gestacao
LEFT JOIN visitas_acs_por_gestacao vacs ON f.id_gestacao = vacs.id_gestacao
LEFT JOIN ultima_visita_acs uvacs ON f.id_gestacao = uvacs.id_gestacao
LEFT JOIN maior_pa_por_gestacao mpa ON f.id_gestacao = mpa.id_gestacao
LEFT JOIN hipertensao_gestacional_completa hgc ON f.id_gestacao = hgc.id_gestacao
LEFT JOIN prescricoes_antidiabeticos pad ON f.id_gestacao = pad.id_gestacao
LEFT JOIN prescricao_aas paas ON f.id_gestacao = paas.id_gestacao
LEFT JOIN obesidade_gestante og ON f.id_gestacao = og.id_gestacao
LEFT JOIN dispensacao_aparelho_pa dap ON f.id_gestacao = dap.id_gestacao
LEFT JOIN cad_e_atd cea ON f.id_paciente = cea.id_paciente
```

**Resultado Final:**
```
┌───────────────────────────────────────────────────────┐
│      UMA LINHA POR GESTAÇÃO COM TUDO!                 │
├───────────────────────────────────────────────────────┤
│                                                       │
│  Gestação: 12345-1 (Maria Silva)                     │
│  ├─ Demografia: 28 anos, parda                       │
│  ├─ Gestação: 32 semanas, 2º trim                    │
│  ├─ Riscos: DIABETES; GEMELARIDADE                   │
│  ├─ Condições: diabetes_gestacional=1                │
│  ├─ Equipe: Equipe Verde / CF Norte                  │
│  ├─ Consultas: 6 consultas, última 15/08             │
│  ├─ Visitas ACS: 4 visitas, última 20/08             │
│  ├─ PA: 145/95 (alterada), 50% controle              │
│  ├─ Medicamentos: METILDOPA                          │
│  ├─ Encaminhamentos: tem_encam_has=1                 │
│  ├─ Prescrições: folico=sim, calcio=sim              │
│  └─ Unidade: CF Norte (8 atendimentos)               │
│                                                       │
└───────────────────────────────────────────────────────┘

TOTAL: 100+ colunas consolidadas!
```

---

## 🎓 Glossário de Termos

| Termo | Significado |
|-------|-------------|
| **HAS** | Hipertensão Arterial Sistêmica |
| **PA** | Pressão Arterial |
| **ACS** | Agente Comunitário de Saúde |
| **SISREG** | Sistema de Regulação (encaminhamentos) |
| **SER** | Sistema Estadual de Regulação |
| **VITAI** | Sistema hospitalar (partos) |
| **VITACARE** | Sistema da APS (consultas) |
| **IECA** | Inibidor da Enzima Conversora de Angiotensina |
| **BRA** | Bloqueador do Receptor de Angiotensina |
| **DPP** | Data Provável do Parto |
| **IG** | Idade Gestacional |
| **CNS** | Cartão Nacional de Saúde |
| **CNES** | Cadastro Nacional de Estabelecimentos de Saúde |
| **AP** | Área Programática |

---

## 📚 Conceitos-Chave

### Por quê "Linha do Tempo"?
```
Este arquivo consolida TODA a trajetória da gestante
em UMA ÚNICA LINHA, permitindo análises como:

  • Qual o perfil de risco?
  • O acompanhamento está adequado?
  • Há subdiagnósticos?
  • A unidade está funcionando?
  • Quais gestantes precisam de intervenção urgente?

É o "DATAMART" final para dashboards e relatórios!
```

### Flags vs Categorias
```
FLAGS (0/1):
  • Simples, binário
  • Usado em condições específicas
  • Fácil de filtrar e contar

  Exemplo: diabetes_previo = 1

CATEGORIAS (texto):
  • Mais descritivo
  • Agrupa múltiplos CIDs
  • Usado em análises qualitativas

  Exemplo: categorias_risco = "DIABETES; NEFROPATIAS"
```

### LEFT JOIN vs INNER JOIN
```
Todo este arquivo usa LEFT JOIN!

Por quê?
  • Nem toda gestação tem TUDO
  • Gestante sem consulta? = NULL (mas aparece)
  • Gestante sem visita ACS? = NULL (mas aparece)
  • Queremos VER gestações com problemas!

INNER JOIN excluiria gestantes com dados faltantes
→ Perderíamos casos que precisam atenção!
```

---

**Última atualização:** 2024-12-10
**Versão:** 1.0
**Autor:** Sistema de Documentação - Claude Code
**Nota:** Este é o arquivo MAIS COMPLEXO dos três, com mais de 40 CTEs!
