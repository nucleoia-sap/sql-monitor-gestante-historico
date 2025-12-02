# Sistema Completo de Histórico de Pré-Natal

## Visão Geral

Sistema parametrizado para reconstrução histórica completa do acompanhamento pré-natal na rede municipal de saúde do Rio de Janeiro. Permite análise temporal de todos os componentes do cuidado pré-natal através de snapshots em datas específicas.

## Arquitetura do Pipeline

```
data_referencia → proced_1_gestacoes_historico
                      ↓ gera _gestacoes_historico
                      ↓
                  proced_2_atd_prenatal_aps_historico
                      ↓ gera _atendimentos_prenatal_aps_historico
                      ↓
    ┌─────────────────┼─────────────────┐
    ↓                 ↓                 ↓
proced_3         proced_4         proced_5
visitas_acs   consultas_emerg  encaminhamentos
    ↓                 ↓                 ↓
    └─────────────────┼─────────────────┘
                      ↓
              proced_6_linha_tempo_historico
                      ↓
          _linha_tempo_historico (agregação final)
```

## Procedimentos Parametrizados

### 1. **proced_1_gestacoes_historico**(data_referencia DATE)
**Arquivo**: `gestante_historico.sql`
**Saída**: `_gestacoes_historico`
**Função**: Identifica e classifica gestações baseado em CIDs (Z32.1, Z34%, Z35%)

**Alterações da versão original**:
- 8 substituições de CURRENT_DATE() por `data_referencia`
- Adiciona coluna `data_snapshot`
- Fonte inalterada: `episodio_assistencial` (dados brutos)

**Lógica de negócio**:
- Agrupa inícios de gestação com janela de 60 dias
- Auto-encerra após 299 dias se sem data_fim
- Classifica fase: Gestação/Puerpério/Encerrada
- Calcula DPP (data provável do parto)

### 2. **proced_2_atd_prenatal_aps_historico**(data_referencia DATE)
**Arquivo**: `2_atd_prenatal_aps_historico.sql`
**Saída**: `_atendimentos_prenatal_aps_historico`
**Função**: Atendimentos SOAP em APS com medidas antropométricas

**Dependência**: `_gestacoes_historico WHERE data_snapshot = data_referencia`

**Alterações**:
- 2 substituições de CURRENT_DATE()
- Fonte alterada: `_gestacoes` → `_gestacoes_historico`
- Adiciona filtro `WHERE data_snapshot = data_referencia`

**Lógica de negócio**:
- Peso inicial: -180 a +84 dias da data_inicio
- Altura: moda entre 1 ano antes e fim da gestação
- IMC e classificação (Baixo peso/Eutrófico/Sobrepeso/Obesidade)
- IG (idade gestacional) e trimestre
- Ganho de peso acumulado

### 3. **proced_3_visitas_acs_gestacao_historico**(data_referencia DATE)
**Arquivo**: `3_visitas_acs_gestacao_historico.sql`
**Saída**: `_visitas_acs_gestacao_historico`
**Função**: Visitas domiciliares por Agentes Comunitários de Saúde

**Dependência**: `_gestacoes_historico WHERE data_snapshot = data_referencia`

**Alterações**:
- 1 substituição de CURRENT_DATE() (linha 59)
- Fonte alterada para `_gestacoes_historico`
- Adiciona coluna `data_snapshot`

**Lógica de negócio**:
- Filtra visitas com subtipo "Visita Domiciliar"
- Profissional: Agente comunitário de saúde
- Numeração sequencial por gestação

### 4. **proced_4_consultas_emergenciais_historico**(data_referencia DATE)
**Arquivo**: `4_consultas_emergenciais_historico.sql`
**Saída**: `_consultas_emergenciais_historico`
**Função**: Atendimentos de urgência/emergência durante gestação

**Dependência**: `_gestacoes_historico WHERE data_snapshot = data_referencia`

**Alterações**:
- 2 substituições de CURRENT_DATE() (linhas 75, 123)
- Fonte alterada para `_gestacoes_historico`
- Adiciona coluna `data_snapshot`

**Lógica de negócio**:
- Prontuário fornecedor: vitai
- Subtipo: Emergência
- Agrega CIDs de emergência
- Calcula idade gestacional no momento da consulta

### 5. **proced_5_encaminhamentos_historico**(data_referencia DATE)
**Arquivo**: `5_encaminhamentos_historico.sql`
**Saída**: `_encaminhamentos_historico`
**Função**: Encaminhamentos SISREG para alto risco

