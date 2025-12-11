# 📚 Documentação Lógica - Atendimentos Pré-Natal APS

## 🎯 Visão Geral do Sistema

Este documento explica a lógica completa do sistema de rastreamento de atendimentos pré-natais na Atenção Primária à Saúde (APS).

### Objetivo Principal
Criar um **snapshot histórico** dos atendimentos de pré-natal realizados durante gestações ativas, incluindo medições antropométricas, prescrições e evolução clínica.

### Fluxo Macro do Sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUXO DE PROCESSAMENTO                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. BUSCAR GESTAÇÕES DO SNAPSHOT                               │
│     ↓                                                           │
│  2. CALCULAR MEDIDAS INICIAIS (Peso + Altura)                  │
│     ↓                                                           │
│  3. CALCULAR IMC INICIAL                                       │
│     ↓                                                           │
│  4. FILTRAR ATENDIMENTOS PRÉ-NATAL                             │
│     ↓                                                           │
│  5. ASSOCIAR ATENDIMENTOS ÀS GESTAÇÕES                         │
│     ↓                                                           │
│  6. AGREGAR PRESCRIÇÕES                                        │
│     ↓                                                           │
│  7. ENRIQUECER COM CÁLCULOS (Ganho de Peso, IMC)              │
│     ↓                                                           │
│  8. GERAR SNAPSHOT DE CONSULTAS                                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📋 Detalhamento das CTEs (Common Table Expressions)

### 1️⃣ CTE: `marcadores_temporais`

**Objetivo:** Buscar as gestações do snapshot gerado anteriormente (apenas gestações ativas e em puerpério).

**Pseudocódigo:**
```
PARA CADA gestacao EM _gestacoes_historico:
    SE gestacao.data_snapshot = data_referencia:
        RETORNAR:
            - id_gestacao
            - id_paciente
            - cpf, nome
            - numero_gestacao
            - idade_gestante
            - data_inicio
            - data_fim
            - data_fim_efetiva
            - fase_atual
FIM
```

**Diagrama de Dependência:**
```
┌──────────────────────────────────────┐
│  _gestacoes_historico                │
│  (Gerado pelo arquivo anterior)      │
│                                      │
│  • Gestação 1 (snapshot: 2024-07-01) │
│  • Gestação 2 (snapshot: 2024-07-01) │
│  • Gestação 3 (snapshot: 2024-08-01) │
└──────────────┬───────────────────────┘
               │
               │ FILTRO: data_snapshot = data_referencia
               ↓
┌──────────────────────────────────────┐
│     marcadores_temporais             │
│  (Apenas do snapshot específico)     │
│                                      │
│  • Gestação 1 ✓                      │
│  • Gestação 2 ✓                      │
└──────────────────────────────────────┘
```

---

## 🔍 BLOCO 1: Cálculo de Medidas Iniciais

Este bloco calcula o **peso** e **altura** de referência para cada gestação, que serão usados para calcular o IMC inicial e monitorar ganho de peso.

---

### 2️⃣ CTE: `peso_filtrado`

**Objetivo:** Buscar medições de peso em uma janela temporal ao redor do início da gestação.

**Janela Temporal:**
```
┌────────────────────────────────────────────────────────┐
│  JANELA DE BUSCA DE PESO                               │
│                                                        │
│  [data_inicio - 180 dias] até [data_inicio + 84 dias] │
│                                                        │
│  ◄────── 180 dias ──────►│◄──── 84 dias ──────►      │
│                          │                             │
│                    data_inicio                         │
│                                                        │
│  Por quê essa janela?                                 │
│  • 180 dias ANTES: capturar peso pré-gestacional      │
│  • 84 dias DEPOIS: peso do 1º trimestre               │
│  • Total: 264 dias de janela                          │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA gestacao EM marcadores_temporais:
    PARA CADA episodio EM episodios_assistenciais:
        SE episodio.id_paciente = gestacao.id_paciente:
            SE episodio.peso NÃO É NULL:
                SE episodio.entrada_data ENTRE [inicio-180, inicio+84]:

                    dias_diferenca = episodio.entrada_data - gestacao.data_inicio

                    RETORNAR:
                        - id_gestacao
                        - id_paciente
                        - entrada_data
                        - peso
                        - dias_diferenca
FIM
```

**Exemplo Visual:**
```
Gestação de Maria (início: 2024-01-15)
═══════════════════════════════════════════════════════

Timeline de Busca:
═══════════════════════════════════════════════════════
2023-07-18        2024-01-15        2024-04-08
    │                 │                 │
    │◄── 180 dias ───►│◄─── 84 dias ──►│
    │                 │                 │
    └─ INÍCIO ────────┴─ INÍCIO ───────┴─ FIM
       janela      data_inicio       janela

Pesos Encontrados:
  2023-08-10: 65kg (dias_diferenca: -158) ✓
  2023-12-20: 67kg (dias_diferenca: -26)  ✓
  2024-01-10: 68kg (dias_diferenca: -5)   ✓ (mais próximo!)
  2024-02-15: 70kg (dias_diferenca: +31)  ✓
  2024-05-01: 72kg (dias_diferenca: +107) ✗ (fora da janela)

Por quê 180 dias antes?
→ Capturar peso pré-gestacional
→ Ideal para calcular ganho de peso total
```

