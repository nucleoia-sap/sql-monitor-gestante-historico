-- =====================================================
-- ANÁLISE DE PRESCRIÇÕES E CONDIÇÕES CLÍNICAS
-- =====================================================
-- Query para calcular percentuais de gestantes com:
-- - Prescrição de ácido fólico
-- - Prescrição de carbonato de cálcio
-- - Hipertensão (total)
-- - Diabetes (total)
-- - Sífilis
--
-- Base: Tabela _linha_tempo_historico
-- Filtro: Apenas gestantes em fase "Gestação" (ativas)
-- =====================================================

-- Versão 1: Agregado Geral (todos os snapshots)
SELECT
    -- Total de gestantes ativas
    COUNT(*) AS total_gestantes_ativas,

    -- PRESCRIÇÕES
    COUNTIF(prescricao_acido_folico = 'sim') AS gestantes_acido_folico,
    ROUND(COUNTIF(prescricao_acido_folico = 'sim') * 100.0 / COUNT(*), 2) AS perc_acido_folico,

    COUNTIF(prescricao_carbonato_calcio = 'sim') AS gestantes_carbonato_calcio,
    ROUND(COUNTIF(prescricao_carbonato_calcio = 'sim') * 100.0 / COUNT(*), 2) AS perc_carbonato_calcio,

    -- CONDIÇÕES CLÍNICAS
    COUNTIF(hipertensao_total = 1) AS gestantes_hipertensao,
    ROUND(COUNTIF(hipertensao_total = 1) * 100.0 / COUNT(*), 2) AS perc_hipertensao,

    COUNTIF(diabetes_total = 1) AS gestantes_diabetes,
    ROUND(COUNTIF(diabetes_total = 1) * 100.0 / COUNT(*), 2) AS perc_diabetes,

    COUNTIF(sifilis = 1) AS gestantes_sifilis,
    ROUND(COUNTIF(sifilis = 1) * 100.0 / COUNT(*), 2) AS perc_sifilis,

    -- COMBINAÇÕES IMPORTANTES
    COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo = 1) AS hipertensas_com_medicacao,
    ROUND(COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo = 1) * 100.0 / NULLIF(COUNTIF(hipertensao_total = 1), 0), 2) AS perc_hipertensas_medicadas,

    COUNTIF(diabetes_total = 1 AND tem_antidiabetico = 1) AS diabeticas_com_medicacao,
    ROUND(COUNTIF(diabetes_total = 1 AND tem_antidiabetico = 1) * 100.0 / NULLIF(COUNTIF(diabetes_total = 1), 0), 2) AS perc_diabeticas_medicadas

FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação';


-- =====================================================
-- Versão 2: Evolução Temporal por Snapshot
-- =====================================================
SELECT
    data_snapshot,

    -- Total de gestantes ativas neste snapshot
    COUNT(*) AS total_gestantes_ativas,

    -- PRESCRIÇÕES
    COUNTIF(prescricao_acido_folico = 'sim') AS gestantes_acido_folico,
    ROUND(COUNTIF(prescricao_acido_folico = 'sim') * 100.0 / COUNT(*), 2) AS perc_acido_folico,

    COUNTIF(prescricao_carbonato_calcio = 'sim') AS gestantes_carbonato_calcio,
    ROUND(COUNTIF(prescricao_carbonato_calcio = 'sim') * 100.0 / COUNT(*), 2) AS perc_carbonato_calcio,

    -- CONDIÇÕES CLÍNICAS
    COUNTIF(hipertensao_total = 1) AS gestantes_hipertensao,
    ROUND(COUNTIF(hipertensao_total = 1) * 100.0 / COUNT(*), 2) AS perc_hipertensao,

    COUNTIF(diabetes_total = 1) AS gestantes_diabetes,
    ROUND(COUNTIF(diabetes_total = 1) * 100.0 / COUNT(*), 2) AS perc_diabetes,

    COUNTIF(sifilis = 1) AS gestantes_sifilis,
    ROUND(COUNTIF(sifilis = 1) * 100.0 / COUNT(*), 2) AS perc_sifilis

FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot
ORDER BY data_snapshot;


-- =====================================================
-- Versão 3: Análise por Área Programática
-- =====================================================
SELECT
    area_programatica,

    COUNT(*) AS total_gestantes_ativas,

    -- PRESCRIÇÕES
    COUNTIF(prescricao_acido_folico = 'sim') AS gestantes_acido_folico,
    ROUND(COUNTIF(prescricao_acido_folico = 'sim') * 100.0 / COUNT(*), 2) AS perc_acido_folico,

    COUNTIF(prescricao_carbonato_calcio = 'sim') AS gestantes_carbonato_calcio,
    ROUND(COUNTIF(prescricao_carbonato_calcio = 'sim') * 100.0 / COUNT(*), 2) AS perc_carbonato_calcio,

    -- CONDIÇÕES CLÍNICAS
    COUNTIF(hipertensao_total = 1) AS gestantes_hipertensao,
    ROUND(COUNTIF(hipertensao_total = 1) * 100.0 / COUNT(*), 2) AS perc_hipertensao,

    COUNTIF(diabetes_total = 1) AS gestantes_diabetes,
    ROUND(COUNTIF(diabetes_total = 1) * 100.0 / COUNT(*), 2) AS perc_diabetes,

    COUNTIF(sifilis = 1) AS gestantes_sifilis,
    ROUND(COUNTIF(sifilis = 1) * 100.0 / COUNT(*), 2) AS perc_sifilis

FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'
  AND area_programatica IS NOT NULL
GROUP BY area_programatica
ORDER BY area_programatica;


-- =====================================================
-- Versão 4: Análise Detalhada de Adequação Terapêutica
-- =====================================================
SELECT
    -- ANÁLISE DE PRESCRIÇÕES SUPLEMENTARES
    '1. Suplementação Vitamínica' AS categoria,
    CONCAT(
        'Ácido Fólico: ',
        ROUND(COUNTIF(prescricao_acido_folico = 'sim') * 100.0 / COUNT(*), 2),
        '% (', COUNTIF(prescricao_acido_folico = 'sim'), '/', COUNT(*), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    '1. Suplementação Vitamínica' AS categoria,
    CONCAT(
        'Carbonato de Cálcio: ',
        ROUND(COUNTIF(prescricao_carbonato_calcio = 'sim') * 100.0 / COUNT(*), 2),
        '% (', COUNTIF(prescricao_carbonato_calcio = 'sim'), '/', COUNT(*), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

-- ANÁLISE DE CONDIÇÕES CLÍNICAS
SELECT
    '2. Prevalência de Condições' AS categoria,
    CONCAT(
        'Hipertensão: ',
        ROUND(COUNTIF(hipertensao_total = 1) * 100.0 / COUNT(*), 2),
        '% (', COUNTIF(hipertensao_total = 1), '/', COUNT(*), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    '2. Prevalência de Condições' AS categoria,
    CONCAT(
        'Diabetes: ',
        ROUND(COUNTIF(diabetes_total = 1) * 100.0 / COUNT(*), 2),
        '% (', COUNTIF(diabetes_total = 1), '/', COUNT(*), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    '2. Prevalência de Condições' AS categoria,
    CONCAT(
        'Sífilis: ',
        ROUND(COUNTIF(sifilis = 1) * 100.0 / COUNT(*), 2),
        '% (', COUNTIF(sifilis = 1), '/', COUNT(*), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

-- ANÁLISE DE ADEQUAÇÃO TERAPÊUTICA
SELECT
    '3. Adequação Terapêutica' AS categoria,
    CONCAT(
        'Hipertensas com Medicação: ',
        ROUND(COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo = 1) * 100.0 / NULLIF(COUNTIF(hipertensao_total = 1), 0), 2),
        '% (', COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo = 1), '/', COUNTIF(hipertensao_total = 1), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    '3. Adequação Terapêutica' AS categoria,
    CONCAT(
        'Hipertensas com Medicação SEGURA: ',
        ROUND(COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo_seguro = 1) * 100.0 / NULLIF(COUNTIF(hipertensao_total = 1), 0), 2),
        '% (', COUNTIF(hipertensao_total = 1 AND tem_anti_hipertensivo_seguro = 1), '/', COUNTIF(hipertensao_total = 1), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    '3. Adequação Terapêutica' AS categoria,
    CONCAT(
        'Diabéticas com Medicação: ',
        ROUND(COUNTIF(diabetes_total = 1 AND tem_antidiabetico = 1) * 100.0 / NULLIF(COUNTIF(diabetes_total = 1), 0), 2),
        '% (', COUNTIF(diabetes_total = 1 AND tem_antidiabetico = 1), '/', COUNTIF(diabetes_total = 1), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

UNION ALL

SELECT
    '3. Adequação Terapêutica' AS categoria,
    CONCAT(
        'Adequação AAS para Pré-eclâmpsia (Adequado): ',
        ROUND(COUNTIF(adequacao_aas_pe = 'Adequado - Com AAS') * 100.0 / COUNT(*), 2),
        '% (', COUNTIF(adequacao_aas_pe = 'Adequado - Com AAS'), '/', COUNT(*), ')'
    ) AS resultado
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'

ORDER BY categoria, resultado;


-- =====================================================
-- Versão 5: Cruzamento Prescrição x Condição Clínica
-- =====================================================
SELECT
    'Ácido Fólico' AS prescricao,
    prescricao_acido_folico AS status_prescricao,
    COUNT(*) AS total_gestantes,
    COUNTIF(hipertensao_total = 1) AS com_hipertensao,
    COUNTIF(diabetes_total = 1) AS com_diabetes,
    COUNTIF(sifilis = 1) AS com_sifilis
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'
GROUP BY prescricao_acido_folico

UNION ALL

SELECT
    'Carbonato de Cálcio' AS prescricao,
    prescricao_carbonato_calcio AS status_prescricao,
    COUNT(*) AS total_gestantes,
    COUNTIF(hipertensao_total = 1) AS com_hipertensao,
    COUNTIF(diabetes_total = 1) AS com_diabetes,
    COUNTIF(sifilis = 1) AS com_sifilis
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE fase_atual = 'Gestação'
GROUP BY prescricao_carbonato_calcio

ORDER BY prescricao, status_prescricao;