**Dependência**: Nenhuma (reconstrói gestações internamente)

**Alterações**:
- 11 substituições de CURRENT_DATE() (linhas 138, 153, 159, 176, 231 e faixas etárias)
- Lógica interna de identificação de gestações com `data_referencia`
- Adiciona coluna `data_snapshot`

**Lógica de negócio**:
- Identifica gestações por CIDs Z32.1, Z34%, Z35%
- Encaminhamentos para procedimentos específicos (0703844, 0703886, etc.)
- Match por CPF com solicitações SISREG
- Primeira solicitação por gestação

### 6. **proced_6_linha_tempo_historico**(data_referencia DATE)
**Arquivo**: `6_linha_tempo_historico.sql`
**Saída**: `_linha_tempo_historico`
**Função**: Agregação completa com análise de hipertensão, diabetes, riscos

**Dependências**:
- `_gestacoes_historico`
- `_atendimentos_prenatal_aps_historico`
- `_visitas_acs_gestacao_historico`
- `_consultas_emergenciais_historico`

**Alterações**:
- 21 substituições de CURRENT_DATE()
- Todas as fontes alteradas para versões `_historico`
- Todos os JOINs incluem `WHERE data_snapshot = data_referencia`
- Adiciona coluna `data_snapshot` no SELECT final

**Lógica de negócio**:
- **Condições clínicas**: Diabetes (prévio/gestacional), Hipertensão (prévia/pré-eclâmpsia), HIV, Sífilis, Tuberculose
- **Controle pressórico**: Contagem PAs alteradas, PA grave, percentual controlado
- **Medicações**: Anti-hipertensivos (seguros vs contraindicados), Antidiabéticos, AAS
- **Encaminhamentos**: SISREG alto risco, identificação de prováveis hipertensas sem diagnóstico
- **Fatores de risco**: Doença renal, gemelaridade, doenças autoimunes
- **Adequação AAS**: Baseado em fatores de risco para pré-eclâmpsia
- **Dados do parto**: Associação com eventos de parto/aborto
- **Equipes**: Histórico de mudanças de equipe durante pré-natal

## Como Usar

### Execução para Data Específica

```sql
-- Executar TODOS os procedimentos na ordem
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(DATE('2024-10-31'));

-- Consultar resultado final
SELECT * FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = DATE('2024-10-31')
  AND fase_atual = 'Gestação';
```

### Construção de Série Histórica Mensal

```sql
DECLARE data_inicial DATE DEFAULT DATE('2024-01-31');
DECLARE data_final DATE DEFAULT DATE('2024-12-31');
DECLARE data_atual DATE;

SET data_atual = data_inicial;

WHILE data_atual <= data_final DO
    -- Executar pipeline completo
    CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_atual);

    -- Inserir em tabelas acumulativas
    INSERT INTO linha_tempo_historico_acumulado
    SELECT * FROM _linha_tempo_historico;

    -- Próximo mês
    SET data_atual = LAST_DAY(DATE_ADD(data_atual, INTERVAL 1 MONTH));
END WHILE;
```

## Estrutura das Tabelas Históricas

### Particionamento
Todas as tabelas históricas devem usar:
```sql
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual
```

### Principais Tabelas Acumulativas

1. **gestacoes_historico_acumulado**: Snapshots de todas as gestações
2. **atendimentos_prenatal_historico_acumulado**: Snapshots de consultas pré-natal
3. **visitas_acs_historico_acumulado**: Snapshots de visitas domiciliares
4. **consultas_emergenciais_historico_acumulado**: Snapshots de atendimentos de emergência
5. **linha_tempo_historico_acumulado**: Agregação completa com todos os indicadores

## Casos de Uso

### 1. Evolução da Cobertura de Pré-Natal

```sql
SELECT
    data_snapshot,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_consulta,
    COUNT(*) AS total_consultas,
    AVG(numero_consulta) AS media_consultas,
    COUNTIF(numero_consulta >= 6) AS adequacao_6_consultas,
    ROUND(COUNTIF(numero_consulta >= 6) / COUNT(DISTINCT id_gestacao) * 100, 1) AS perc_adequado
FROM atendimentos_prenatal_historico_acumulado
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 2. Análise Temporal de Hipertensão na Gestação

```sql
SELECT
    data_snapshot,
    COUNT(*) AS total_gestantes,
    COUNTIF(hipertensao_total = 1) AS com_diagnostico_hipertensao,
    COUNTIF(provavel_hipertensa_sem_diagnostico = 1) AS provaveis_sem_diagnostico,
    COUNTIF(tem_anti_hipertensivo_seguro = 1) AS com_medicacao_segura,
    COUNTIF(tem_anti_hipertensivo_contraindicado = 1) AS com_medicacao_contraindicada,
    AVG(percentual_pa_controlada) AS media_controle_pa