---

### 3️⃣ CTE: `peso_proximo_inicio`

**Objetivo:** Para cada gestação, selecionar o peso **mais próximo** da data de início.

**Pseudocódigo:**
```
PARA CADA peso EM peso_filtrado:

    // Calcular ranking baseado em proximidade
    ranking = ROW_NUMBER() PARTICIONADO por id_gestacao
              ORDENADO por ABS(dias_diferenca)

    SE ranking = 1:
        RETORNAR peso
FIM
```

**Exemplo Visual:**
```
ANTES (peso_filtrado):
┌──────────────────────────────────────────┐
│ Gestação de Maria                        │
│                                          │
│  2023-08-10: 65kg (dif: -158) → |158|  │
│  2023-12-20: 67kg (dif: -26)  → |26|   │
│  2024-01-10: 68kg (dif: -5)   → |5|  ← MENOR! │
│  2024-02-15: 70kg (dif: +31)  → |31|   │
└──────────────────────────────────────────┘

DEPOIS (peso_proximo_inicio):
┌──────────────────────────────────────────┐
│ Gestação de Maria                        │
│                                          │
│  2024-01-10: 68kg ✓                     │
│  (Apenas o mais próximo do início)      │
└──────────────────────────────────────────┘

Lógica ABS (valor absoluto):
  • Ignora se é antes ou depois
  • Importa apenas a PROXIMIDADE
  • -5 dias tem prioridade sobre +31 dias
```

---

### 4️⃣ CTE: `alturas_filtradas`

**Objetivo:** Buscar TODAS as medições de altura da paciente no histórico clínico.

**Janela Temporal:**
```
┌────────────────────────────────────────────────────────┐
│  JANELA DE BUSCA DE ALTURA                             │
│                                                        │
│  Todo o histórico disponível da paciente               │
│  (sem limite de data)                                  │
│                                                        │
│  Por quê sem limite?                                  │
│  • Altura é estável (não muda durante gestação)       │
│  • Quanto mais medições, melhor a precisão da moda    │
│  • Podemos usar medições de anos anteriores           │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA gestacao EM marcadores_temporais:
    PARA CADA episodio EM episodios_assistenciais:
        SE episodio.id_paciente = gestacao.id_paciente:
            SE episodio.altura NÃO É NULL:

                // Calcular relação temporal
                dias_antes_inicio = gestacao.data_inicio - episodio.entrada_data
                dias_apos_inicio = episodio.entrada_data - gestacao.data_fim_efetiva

                RETORNAR:
                    - id_gestacao
                    - id_paciente
                    - altura
                    - dias_antes_inicio
                    - dias_apos_inicio
FIM
```

**Exemplo Visual:**
```
Histórico de Alturas de Maria:
═══════════════════════════════════════════════════════

2020-03-15: 165cm (4 anos antes)
2021-08-20: 165cm (2 anos antes)
2022-11-10: 165cm (1 ano antes)
2023-02-05: 164cm (erro de medição?)
2023-09-12: 165cm (4 meses antes)
2024-01-20: 165cm (durante gestação)
2024-03-15: 165cm (durante gestação)

Todas as medições são incluídas!
Não há filtro temporal nesta etapa.
```

---

### 5️⃣ CTE: `altura_preferencial`

**Objetivo:** Calcular a **moda** (valor mais frequente) das alturas, priorizando medições de até 1 ano antes do início da gestação.

**Regras de Inclusão:**
- Até **365 dias ANTES** do início da gestação
- **Antes ou no máximo ATÉ** o fim da gestação (não depois)

**Pseudocódigo:**
```
PARA CADA altura EM alturas_filtradas:

    SE dias_antes_inicio <= 365:        // Até 1 ano antes
        SE dias_apos_inicio <= 0:       // Não depois do fim

            // Agrupar por altura e contar frequência
            AGRUPAR por (id_gestacao, id_paciente, altura)
            freq = COUNT(*)

            // Ordenar por frequência
            ranking = ROW_NUMBER() PARTICIONADO por id_gestacao
                      ORDENADO por freq DESC

            SE ranking = 1:
                RETORNAR:
                    - id_gestacao
                    - id_paciente
                    - altura_cm
                    - freq (número de vezes que apareceu)
FIM
```

**Exemplo Visual:**
```
Gestação de Ana (início: 2024-01-15)
═══════════════════════════════════════════════════════

Alturas DENTRO da janela preferencial (1 ano antes):
  2023-02-10: 162cm ✓
  2023-05-20: 162cm ✓
  2023-08-15: 162cm ✓
  2023-11-01: 163cm ✓ (erro de medição?)
  2024-01-20: 162cm ✓

Alturas FORA da janela (mais de 1 ano antes):
  2022-03-10: 162cm ✗ (excluída)
  2021-08-15: 162cm ✗ (excluída)

Contagem de Frequências:
┌──────────────────────────────────────┐
│ Altura | Frequência | Ranking       │
├──────────────────────────────────────┤
│ 162cm  |     4      |   1  ← MODA  │
│ 163cm  |     1      |   2          │
└──────────────────────────────────────┘

altura_preferencial = 162cm ✓
(Valor que apareceu mais vezes)
```

