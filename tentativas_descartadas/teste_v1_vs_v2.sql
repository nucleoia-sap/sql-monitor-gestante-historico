-- ============================================================
-- TESTE DE COMPARAÇÃO: V1 (agrupamento por DUM) vs V2 (agrupamento por data_atendimento)
-- ============================================================
-- Objetivo: Validar se a V2 resolve os problemas:
-- 1. Número excessivo de gestações (95K vs esperado ~80K)
-- 2. id_hci aparecendo em múltiplas gestações (528 casos)
-- Data: 03/12/2025
-- ============================================================

-- ============================================================
-- EXECUTAR PRIMEIRO:
-- bq query --use_legacy_sql=false < "1_gestacoes_historico.sql"
-- CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2025-07-01'));
--
-- bq query --use_legacy_sql=false < "1_gestacoes_historico_v2.sql"
-- CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico_v2`(DATE('2025-07-01'));
-- ============================================================

WITH

    -- Resultados V1 (original)
    v1_stats AS (
        SELECT
            'V1' AS versao,
            COUNT(*) AS total_gestacoes,
            COUNT(DISTINCT id_paciente) AS pacientes_unicos,
            COUNT(DISTINCT id_hci) AS id_hci_unicos,
            COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
            COUNTIF(fase_atual = 'Puerpério') AS puerperios
        FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
        WHERE data_snapshot = DATE('2025-07-01')
    ),

    -- Resultados V2 (nova lógica)
    v2_stats AS (
        SELECT
            'V2' AS versao,
            COUNT(*) AS total_gestacoes,
            COUNT(DISTINCT id_paciente) AS pacientes_unicos,
            COUNT(DISTINCT id_hci) AS id_hci_unicos,
            COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
            COUNTIF(fase_atual = 'Puerpério') AS puerperios
        FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico_v2`
        WHERE data_snapshot = DATE('2025-07-01')
    ),

    -- Análise de id_hci duplicados V1
    v1_id_hci_duplicados AS (
        SELECT
            'V1' AS versao,
            COUNT(*) AS id_hci_duplicados
        FROM (
            SELECT id_hci, COUNT(*) AS ocorrencias
            FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
            WHERE data_snapshot = DATE('2025-07-01')
            GROUP BY id_hci
            HAVING COUNT(*) > 1
        )
    ),

    -- Análise de id_hci duplicados V2
    v2_id_hci_duplicados AS (
        SELECT
            'V2' AS versao,
            COUNT(*) AS id_hci_duplicados
        FROM (
            SELECT id_hci, COUNT(*) AS ocorrencias
            FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico_v2`
            WHERE data_snapshot = DATE('2025-07-01')
            GROUP BY id_hci
            HAVING COUNT(*) > 1
        )
    ),

    -- Pacientes com múltiplas gestações V1
    v1_multiplas AS (
        SELECT
            'V1' AS versao,
            COUNTIF(total = 2) AS pacientes_2_gestacoes,
            COUNTIF(total >= 3) AS pacientes_3plus_gestacoes,
            MAX(total) AS max_gestacoes_por_paciente
        FROM (
            SELECT id_paciente, COUNT(*) AS total
            FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
            WHERE data_snapshot = DATE('2025-07-01')
            GROUP BY id_paciente
        )
    ),

    -- Pacientes com múltiplas gestações V2
    v2_multiplas AS (
        SELECT
            'V2' AS versao,
            COUNTIF(total = 2) AS pacientes_2_gestacoes,
            COUNTIF(total >= 3) AS pacientes_3plus_gestacoes,
            MAX(total) AS max_gestacoes_por_paciente
        FROM (
            SELECT id_paciente, COUNT(*) AS total
            FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico_v2`
            WHERE data_snapshot = DATE('2025-07-01')
            GROUP BY id_paciente
        )
    )

-- ============================================================
-- RELATÓRIO COMPARATIVO
-- ============================================================

SELECT
    '=== COMPARAÇÃO GERAL ===' AS secao,
    CAST(NULL AS STRING) AS versao,
    NULL AS metrica_1,
    NULL AS metrica_2,
    NULL AS diferenca

UNION ALL

SELECT
    '',
    v1.versao,
    v1.total_gestacoes,
    v2.total_gestacoes,
    v2.total_gestacoes - v1.total_gestacoes
FROM v1_stats v1, v2_stats v2
WHERE v1.versao = 'V1' AND v2.versao = 'V2'

UNION ALL

SELECT
    'Total de gestações',
    'Variação %',
    NULL,
    NULL,
    ROUND((v2.total_gestacoes - v1.total_gestacoes) * 100.0 / v1.total_gestacoes, 2)
FROM v1_stats v1, v2_stats v2
WHERE v1.versao = 'V1' AND v2.versao = 'V2'

UNION ALL

SELECT
    '',
    NULL,
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    '=== PACIENTES ÚNICOS ===',
    NULL,
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    'Pacientes únicos',
    v1.versao,
    v1.pacientes_unicos,
    v2.pacientes_unicos,
    v2.pacientes_unicos - v1.pacientes_unicos
FROM v1_stats v1, v2_stats v2
WHERE v1.versao = 'V1' AND v2.versao = 'V2'

UNION ALL

SELECT
    '',
    NULL,
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    '=== PROBLEMA: id_hci DUPLICADOS ===',
    NULL,
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    'id_hci em múltiplas gestações',
    v1.versao,
    v1.id_hci_duplicados,
    v2.id_hci_duplicados,
    v2.id_hci_duplicados - v1.id_hci_duplicados
FROM v1_id_hci_duplicados v1, v2_id_hci_duplicados v2
WHERE v1.versao = 'V1' AND v2.versao = 'V2'

UNION ALL

SELECT
    '✅ Esperado',
    'V2 = 0',
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    '',
    NULL,
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    '=== GESTAÇÕES MÚLTIPLAS ===',
    NULL,
    NULL,
    NULL,
    NULL

UNION ALL

SELECT
    'Pacientes com 2 gestações',
    v1.versao,
    v1.pacientes_2_gestacoes,
    v2.pacientes_2_gestacoes,
    v2.pacientes_2_gestacoes - v1.pacientes_2_gestacoes
FROM v1_multiplas v1, v2_multiplas v2
WHERE v1.versao = 'V1' AND v2.versao = 'V2'

UNION ALL

SELECT
    'Pacientes com 3+ gestações',
    v1.versao,
    v1.pacientes_3plus_gestacoes,
    v2.pacientes_3plus_gestacoes,
    v2.pacientes_3plus_gestacoes - v1.pacientes_3plus_gestacoes
FROM v1_multiplas v1, v2_multiplas v2
WHERE v1.versao = 'V1' AND v2.versao = 'V2'

UNION ALL

SELECT
    'Máximo gestações/paciente',
    v1.versao,
    v1.max_gestacoes_por_paciente,
    v2.max_gestacoes_por_paciente,
    v2.max_gestacoes_por_paciente - v1.max_gestacoes_por_paciente
FROM v1_multiplas v1, v2_multiplas v2
WHERE v1.versao = 'V1' AND v2.versao = 'V2'

ORDER BY secao, versao;