FROM linha_tempo_historico_acumulado
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 3. Adequação de Prescrição de AAS para Pré-Eclâmpsia

```sql
SELECT
    data_snapshot,
    COUNTIF(tem_indicacao_aas = 1) AS total_com_indicacao,
    COUNTIF(adequacao_aas_pe = 'Adequado - Com AAS') AS adequado_com_aas,
    COUNTIF(adequacao_aas_pe = 'Inadequado - Sem AAS') AS inadequado_sem_aas,
    ROUND(
        COUNTIF(adequacao_aas_pe = 'Adequado - Com AAS') * 100.0 /
        COUNTIF(tem_indicacao_aas = 1), 1
    ) AS percentual_adequacao
FROM linha_tempo_historico_acumulado
WHERE tem_indicacao_aas = 1
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 4. Evolução de Encaminhamentos para Alto Risco

```sql
SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNTIF(encaminhado_sisreg = 'sim') AS total_encaminhadas,
    COUNTIF(tem_encaminhamento_has = 1) AS encaminhadas_hipertensao,
    ROUND(COUNTIF(encaminhado_sisreg = 'sim') / COUNT(*) * 100, 1) AS perc_encaminhadas
FROM linha_tempo_historico_acumulado
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

### 5. Análise de Ganho de Peso por Classificação de IMC

```sql
SELECT
    data_snapshot,
    classificacao_imc_inicio,
    COUNT(*) AS total_gestantes,
    AVG(ganho_peso_acumulado) AS ganho_medio,
    STDDEV(ganho_peso_acumulado) AS desvio_padrao,
    MIN(ganho_peso_acumulado) AS ganho_minimo,
    MAX(ganho_peso_acumulado) AS ganho_maximo
FROM atendimentos_prenatal_historico_acumulado
WHERE ganho_peso_acumulado IS NOT NULL
  AND trimestre_consulta = 3  -- Terceiro trimestre
GROUP BY data_snapshot, classificacao_imc_inicio
ORDER BY data_snapshot, classificacao_imc_inicio;
```

### 6. Cobertura de Visitas ACS

```sql
SELECT
    data_snapshot,
    COUNT(DISTINCT g.id_gestacao) AS total_gestacoes,
    COUNT(DISTINCT v.id_gestacao) AS gestacoes_com_visita,
    ROUND(COUNT(DISTINCT v.id_gestacao) * 100.0 / COUNT(DISTINCT g.id_gestacao), 1) AS perc_cobertura_visita,
    AVG(total_visitas) AS media_visitas_por_gestacao
FROM gestacoes_historico_acumulado g
LEFT JOIN (
    SELECT data_snapshot, id_gestacao, COUNT(*) AS total_visitas
    FROM visitas_acs_historico_acumulado
    GROUP BY data_snapshot, id_gestacao
) v ON g.data_snapshot = v.data_snapshot AND g.id_gestacao = v.id_gestacao
WHERE g.fase_atual = 'Gestação'
GROUP BY g.data_snapshot
ORDER BY g.data_snapshot;
```

## Indicadores Calculáveis

### Cobertura e Acesso
- % gestações com pelo menos 1 consulta pré-natal
- % gestações com ≥ 6 consultas (adequação MS)
- % início precoce (1ª consulta no 1º trimestre)
- % cobertura de visitas ACS
- Tempo médio desde última consulta/visita

### Condições Clínicas
- Prevalência de diabetes (prévio, gestacional)
- Prevalência de hipertensão (prévia, pré-eclâmpsia)
- Identificação de prováveis hipertensas sem diagnóstico
- Prevalência de HIV, sífilis, tuberculose

### Controle e Tratamento
- % gestantes hipertensas com PA controlada
- % uso de anti-hipertensivos seguros vs contraindicados
- % adequação de prescrição de AAS
- % prescrição de ácido fólico e carbonato de cálcio
- Dispensação de aparelhos de PA

### Encaminhamentos
- % gestações encaminhadas para alto risco
- Tempo médio para encaminhamento
- Motivos de encaminhamento (CIDs)

### Ganho de Peso
- Ganho de peso médio por classificação IMC inicial
- % ganho de peso adequado por diretriz MS
- Evolução do IMC durante gestação