---

### 6️⃣ CTE: `altura_fallback`

**Objetivo:** Calcular a moda de altura **sem restrição temporal**, para casos onde não há medições no período preferencial.

**Pseudocódigo:**
```
PARA CADA altura EM alturas_filtradas:

    // SEM FILTROS TEMPORAIS
    // Usa TODAS as medições disponíveis

    AGRUPAR por (id_gestacao, id_paciente, altura)
    freq = COUNT(*)

    ranking = ROW_NUMBER() PARTICIONADO por id_gestacao
              ORDENADO por freq DESC

    SE ranking = 1:
        RETORNAR:
            - id_gestacao
            - id_paciente
            - altura_cm
            - freq
FIM
```

**Exemplo Visual:**
```
Cenário de Fallback (gestante nova no sistema):
═══════════════════════════════════════════════════════

Gestação de Carla (início: 2024-06-01)

Alturas DENTRO da janela preferencial (1 ano):
  Nenhuma! ✗

Alturas em TODO o histórico:
  2020-03-15: 158cm ✓
  2020-08-20: 158cm ✓
  2021-02-10: 158cm ✓
  2023-11-15: 157cm ✓ (erro?)

Contagem (SEM filtro temporal):
┌──────────────────────────────────────┐
│ Altura | Frequência | Ranking       │
├──────────────────────────────────────┤
│ 158cm  |     3      |   1  ← FALLBACK │
│ 157cm  |     1      |   2             │
└──────────────────────────────────────┘

altura_fallback = 158cm ✓
(Única opção disponível)
```

---

### 7️⃣ CTE: `altura_moda_completa`

**Objetivo:** Combinar altura preferencial e fallback em uma única tabela.

**Estratégia:**
1. Usar altura **preferencial** se disponível
2. Usar altura **fallback** apenas se preferencial não existir

**Pseudocódigo:**
```
// Parte 1: Usar preferenciais
PARA CADA altura EM altura_preferencial ONDE ranking = 1:
    RETORNAR altura

UNION ALL

// Parte 2: Usar fallback APENAS se não tem preferencial
PARA CADA altura EM altura_fallback:
    SE altura.id_gestacao NÃO ESTÁ EM altura_preferencial:
        RETORNAR altura
FIM
```

**Exemplo Visual:**
```
┌────────────────────────────────────────────────────────┐
│                ESTRATÉGIA DE UNIÃO                     │
├────────────────────────────────────────────────────────┤
│                                                        │
│  Gestação A:                                          │
│    altura_preferencial = 162cm (disponível)           │
│    altura_fallback = 162cm                            │
│    → ESCOLHE: preferencial (162cm) ✓                  │
│                                                        │
│  Gestação B:                                          │
│    altura_preferencial = NULL (não disponível)        │
│    altura_fallback = 158cm                            │
│    → ESCOLHE: fallback (158cm) ✓                      │
│                                                        │
│  Gestação C:                                          │
│    altura_preferencial = 165cm (disponível)           │
│    altura_fallback = 164cm                            │
│    → ESCOLHE: preferencial (165cm) ✓                  │
│    → IGNORA: fallback                                 │
│                                                        │
└────────────────────────────────────────────────────────┘

Resultado: Uma altura por gestação, sempre a melhor disponível!
```

---

### 8️⃣ CTE: `peso_altura_inicio`

**Objetivo:** Calcular o **IMC inicial** e sua classificação para cada gestação.

**Fórmula do IMC:**
```
┌────────────────────────────────────────┐
│         CÁLCULO DO IMC                 │
├────────────────────────────────────────┤
│                                        │
│  IMC = peso (kg) / altura² (m)        │
│                                        │
│  Exemplo:                              │
│    Peso: 68 kg                         │
│    Altura: 1.65 m                      │
│    IMC = 68 / (1.65)²                 │
│    IMC = 68 / 2.7225                  │
│    IMC = 24.98 ≈ 25.0                 │
│                                        │
└────────────────────────────────────────┘
```

**Classificação do IMC:**
```
┌────────────────────────────────────────┐
│    TABELA DE CLASSIFICAÇÃO IMC         │
├────────────────────────────────────────┤
│                                        │
│  IMC < 18.0  →  Baixo peso            │
│  18.0 ≤ IMC < 25.0  →  Eutrófico      │
│  25.0 ≤ IMC < 30.0  →  Sobrepeso      │
│  IMC ≥ 30.0  →  Obesidade             │
│                                        │
└────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA gestacao:
    peso = peso_proximo_inicio.peso
    altura_m = altura_moda_completa.altura_cm / 100

    // Calcular IMC
    imc_inicio = ROUND(peso / POW(altura_m, 2), 1)

    // Classificar IMC
    SE imc_inicio < 18:
        classificacao = 'Baixo peso'
    SENÃO SE imc_inicio < 25:
        classificacao = 'Eutrófico'
    SENÃO SE imc_inicio < 30:
        classificacao = 'Sobrepeso'
    SENÃO:
        classificacao = 'Obesidade'

    RETORNAR:
        - id_gestacao
        - id_paciente
        - peso
        - altura_m
        - imc_inicio
        - classificacao_imc_inicio
FIM
```

