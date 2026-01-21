-- ============================================================
-- KPIs DE INDICADORES DE MELHORIA - GESTANTES
-- ============================================================
-- Objetivo: Gerar indicadores de melhoria para acompanhamento
--           em série histórica (por data_snapshot)
--
-- KPIs Implementados:
--   1. Percentual de gestantes com indicação de AAS sem prescrição
--   2. Percentual de gestantes com critérios de alto risco não encaminhadas
--   3. Percentual de gestantes com sífilis com tratamento inadequado (AGUARDANDO TABELA EXTERNA)
--   4. Percentual de gestantes com mais de 30 dias sem consulta
--   5. Percentual de gestantes sem prescrição de Carbonato de cálcio
--   6. Percentual de gestantes sem prescrição de ácido fólico
--
-- Nota: KPIs com baixo nível de maturidade, em evolução
-- Data: 2026-01-14
-- ============================================================

-- ============================================================
-- QUERY 1: KPIs AGREGADOS POR SNAPSHOT (SÉRIE HISTÓRICA)
-- ============================================================
-- Retorna os 6 KPIs de melhoria para cada data_snapshot

WITH base_gestantes AS (
    SELECT
        data_snapshot,
        id_gestacao,
        id_paciente,
        nome,
        
        -- Campos para KPI 1: AAS
        tem_indicacao_aas,
        tem_prescricao_aas,
        
        -- Campos para KPI 2: Encaminhamento alto risco
        deve_encaminhar,
        houve_encaminhamento,
        categorias_risco,
        
        -- Campos para KPI 3: Sífilis (aguardando tabela externa)
        sifilis,
        
        -- Campos para KPI 4: Dias sem consulta
        dias_desde_ultima_consulta,
        mais_de_30_sem_atd,
        
        -- Campos para KPI 5 e 6: Prescrições
        prescricao_carbonato_calcio,
        prescricao_acido_folico,
        
        -- Campos auxiliares
        clinica_nome,
        equipe_nome,
        area_programatica
        
    FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
    WHERE fase_atual = 'Gestação'
)