### Desfecho
- Tipo de parto (normal/cesariana/aborto)
- Local do parto (estabelecimento)
- IG no momento do parto

## Boas Práticas

### ✅ Ordem de Execução OBRIGATÓRIA
1. gestacoes_historico (base para todas as outras)
2. atendimentos_prenatal_aps_historico
3. visitas_acs_gestacao_historico (pode paralelizar com 4 e 5)
4. consultas_emergenciais_historico (pode paralelizar com 3 e 5)
5. encaminhamentos_historico (pode paralelizar com 3 e 4)
6. linha_tempo_historico (depende de todas as anteriores)

### ❌ Erros Comuns
- Executar linha_tempo sem executar dependências primeiro
- Esquecer de filtrar por `data_snapshot` em consultas
- Misturar tabelas originais com históricas
- Não validar consistência entre tabelas

### Performance
- Execute em horários de baixo uso para grandes volumes
- Use particionamento por `data_snapshot` em todas as queries
- Use clustering por `id_paciente, fase_atual`
- Considere materializar agregações frequentes
- Para análises de longo período, use tabelas acumulativas

### Validação de Consistência
```sql
-- Verificar se todas as tabelas têm dados para a mesma data
SELECT
    data_snapshot,
    COUNT(DISTINCT tabela) AS tabelas_com_dados
FROM (
    SELECT DISTINCT data_snapshot, 'gestacoes' AS tabela
    FROM gestacoes_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'atendimentos_pn'
    FROM atendimentos_prenatal_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'visitas_acs'
    FROM visitas_acs_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'consultas_emerg'
    FROM consultas_emergenciais_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'linha_tempo'
    FROM linha_tempo_historico_acumulado
)
GROUP BY data_snapshot
HAVING COUNT(DISTINCT tabela) < 5  -- Alerta se faltarem tabelas
ORDER BY data_snapshot;
```

## Limitações

1. **Dados Retroativos**: Reconstrói snapshots baseado no estado atual dos dados, não como estavam naquela data
2. **Performance**: Pipeline completo pode levar minutos para grandes volumes
3. **Dependências**: Falha em uma etapa impede execução das seguintes
4. **Espaço**: Tabelas acumulativas crescem linearmente com número de snapshots

## Troubleshooting

### Erro: "Table not found: _gestacoes_historico"
**Causa**: Procedimento 1 não foi executado ou falhou
**Solução**: Execute `proced_1_gestacoes_historico` primeiro

### Resultado vazio em tabela downstream
**Causa**: Snapshot não existe na tabela dependente
**Solução**: Verificar execução dos procedimentos anteriores

### Performance lenta
**Causas**:
- Volume grande de dados
- Falta de particionamento/clustering
- Horário de pico

**Soluções**:
- Reduza intervalo de datas
- Execute em horários de baixo uso
- Use particionamento adequado
- Considere aumentar slots de processamento

### Inconsistências entre tabelas
**Causa**: Execução parcial do pipeline
**Solução**: Execute validação de consistência, reprocesse data completa

## Arquivos do Projeto

| Arquivo | Descrição |
|---------|-----------|
| `gestante_historico.sql` | Procedimento 1: Gestações |
| `2_atd_prenatal_aps_historico.sql` | Procedimento 2: Atendimentos PN APS |
| `3_visitas_acs_gestacao_historico.sql` | Procedimento 3: Visitas ACS |
| `4_consultas_emergenciais_historico.sql` | Procedimento 4: Consultas Emergenciais |
| `5_encaminhamentos_historico.sql` | Procedimento 5: Encaminhamentos SISREG |
| `6_linha_tempo_historico.sql` | Procedimento 6: Linha do Tempo (agregação) |
| `construir_historico_completo.sql` | Script de execução completo com exemplos |
| `README_HISTORICO_COMPLETO.md` | Esta documentação |
| `README_GESTACOES_HISTORICO.md` | Documentação específica de gestações |
| `README_ATENDIMENTOS_HISTORICO.md` | Documentação específica de atendimentos |

## Suporte

Para questões sobre:
- **Lógica de negócio**: Consulte esta documentação e arquivos README específicos
- **Performance**: Verifique plano de execução e otimizações
- **Dados inconsistentes**: Execute queries de validação
- **Indicadores**: Consulte MS - Cadernos de Atenção Básica nº 32

## Próximos Passos

1. Testar pipeline completo com dados de produção
2. Criar dashboards de acompanhamento temporal
3. Automatizar execução mensal
4. Implementar alertas de qualidade de dados
5. Documentar indicadores calculados