**Exemplo Visual:**
```
Gestação de Maria
═══════════════════════════════════════════════════════

Medidas Iniciais:
  peso_inicio: 68 kg
  altura: 162 cm → 1.62 m

Cálculo do IMC:
  IMC = 68 / (1.62)²
  IMC = 68 / 2.6244
  IMC = 25.9

Classificação:
  25.9 está entre 25.0 e 30.0
  → classificacao_imc_inicio = 'Sobrepeso' ✓

═══════════════════════════════════════════════════════

Representação Visual:
────────────────────────────────────────────────────
0        18       25       30               40
│──────┼────────┼────────┼─────────────────│
Baixo  Eutrófico Sobrepeso    Obesidade
Peso               ▲
                   │
               Maria (25.9)
```

---

## 📝 BLOCO 2: Coleta de Atendimentos

Este bloco filtra e processa os atendimentos de pré-natal realizados na APS.

---

### 9️⃣ CTE: `atendimentos_filtrados`

**Objetivo:** Filtrar apenas atendimentos de **pré-natal na APS** (Atenção Primária à Saúde).

**Critérios de Filtro:**
```
┌────────────────────────────────────────────────────────┐
│         CRITÉRIOS DE INCLUSÃO DE ATENDIMENTOS          │
├────────────────────────────────────────────────────────┤
│                                                        │
│  ✓ Subtipo = 'Atendimento SOAP'                       │
│  ✓ Fornecedor = 'vitacare' (sistema APS)              │
│  ✓ CID situação = 'ATIVO'                             │
│  ✓ Profissional da APS (lista de especialidades)      │
│                                                        │
│  Especialidades Incluídas:                            │
│  • Médico da estratégia de saúde da família           │
│  • Enfermeiro da estratégia saúde da família          │
│  • Médico Clínico                                     │
│  • Médico Ginecologista e Obstetra                    │
│  • Enfermeiro obstétrico                              │
│  • Médico de Família e Comunidade                     │
│  • ... (13 categorias no total)                       │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA episodio EM episodios_assistenciais:

    SE episodio.subtipo = 'Atendimento SOAP':
        SE LOWER(episodio.fornecedor) = 'vitacare':
            SE episodio.profissional_categoria NA lista_aps:

                // Agregar medidas do episódio
                altura = ANY_VALUE(episodio.altura)
                peso = ANY_VALUE(episodio.peso)
                imc = ANY_VALUE(episodio.imc)
                pressao_sistolica = ANY_VALUE(episodio.pressao_sistolica)
                pressao_diastolica = ANY_VALUE(episodio.pressao_diastolica)
                motivo = ANY_VALUE(episodio.motivo_atendimento)
                desfecho = ANY_VALUE(episodio.desfecho_atendimento)

                // Concatenar CIDs ativos
                cid_string = STRING_AGG(condicoes.id, ', ')

                RETORNAR:
                    - id_hci
                    - id_paciente
                    - entrada_data
                    - estabelecimento, estabelecimento_tipo
                    - profissional_nome, profissional_categoria
                    - altura, peso, imc
                    - pressao_sistolica, pressao_diastolica
                    - motivo_atendimento, desfecho_atendimento
                    - cid_string (todos os CIDs concatenados)
FIM
```

**Exemplo Visual:**
```
ANTES (todos os episódios):
┌──────────────────────────────────────────────────────┐
│ Episódio 1: Atendimento SOAP / vitacare / ESF    ✓  │
│ Episódio 2: Atendimento SOAP / vitacare / ESF    ✓  │
│ Episódio 3: Consulta / vitacare / Cardiologista  ✗  │
│ Episódio 4: Atendimento SOAP / smsrio / ESF      ✗  │
│ Episódio 5: Urgência / vitacare / ESF            ✗  │
└──────────────────────────────────────────────────────┘
       │
       │ FILTROS APLICADOS
       ↓
┌──────────────────────────────────────────────────────┐
│        atendimentos_filtrados                        │
│  (Apenas pré-natal APS)                              │
│                                                      │
│  Episódio 1 ✓                                        │
│  Episódio 2 ✓                                        │
└──────────────────────────────────────────────────────┘

Por quê 'vitacare'?
→ Sistema de prontuário eletrônico da APS do Rio
→ Garante que são atendimentos da Atenção Primária
```

---

### 🔟 CTE: `atendimentos_gestacao`

**Objetivo:** Associar cada atendimento à sua gestação correspondente e calcular idade gestacional.