SELECT
    data_snapshot,
    
    -- Total de gestantes ativas no snapshot
    COUNT(*) AS total_gestantes,
    
    -- ============================================================
    -- KPI 1: Gestantes com indicação de AAS sem prescrição
    -- ============================================================
    -- Numerador: tem indicação E não tem prescrição
    -- Denominador: total com indicação de AAS
    COUNTIF(tem_indicacao_aas = 1) AS total_com_indicacao_aas,
    COUNTIF(tem_indicacao_aas = 1 AND COALESCE(tem_prescricao_aas, 0) = 0) AS aas_indicado_sem_prescricao,
    ROUND(
        SAFE_DIVIDE(
            COUNTIF(tem_indicacao_aas = 1 AND COALESCE(tem_prescricao_aas, 0) = 0),
            COUNTIF(tem_indicacao_aas = 1)
        ) * 100, 1
    ) AS pct_aas_indicado_sem_prescricao,
    
    -- ============================================================
    -- KPI 2: Gestantes com critérios de alto risco não encaminhadas
    -- ============================================================
    -- Numerador: deve encaminhar E não foi encaminhada
    -- Denominador: total que deve encaminhar
    COUNTIF(deve_encaminhar IS NOT NULL AND TRIM(deve_encaminhar) != '') AS total_deve_encaminhar,
    COUNTIF(
        deve_encaminhar IS NOT NULL 
        AND TRIM(deve_encaminhar) != '' 
        AND (houve_encaminhamento IS NULL OR houve_encaminhamento != 'Sim')
    ) AS alto_risco_sem_encaminhamento,
    ROUND(
        SAFE_DIVIDE(
            COUNTIF(
                deve_encaminhar IS NOT NULL 
                AND TRIM(deve_encaminhar) != '' 
                AND (houve_encaminhamento IS NULL OR houve_encaminhamento != 'Sim')
            ),
            COUNTIF(deve_encaminhar IS NOT NULL AND TRIM(deve_encaminhar) != '')
        ) * 100, 1
    ) AS pct_alto_risco_sem_encaminhamento,
    
    -- ============================================================
    -- KPI 3: Gestantes com sífilis com tratamento inadequado
    -- ============================================================
    -- NOTA: Aguardando tabela externa com adequação do tratamento
    -- Por enquanto, apenas contagem de gestantes com sífilis
    COUNTIF(sifilis = 1) AS total_com_sifilis,
    -- Placeholder: será substituído por JOIN com tabela de tratamento
    CAST(NULL AS INT64) AS sifilis_tratamento_inadequado,
    CAST(NULL AS FLOAT64) AS pct_sifilis_tratamento_inadequado,
    
    -- ============================================================
    -- KPI 4: Gestantes com mais de 30 dias sem consulta
    -- ============================================================
    -- Numerador: mais de 30 dias sem atendimento
    -- Denominador: total de gestantes
    COUNTIF(mais_de_30_sem_atd = 'sim') AS mais_30_dias_sem_consulta,
    ROUND(
        COUNTIF(mais_de_30_sem_atd = 'sim') * 100.0 / COUNT(*), 1
    ) AS pct_mais_30_dias_sem_consulta,
    
    -- ============================================================
    -- KPI 5: Gestantes sem prescrição de Carbonato de cálcio
    -- ============================================================
    -- Numerador: sem prescrição de cálcio
    -- Denominador: total de gestantes
    COUNTIF(prescricao_carbonato_calcio = 'não' OR prescricao_carbonato_calcio IS NULL) AS sem_carbonato_calcio,
    ROUND(
        COUNTIF(prescricao_carbonato_calcio = 'não' OR prescricao_carbonato_calcio IS NULL) * 100.0 / COUNT(*), 1
    ) AS pct_sem_carbonato_calcio,
    
    -- ============================================================
    -- KPI 6: Gestantes sem prescrição de ácido fólico
    -- ============================================================
    -- Numerador: sem prescrição de ácido fólico
    -- Denominador: total de gestantes
    COUNTIF(prescricao_acido_folico = 'não' OR prescricao_acido_folico IS NULL) AS sem_acido_folico,
    ROUND(
        COUNTIF(prescricao_acido_folico = 'não' OR prescricao_acido_folico IS NULL) * 100.0 / COUNT(*), 1
    ) AS pct_sem_acido_folico

FROM base_gestantes
GROUP BY data_snapshot
ORDER BY data_snapshot;


-- ============================================================
-- QUERY 2: DRILL-DOWN - LISTA DE PACIENTES POR KPI
-- ============================================================
-- Use esta query para obter a lista de pacientes em cada indicador
-- Descomente e ajuste o filtro conforme necessário