**Regras de Associação:**
```
┌────────────────────────────────────────────────────────┐
│      REGRAS DE MATCHING ATENDIMENTO ↔ GESTAÇÃO         │
├────────────────────────────────────────────────────────┤
│                                                        │
│  1. Mesma paciente (id_paciente)                      │
│  2. Data do atendimento ENTRE:                        │
│     • data_inicio da gestação                         │
│     • data_fim_efetiva (ou data_referencia se NULL)   │
│                                                        │
│  Atendimentos FORA da gestação são descartados!       │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Cálculo de IG e Trimestre:**
```
┌────────────────────────────────────────────────────────┐
│         IDADE GESTACIONAL (IG) E TRIMESTRE             │
├────────────────────────────────────────────────────────┤
│                                                        │
│  IG = (data_consulta - data_inicio) em SEMANAS        │
│                                                        │
│  Trimestre:                                           │
│    IG ≤ 13 semanas  →  1º trimestre                   │
│    14 ≤ IG ≤ 27     →  2º trimestre                   │
│    IG ≥ 28          →  3º trimestre                   │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA atendimento EM atendimentos_filtrados:
    PARA CADA gestacao EM marcadores_temporais:

        SE atendimento.id_paciente = gestacao.id_paciente:
            SE atendimento.entrada_data ENTRE [inicio, fim_efetivo]:

                // Calcular IG na consulta
                ig_consulta = DATE_DIFF(entrada_data, data_inicio, WEEK)

                // Determinar trimestre
                SE ig_consulta <= 13:
                    trimestre = 1
                SENÃO SE ig_consulta <= 27:
                    trimestre = 2
                SENÃO:
                    trimestre = 3

                RETORNAR:
                    - atendimento (todos os campos)
                    - id_gestacao
                    - data_inicio, data_fim_efetiva, fase_atual
                    - ig_consulta
                    - trimestre_consulta
FIM
```

**Exemplo Visual:**
```
Gestação de Maria (2024-01-15 a 2024-09-20)
═══════════════════════════════════════════════════════

Timeline:
═══════════════════════════════════════════════════════
2024-01-15          2024-05-15          2024-09-20
    │                   │                   │
    ├───────────────────┼───────────────────┤
    │                   │                   │
 INÍCIO             MEIO                  FIM

Atendimentos:
  2023-12-01: Consulta → ANTES da gestação       ✗
  2024-02-10: Consulta → IG = 4 sem (1º trim)   ✓
  2024-04-20: Consulta → IG = 14 sem (2º trim)  ✓
  2024-07-15: Consulta → IG = 26 sem (2º trim)  ✓
  2024-09-05: Consulta → IG = 34 sem (3º trim)  ✓
  2024-10-15: Consulta → DEPOIS da gestação      ✗

Apenas consultas DURANTE a gestação são incluídas!
```

---

### 1️⃣1️⃣ CTE: `prescricoes_aggregadas`

**Objetivo:** Agregar todas as prescrições de cada atendimento em uma única string.

**Pseudocódigo:**
```
PARA CADA episodio EM episodios_assistenciais:

    SE episodio.subtipo = 'Atendimento SOAP':
        SE episodio.fornecedor = 'vitacare':

            // Concatenar nomes das prescrições
            prescricoes_texto = STRING_AGG(
                prescricoes.nome,
                ', '  // separador
            )

            RETORNAR:
                - id_hci
                - prescricoes (texto concatenado)
FIM
```

**Exemplo Visual:**
```
ANTES (array de prescrições):
┌──────────────────────────────────────────────────────┐
│ Atendimento #1001                                    │
│                                                      │
│ prescricoes: [                                       │
│   { nome: "Sulfato Ferroso 40mg" },                 │
│   { nome: "Ácido Fólico 5mg" },                     │
│   { nome: "Vitamina D 1000UI" }                     │
│ ]                                                    │
└──────────────────────────────────────────────────────┘
       │
       │ STRING_AGG
       ↓
┌──────────────────────────────────────────────────────┐
│ Atendimento #1001                                    │
│                                                      │
│ prescricoes: "Sulfato Ferroso 40mg,                  │
│               Ácido Fólico 5mg,                      │
│               Vitamina D 1000UI"                     │
└──────────────────────────────────────────────────────┘

Facilita leitura e visualização das prescrições!
```

---

### 1️⃣2️⃣ CTE: `consultas_enriquecidas`

**Objetivo:** Combinar todas as informações e calcular métricas finais (ganho de peso, IMC da consulta, número da consulta).

**Cálculos Principais:**
```
┌────────────────────────────────────────────────────────┐
│              CÁLCULOS FINAIS                           │
├────────────────────────────────────────────────────────┤
│                                                        │
│  numero_consulta:                                     │
│    ROW_NUMBER() por gestação                          │
│    Ordenado por data da consulta                      │
│    → 1ª consulta, 2ª consulta, 3ª consulta...        │
│                                                        │
│  ganho_peso_acumulado:                                │
│    peso_consulta - peso_inicio                        │
│    Ex: 72kg - 68kg = +4kg                             │
│                                                        │
│  imc_consulta:                                        │
│    peso_consulta / (altura)²                          │
│    Ex: 72 / (1.62)² = 27.4                            │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA atendimento EM atendimentos_gestacao:

    // Buscar dados iniciais
    peso_inicio = peso_altura_inicio.peso
    altura_m = peso_altura_inicio.altura_m
    imc_inicio = peso_altura_inicio.imc_inicio
    classificacao_inicio = peso_altura_inicio.classificacao_imc_inicio

    // Buscar prescrições
    prescricoes = prescricoes_aggregadas.prescricoes

    // Calcular número da consulta
    numero_consulta = ROW_NUMBER() PARTICIONADO por id_gestacao
                      ORDENADO por entrada_data

    // Calcular ganho de peso
    ganho_peso_acumulado = atendimento.peso - peso_inicio

    // Calcular IMC atual
    imc_consulta = ROUND(atendimento.peso / POW(altura_m, 2), 1)

    RETORNAR:
        - atendimento (todos os campos)
        - prescricoes
        - numero_consulta
        - peso_inicio, altura_m, imc_inicio, classificacao_imc_inicio
        - ganho_peso_acumulado
        - imc_consulta
FIM
```

**Exemplo Visual - Evolução de uma Gestação:**
```
Gestação de Maria (IMC inicial: 25.9 - Sobrepeso)
═══════════════════════════════════════════════════════

┌────────────────────────────────────────────────────┐
│  Consulta 1 (IG: 4 semanas)                        │
│  Data: 2024-02-10                                  │
│  Peso: 68.5 kg → Ganho: +0.5 kg                   │
│  IMC: 26.1                                         │
│  Prescrições: Ácido Fólico 5mg                     │
├────────────────────────────────────────────────────┤
│  Consulta 2 (IG: 14 semanas)                       │
│  Data: 2024-04-20                                  │
│  Peso: 70.0 kg → Ganho: +2.0 kg                   │
│  IMC: 26.7                                         │
│  Prescrições: Ácido Fólico 5mg, Sulfato Ferroso   │
├────────────────────────────────────────────────────┤
│  Consulta 3 (IG: 26 semanas)                       │
│  Data: 2024-07-15                                  │
│  Peso: 73.5 kg → Ganho: +5.5 kg                   │
│  IMC: 28.0                                         │
│  Prescrições: Sulfato Ferroso, Vitamina D         │
├────────────────────────────────────────────────────┤
│  Consulta 4 (IG: 34 semanas)                       │
│  Data: 2024-09-05                                  │
│  Peso: 76.0 kg → Ganho: +8.0 kg                   │
│  IMC: 28.9                                         │
│  Prescrições: Sulfato Ferroso, Vitamina D         │
└────────────────────────────────────────────────────┘

Gráfico de Ganho de Peso:
──────────────────────────────────────────────────
Ganho (kg)
10 │
 9 │
 8 │                                        ●
 7 │
 6 │
 5 │                           ●
 4 │
 3 │
 2 │              ●
 1 │     ●
 0 │─────┼───────┼────────────┼───────────┼──────
   0     4      14          26          34   IG (sem)
```

---

## 🎯 SELECT FINAL - Montagem do Snapshot de Consultas

**Objetivo:** Gerar snapshot final apenas de consultas em **gestações ativas**.

**Filtro Final:**
```
┌────────────────────────────────────────────────────────┐
│         FILTRO FINAL: fase_atual = 'Gestação'          │
├────────────────────────────────────────────────────────┤
│                                                        │
│  ✓ INCLUI: Consultas de gestações ativas              │
│  ✗ EXCLUI: Consultas de gestações em puerpério        │
│  ✗ EXCLUI: Consultas de gestações encerradas          │
│                                                        │
│  Por quê apenas 'Gestação'?                           │
│  → Foco em acompanhamento pré-natal ativo             │
│  → Puerpério tem acompanhamento diferente             │
│                                                        │
└────────────────────────────────────────────────────────┘
```

**Pseudocódigo:**
```
PARA CADA consulta EM consultas_enriquecidas:

    SE consulta.fase_atual = 'Gestação':

        RETORNAR:
            // Metadados
            - data_snapshot = data_referencia

            // Identificadores
            - id_gestacao
            - id_paciente

            // Informações da consulta
            - data_consulta
            - numero_consulta
            - ig_consulta
            - trimestre_consulta
            - fase_atual

            // Medidas iniciais
            - peso_inicio
            - altura_inicio
            - imc_inicio
            - classificacao_imc_inicio

            // Medidas da consulta
            - peso
            - imc_consulta
            - ganho_peso_acumulado

            // Sinais vitais
            - pressao_sistolica
            - pressao_diastolica

            // Dados clínicos
            - descricao_s (motivo)
            - cid_string
            - desfecho
            - prescricoes

            // Dados do atendimento
            - estabelecimento
            - profissional_nome
            - profissional_categoria

ORDENAR por data_consulta DESC
FIM
```

**Estrutura Final:**
```
┌───────────────────────────────────────────────────────┐
│         SNAPSHOT DE CONSULTAS PRÉ-NATAL               │
│         data_snapshot: 2024-07-01                     │
├───────────────────────────────────────────────────────┤
│                                                       │
│  Consulta #4 - Maria Silva (Gestação 12345-1)        │
│  ├─ Data: 2024-06-15 (IG: 22 sem - 2º trimestre)     │
│  ├─ Peso: 72kg (inicio: 68kg) → Ganho: +4kg         │
│  ├─ IMC: 27.4 (inicio: 25.9 - Sobrepeso)            │
│  ├─ PA: 120/80 mmHg                                  │
│  ├─ CIDs: Z321, Z34                                  │
│  ├─ Prescrições: Sulfato Ferroso, Ácido Fólico      │
│  └─ Profissional: Dra. Ana (Enfermeira ESF)         │
│                                                       │
│  Consulta #3 - Ana Costa (Gestação 67890-2)          │
│  ├─ Data: 2024-05-20 (IG: 16 sem - 2º trimestre)     │
│  ├─ Peso: 65kg (inicio: 62kg) → Ganho: +3kg         │
│  ├─ IMC: 24.2 (inicio: 23.1 - Eutrófico)            │
│  ├─ PA: 110/70 mmHg                                  │
│  ├─ CIDs: Z34                                        │
│  ├─ Prescrições: Ácido Fólico 5mg                   │
│  └─ Profissional: Dr. Carlos (Médico ESF)           │
│                                                       │
└───────────────────────────────────────────────────────┘
```

---

## 📊 Resumo do Fluxo Completo

```
┌────────────────────────────────────────────────────────────┐
│                    PIPELINE COMPLETO                       │
└────────────────────────────────────────────────────────────┘