/*
DECLARE data_referencia DATE DEFAULT DATE('2025-01-01');

-- Exemplo: Lista de gestantes com indicação de AAS sem prescrição
SELECT
    data_snapshot,
    id_gestacao,
    id_paciente,
    nome,
    clinica_nome,
    equipe_nome,
    area_programatica,
    tem_indicacao_aas,
    tem_prescricao_aas,
    'KPI 1 - AAS indicado sem prescrição' AS kpi_afetado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_referencia
  AND fase_atual = 'Gestação'
  AND tem_indicacao_aas = 1 
  AND COALESCE(tem_prescricao_aas, 0) = 0

UNION ALL

-- Lista de gestantes de alto risco sem encaminhamento
SELECT
    data_snapshot,
    id_gestacao,
    id_paciente,
    nome,
    clinica_nome,
    equipe_nome,
    area_programatica,
    CAST(NULL AS INT64) AS tem_indicacao_aas,
    CAST(NULL AS INT64) AS tem_prescricao_aas,
    'KPI 2 - Alto risco sem encaminhamento' AS kpi_afetado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_referencia
  AND fase_atual = 'Gestação'
  AND deve_encaminhar IS NOT NULL 
  AND TRIM(deve_encaminhar) != ''
  AND (houve_encaminhamento IS NULL OR houve_encaminhamento != 'Sim')

UNION ALL

-- Lista de gestantes com mais de 30 dias sem consulta
SELECT
    data_snapshot,
    id_gestacao,
    id_paciente,
    nome,
    clinica_nome,
    equipe_nome,
    area_programatica,
    CAST(NULL AS INT64) AS tem_indicacao_aas,
    CAST(NULL AS INT64) AS tem_prescricao_aas,
    'KPI 4 - Mais de 30 dias sem consulta' AS kpi_afetado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_referencia
  AND fase_atual = 'Gestação'
  AND mais_de_30_sem_atd = 'sim'

UNION ALL

-- Lista de gestantes sem carbonato de cálcio
SELECT
    data_snapshot,
    id_gestacao,
    id_paciente,
    nome,
    clinica_nome,
    equipe_nome,
    area_programatica,
    CAST(NULL AS INT64) AS tem_indicacao_aas,
    CAST(NULL AS INT64) AS tem_prescricao_aas,
    'KPI 5 - Sem carbonato de cálcio' AS kpi_afetado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_referencia
  AND fase_atual = 'Gestação'
  AND (prescricao_carbonato_calcio = 'não' OR prescricao_carbonato_calcio IS NULL)

UNION ALL

-- Lista de gestantes sem ácido fólico
SELECT
    data_snapshot,
    id_gestacao,
    id_paciente,
    nome,
    clinica_nome,
    equipe_nome,
    area_programatica,
    CAST(NULL AS INT64) AS tem_indicacao_aas,
    CAST(NULL AS INT64) AS tem_prescricao_aas,
    'KPI 6 - Sem ácido fólico' AS kpi_afetado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_referencia
  AND fase_atual = 'Gestação'
  AND (prescricao_acido_folico = 'não' OR prescricao_acido_folico IS NULL)

ORDER BY kpi_afetado, nome;
*/


-- ============================================================
-- QUERY 3: KPIs AGREGADOS POR UNIDADE (PARA COMPARAÇÃO)
-- ============================================================
-- Permite comparar KPIs entre diferentes unidades/equipes

/*
DECLARE data_referencia DATE DEFAULT DATE('2025-01-01');

SELECT
    data_snapshot,
    clinica_nome,
    area_programatica,
    
    COUNT(*) AS total_gestantes,
    
    -- KPI 1: AAS
    ROUND(SAFE_DIVIDE(
        COUNTIF(tem_indicacao_aas = 1 AND COALESCE(tem_prescricao_aas, 0) = 0),
        COUNTIF(tem_indicacao_aas = 1)
    ) * 100, 1) AS pct_aas_indicado_sem_prescricao,
    
    -- KPI 2: Encaminhamento
    ROUND(SAFE_DIVIDE(
        COUNTIF(deve_encaminhar IS NOT NULL AND TRIM(deve_encaminhar) != '' 
                AND (houve_encaminhamento IS NULL OR houve_encaminhamento != 'Sim')),
        COUNTIF(deve_encaminhar IS NOT NULL AND TRIM(deve_encaminhar) != '')
    ) * 100, 1) AS pct_alto_risco_sem_encaminhamento,
    
    -- KPI 4: Dias sem consulta
    ROUND(COUNTIF(mais_de_30_sem_atd = 'sim') * 100.0 / COUNT(*), 1) AS pct_mais_30_dias_sem_consulta,
    
    -- KPI 5: Carbonato de cálcio
    ROUND(COUNTIF(prescricao_carbonato_calcio = 'não' OR prescricao_carbonato_calcio IS NULL) * 100.0 / COUNT(*), 1) AS pct_sem_carbonato_calcio,
    
    -- KPI 6: Ácido fólico
    ROUND(COUNTIF(prescricao_acido_folico = 'não' OR prescricao_acido_folico IS NULL) * 100.0 / COUNT(*), 1) AS pct_sem_acido_folico

FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_referencia
  AND fase_atual = 'Gestação'
GROUP BY data_snapshot, clinica_nome, area_programatica
ORDER BY clinica_nome;
*/