1. BUSCAR GESTAÇÕES
   └─► marcadores_temporais: Gestações do snapshot específico

2. CALCULAR PESO INICIAL
   └─► peso_filtrado: Pesos em janela de -180 a +84 dias
       └─► peso_proximo_inicio: Peso mais próximo do início

3. CALCULAR ALTURA INICIAL
   └─► alturas_filtradas: Todas as alturas disponíveis
       ├─► altura_preferencial: Moda (1 ano antes)
       └─► altura_fallback: Moda (todo histórico)
           └─► altura_moda_completa: União das duas

4. CALCULAR IMC INICIAL
   └─► peso_altura_inicio: IMC e classificação inicial

5. FILTRAR ATENDIMENTOS APS
   └─► atendimentos_filtrados: Apenas pré-natal APS

6. ASSOCIAR ATENDIMENTOS ÀS GESTAÇÕES
   └─► atendimentos_gestacao: Match por paciente e data
       Calcula: IG, trimestre

7. AGREGAR PRESCRIÇÕES
   └─► prescricoes_aggregadas: Concatena prescrições

8. ENRIQUECER E CALCULAR MÉTRICAS
   └─► consultas_enriquecidas: Ganho de peso, IMC atual

9. GERAR SNAPSHOT FINAL
   └─► SELECT FINAL: Apenas fase 'Gestação'
       Ordenado por data_consulta DESC
```

---

## 🔍 Conceitos-Chave Explicados

### Janela de Peso
```
Por quê -180 a +84 dias?
═══════════════════════════════════════════════════

180 dias ANTES:
  • Captura peso pré-gestacional
  • Ideal para avaliar ganho de peso total
  • Permite detectar gestantes com sobrepeso/obesidade

84 dias DEPOIS (12 semanas):
  • Final do 1º trimestre
  • Peso ainda próximo do inicial
  • Minimiza ganho gestacional no cálculo base

Peso mais próximo da data_inicio é o mais representativo!
```

### Moda de Altura
```
Por quê usar MODA ao invés de MÉDIA?
═══════════════════════════════════════════════════

Exemplo de medições:
  162cm, 162cm, 162cm, 162cm, 175cm (erro!)

Média: (162+162+162+162+175) / 5 = 164.6 cm ✗
  → Distorcida pelo erro de medição

Moda: 162cm (valor mais frequente) ✓
  → Robusta a erros isolados
  → Reflete valor real da paciente
```

### Altura Preferencial vs Fallback
```
Por quê preferir medições de 1 ano?
═══════════════════════════════════════════════════

PREFERENCIAL (1 ano):
  ✓ Dados mais recentes
  ✓ Mesmo sistema/equipamento
  ✓ Menor chance de erro técnico

FALLBACK (todo histórico):
  ✓ Pacientes novas no sistema
  ✓ Quando não há dados recentes
  ✓ Melhor que não ter altura
```

### Fase Atual = 'Gestação'
```
Por quê excluir Puerpério?
═══════════════════════════════════════════════════

Pré-natal:
  • Acompanhamento da GESTAÇÃO
  • Medições antropométricas relevantes
  • Prescrições voltadas para gestação

Puerpério:
  • Acompanhamento PÓS-PARTO
  • Medições diferentes (involução uterina, etc)
  • Prescrições diferentes (lactação, etc)

São protocolos clínicos DIFERENTES!
```

---

## ⚠️ Pontos de Atenção

### 1. Qualidade das Medições
```
⚠️ PESO e ALTURA inconsistentes
───────────────────────────────────────────────────

Possíveis problemas:
  • Erros de digitação (175cm → 1750cm)
  • Medições em unidades erradas (libras vs kg)
  • Equipamentos descalibrados

Soluções aplicadas:
  ✓ Usar valor mais PRÓXIMO (peso)
  ✓ Usar valor mais FREQUENTE (altura)
  ✓ Ambos minimizam impacto de erros
```

### 2. Gestações Sem Medidas Iniciais
```
⚠️ Ausência de peso/altura inicial
───────────────────────────────────────────────────

Cenários:
  • Primeira consulta tardia (>12 semanas)
  • Paciente nova no sistema
  • Dados não registrados

Impacto:
  ✗ Sem IMC inicial
  ✗ Sem cálculo de ganho de peso
  ✗ Análise limitada da evolução

Campo ficará NULL no resultado
```

### 3. Múltiplas Medições na Mesma Consulta
```
⚠️ Múltiplos registros de peso/pressão/etc
───────────────────────────────────────────────────

Por quê ocorre?
  • Sistema registra medições em momentos diferentes
  • Aferições repetidas para confirmação
  • Múltiplos profissionais no mesmo atendimento

Solução: ANY_VALUE()
  → Pega qualquer valor disponível
  → Assume que variação intra-consulta é mínima
```

---

## 📈 Exemplo Completo - Caso Real

```
═══════════════════════════════════════════════════════════
CASO: Ana Paula (ID: 67890)
data_referencia: 2024-07-01
═══════════════════════════════════════════════════════════

📋 DADOS DA GESTAÇÃO (de marcadores_temporais)
───────────────────────────────────────────────────────────
id_gestacao: 67890-1
data_inicio: 2024-03-01
data_fim_efetiva: NULL (em andamento)
fase_atual: Gestação
idade_gestante: 32 anos

📊 CÁLCULO DE MEDIDAS INICIAIS
───────────────────────────────────────────────────────────

PESO:
  Janela: 2023-09-02 a 2024-05-24
  Pesos encontrados:
    2023-12-10: 62kg (dif: -81 dias)
    2024-02-20: 63kg (dif: -10 dias) ← MAIS PRÓXIMO ✓
    2024-03-15: 64kg (dif: +14 dias)
  peso_inicio = 63kg

ALTURA:
  Alturas em 1 ano:
    2023-05-10: 158cm
    2023-08-15: 158cm
    2024-01-20: 158cm
    2024-02-28: 159cm (erro?)
  Moda preferencial: 158cm (3x) ✓
  altura_inicio = 1.58m

IMC INICIAL:
  IMC = 63 / (1.58)² = 25.2
  Classificação: Sobrepeso

🏥 ATENDIMENTOS DE PRÉ-NATAL
───────────────────────────────────────────────────────────

Consulta 1: 2024-03-15
  IG: 2 semanas (1º trimestre)
  Peso: 64kg → Ganho: +1kg
  IMC: 25.6
  PA: 115/75 mmHg
  CIDs: Z321
  Prescrições: Ácido Fólico 5mg
  Profissional: Enf. Maria (ESF)

Consulta 2: 2024-04-22
  IG: 7 semanas (1º trimestre)
  Peso: 65kg → Ganho: +2kg
  IMC: 26.0
  PA: 120/80 mmHg
  CIDs: Z321, Z34
  Prescrições: Ácido Fólico 5mg, Sulfato Ferroso 40mg
  Profissional: Dr. João (Médico ESF)

Consulta 3: 2024-06-10
  IG: 14 semanas (2º trimestre)
  Peso: 67kg → Ganho: +4kg
  IMC: 26.8
  PA: 118/78 mmHg
  CIDs: Z34
  Prescrições: Sulfato Ferroso 40mg, Vitamina D 1000UI
  Profissional: Enf. Maria (ESF)

═══════════════════════════════════════════════════════════
RESULTADO FINAL NO SNAPSHOT (2024-07-01)
═══════════════════════════════════════════════════════════

3 consultas incluídas (fase = 'Gestação')
Evolução: +4kg em 14 semanas
IMC: 25.2 → 26.8 (dentro do esperado)
PA: Estável e normal
Prescrições adequadas ao protocolo
```

---

## 🎓 Glossário de Termos

| Termo | Significado |
|-------|-------------|
| **APS** | Atenção Primária à Saúde (rede básica) |
| **SOAP** | Subjetivo, Objetivo, Avaliação, Plano (método de registro) |
| **ESF** | Estratégia Saúde da Família |
| **IMC** | Índice de Massa Corporal (peso/altura²) |
| **IG** | Idade Gestacional (em semanas) |
| **PA** | Pressão Arterial (sistólica/diastólica) |
| **Moda** | Valor mais frequente em um conjunto de dados |
| **Fallback** | Alternativa quando opção preferencial não está disponível |
| **ANY_VALUE** | Pega qualquer valor disponível (usado para agregações) |
| **STRING_AGG** | Concatena múltiplos valores em uma única string |

---

## 📚 Referências e Observações

### Parâmetros Clínicos
- **Janela de peso**: -180 a +84 dias do início
- **Janela de altura preferencial**: 1 ano antes do início
- **Trimestres**: 1º (0-13), 2º (14-27), 3º (28+) semanas
- **Classificação IMC**: <18 (baixo), 18-25 (eutrófico), 25-30 (sobrepeso), ≥30 (obesidade)

### Decisões de Design
1. **Peso mais próximo** do início (não médio ou moda)
2. **Altura moda** com preferência para último ano
3. **Fallback de altura** para todo histórico se necessário
4. **Apenas fase 'Gestação'** no resultado final
5. **ANY_VALUE** para medições múltiplas na mesma consulta
6. **Filtro de especialidades APS** para garantir atenção primária

### Fórmulas Utilizadas
```
IMC = peso (kg) / [altura (m)]²

Ganho de Peso = peso_consulta - peso_inicio

IG (semanas) = (data_consulta - data_inicio) / 7
```

---

**Última atualização:** 2024-12-10
**Versão:** 1.0
**Autor:** Sistema de Documentação - Claude Code
