-- ============================================================
-- VALIDAÇÃO DA QUERY DE TESTE - query_teste_gestacoes.sql
-- ============================================================
--
-- Este script valida os resultados da query de teste, exibindo:
-- 1. Quantidade de gestantes com fase_atual = 'Gestação'
-- 2. Máximo de consultas de uma mesma gestante
-- 3. Quantidade média de consultas por gestante
-- 4. Data de início máxima e mínima dentre todas as gestações
--
-- Para usar: Execute a query_teste_gestacoes.sql primeiro,
-- depois execute este script de validação
-- ============================================================

WITH
    -- Resultado da query de teste (pode ser substituído por uma CTE ou tabela temporária)
    dados_teste AS (
        -- COLE AQUI O CONTEÚDO COMPLETO DA query_teste_gestacoes.sql
        -- OU substitua por: SELECT * FROM `projeto.dataset.tabela_resultado_teste`

        DECLARE data_referencia DATE DEFAULT DATE('2025-01-01');

        WITH
            -- ------------------------------------------------------------
            -- Recuperando dados do Paciente
            -- ------------------------------------------------------------
            cadastro_paciente AS (
                SELECT
                    dados.id_paciente,
                    dados.nome,
                    DATE_DIFF (
                        data_referencia,
                        dados.data_nascimento,
                        YEAR
                    ) AS idade_gestante
                FROM `rj-sms.saude_historico_clinico.paciente`
            ),

            -- ------------------------------------------------------------
            -- Eventos de Gestação COM FILTRO TEMPORAL
            -- ------------------------------------------------------------
            eventos_brutos AS (
                SELECT
                    id_hci,
                    paciente.id_paciente AS id_paciente,
                    paciente_cpf as cpf,
                    cp.nome,
                    cp.idade_gestante,
                    c.id AS cid,
                    c.situacao AS situacao_cid,
                    SAFE.PARSE_DATE (
                        '%Y-%m-%d',
                        SUBSTR(c.data_diagnostico, 1, 10)
                    ) AS data_evento,
                    CASE
                        WHEN c.id = 'Z321'
                        OR c.id LIKE 'Z34%'
                        OR c.id LIKE 'Z35%' THEN 'gestacao'
                        ELSE NULL
                    END AS tipo_evento
                FROM
                    `rj-sms.saude_historico_clinico.episodio_assistencial`
                    LEFT JOIN UNNEST (condicoes) c
                    INNER JOIN cadastro_paciente cp ON paciente.id_paciente = cp.id_paciente
                WHERE
                    c.data_diagnostico IS NOT NULL
                    AND c.data_diagnostico != ''
                    AND c.situacao IN ('ATIVO', 'RESOLVIDO')
                    AND (
                        c.id = 'Z321'
                        OR c.id LIKE 'Z34%'
                        OR c.id LIKE 'Z35%'
                    )
                    AND paciente.id_paciente IS NOT NULL
                    AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
                    AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
            ),

            -- ------------------------------------------------------------
            -- Eventos de DESFECHO da Gestação
            -- ------------------------------------------------------------
            eventos_desfecho AS (
                SELECT
                    paciente.id_paciente AS id_paciente,
                    SAFE.PARSE_DATE (
                        '%Y-%m-%d',
                        SUBSTR(c.data_diagnostico, 1, 10)
                    ) AS data_desfecho,
                    c.id AS cid_desfecho,
                    CASE
                        WHEN c.id BETWEEN 'O00' AND 'O08' THEN 'aborto'
                        WHEN c.id BETWEEN 'O80' AND 'O84' THEN 'parto'
                        WHEN c.id BETWEEN 'O85' AND 'O92' THEN 'puerperio_confirmado'
                        ELSE 'outro_desfecho'
                    END AS tipo_desfecho
                FROM
                    `rj-sms.saude_historico_clinico.episodio_assistencial`
                    LEFT JOIN UNNEST (condicoes) c
                WHERE
                    c.data_diagnostico IS NOT NULL
                    AND c.data_diagnostico != ''
                    AND paciente.id_paciente IS NOT NULL
                    AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
                    AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 365 DAY)
                    AND (c.id BETWEEN 'O00' AND 'O99')
            ),

            -- ------------------------------------------------------------
            -- Primeiro desfecho por gestação
            -- ------------------------------------------------------------
            primeiro_desfecho AS (
                SELECT
                    i.id_hci,
                    i.id_paciente,
                    i.data_evento AS data_inicio,
                    MIN(d.data_desfecho) AS data_fim,
                    ARRAY_AGG(d.tipo_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS tipo_desfecho,
                    ARRAY_AGG(d.cid_desfecho ORDER BY d.data_desfecho LIMIT 1)[OFFSET(0)] AS cid_desfecho
                FROM eventos_brutos i
                LEFT JOIN eventos_desfecho d
                    ON i.id_paciente = d.id_paciente
                    AND d.data_desfecho > i.data_evento
                    AND DATE_DIFF(d.data_desfecho, i.data_evento, DAY) <= 320
                WHERE i.data_evento <= data_referencia
                    AND i.tipo_evento = 'gestacao'
                GROUP BY i.id_hci, i.id_paciente, i.data_evento
            ),

            -- ------------------------------------------------------------
            -- Gestações Únicas com Desfecho Real
            -- ------------------------------------------------------------
            gestacoes_unicas AS (
                SELECT
                    pd.id_hci,
                    pd.id_paciente,
                    eb.cpf,
                    eb.nome,
                    eb.idade_gestante,
                    pd.data_inicio,
                    pd.data_fim,
                    pd.tipo_desfecho,
                    pd.cid_desfecho,
                    ROW_NUMBER() OVER (
                        PARTITION BY pd.id_paciente
                        ORDER BY pd.data_inicio
                    ) AS numero_gestacao,
                    CONCAT(
                        pd.id_paciente,
                        '-',
                        CAST(
                            ROW_NUMBER() OVER (
                                PARTITION BY pd.id_paciente
                                ORDER BY pd.data_inicio
                            ) AS STRING
                        )
                    ) AS id_gestacao
                FROM primeiro_desfecho pd
                INNER JOIN eventos_brutos eb
                    ON pd.id_hci = eb.id_hci
                    AND pd.id_paciente = eb.id_paciente
                    AND pd.data_inicio = eb.data_evento
            ),

            -- ------------------------------------------------------------
            -- Gestações com Status
            -- ------------------------------------------------------------
            gestacoes_com_status AS (
                SELECT
                    *,
                    CASE
                        WHEN data_fim IS NOT NULL THEN data_fim
                        WHEN DATE_ADD(data_inicio, INTERVAL 299 DAY) <= data_referencia
                        THEN DATE_ADD(data_inicio, INTERVAL 299 DAY)
                        ELSE NULL
                    END AS data_fim_efetiva,
                    DATE_ADD(data_inicio, INTERVAL 40 WEEK) AS dpp
                FROM gestacoes_unicas
            ),

            -- ------------------------------------------------------------
            -- Definição de Fase Atual
            -- ------------------------------------------------------------
            gestacoes_com_fase AS (
                SELECT
                    gcs.*,
                    CASE
                        WHEN gcs.data_inicio <= data_referencia
                        AND (
                            gcs.data_fim IS NULL OR gcs.data_fim >= data_referencia
                        )
                        AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) >= data_referencia
                        THEN 'Gestação'

                        WHEN gcs.data_fim IS NOT NULL
                        AND gcs.data_fim < data_referencia
                        AND DATE_ADD(gcs.data_fim, INTERVAL 42 DAY) >= data_referencia
                        THEN 'Puerpério'

                        WHEN gcs.data_fim IS NOT NULL
                        AND DATE_ADD(gcs.data_fim, INTERVAL 42 DAY) < data_referencia
                        THEN 'Encerrada'

                        WHEN gcs.data_fim IS NULL
                        AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) < data_referencia
                        THEN 'Encerrada'

                        ELSE 'Status indefinido'
                    END AS fase_atual,

                    CASE
                        WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) <= 13 THEN '1º trimestre'
                        WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) BETWEEN 14 AND 27 THEN '2º trimestre'
                        WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) >= 28 THEN '3º trimestre'
                        ELSE 'Não aplicável'
                    END AS trimestre_atual_gestacao,

                    DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) AS ig_atual_semanas,

                    CASE
                        WHEN gcs.data_fim IS NOT NULL
                        THEN DATE_DIFF(gcs.data_fim, gcs.data_inicio, WEEK)
                        ELSE NULL
                    END AS ig_final_semanas
                FROM gestacoes_com_status gcs
            ),

            -- ------------------------------------------------------------
            -- Filtrar para Incluir APENAS Gestação e Puerpério
            -- ------------------------------------------------------------
            filtrado AS (
                SELECT *
                FROM gestacoes_com_fase
                WHERE fase_atual IN ('Gestação', 'Puerpério')
            )

        SELECT
            data_referencia AS data_snapshot,
            id_hci,
            id_gestacao,
            id_paciente,
            cpf,
            nome,
            idade_gestante,
            numero_gestacao,
            data_inicio,
            data_fim,
            data_fim_efetiva,
            tipo_desfecho,
            cid_desfecho,
            dpp,
            fase_atual,
            trimestre_atual_gestacao,
            ig_atual_semanas,
            ig_final_semanas
        FROM filtrado
    ),

    -- ============================================================
    -- INDICADORES DE VALIDAÇÃO
    -- ============================================================

    -- 1. Contagem de gestantes com fase_atual = 'Gestação'
    gestantes_ativas AS (
        SELECT COUNT(*) AS total_gestantes_ativas
        FROM dados_teste
        WHERE fase_atual = 'Gestação'
    ),

    -- 2. Estatísticas de consultas por gestante
    -- Nota: A query de teste não inclui informações de consultas
    -- Este indicador seria aplicável se houvesse junção com tabela de atendimentos
    estatisticas_consultas AS (
        SELECT
            'N/A - Query não inclui consultas' AS nota,
            0 AS max_consultas_gestante,
            0.0 AS media_consultas_gestante
    ),

    -- 3. Datas de início máxima e mínima
    datas_inicio AS (
        SELECT
            MIN(data_inicio) AS data_inicio_minima,
            MAX(data_inicio) AS data_inicio_maxima,
            DATE_DIFF(MAX(data_inicio), MIN(data_inicio), DAY) AS range_dias
        FROM dados_teste
    ),

    -- 4. Estatísticas adicionais por fase
    distribuicao_fases AS (
        SELECT
            fase_atual,
            COUNT(*) AS total,
            ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual
        FROM dados_teste
        GROUP BY fase_atual
    ),

    -- 5. Estatísticas por trimestre (para gestantes ativas)
    distribuicao_trimestres AS (
        SELECT
            trimestre_atual_gestacao,
            COUNT(*) AS total,
            ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual
        FROM dados_teste
        WHERE fase_atual = 'Gestação'
        GROUP BY trimestre_atual_gestacao
    )

-- ============================================================
-- RESULTADO FINAL DA VALIDAÇÃO
-- ============================================================
SELECT
    '====== VALIDAÇÃO DA QUERY DE TESTE ======' AS secao,
    CAST(NULL AS STRING) AS metrica,
    CAST(NULL AS STRING) AS valor,
    CAST(NULL AS STRING) AS observacao

UNION ALL

-- Linha em branco
SELECT '', '', '', ''

UNION ALL

-- 1. GESTANTES ATIVAS
SELECT
    '1. GESTANTES COM FASE = "Gestação"' AS secao,
    'Total de Gestantes Ativas' AS metrica,
    CAST(total_gestantes_ativas AS STRING) AS valor,
    'Gestações em curso na data de referência' AS observacao
FROM gestantes_ativas

UNION ALL

-- Linha em branco
SELECT '', '', '', ''

UNION ALL

-- 2. ESTATÍSTICAS DE CONSULTAS (não aplicável)
SELECT
    '2. ESTATÍSTICAS DE CONSULTAS' AS secao,
    'Máximo de Consultas (uma gestante)' AS metrica,
    nota AS valor,
    'Query de teste não inclui dados de atendimentos prenatal' AS observacao
FROM estatisticas_consultas

UNION ALL

SELECT
    '',
    'Média de Consultas por Gestante' AS metrica,
    nota AS valor,
    'Para validar consultas, use: proced_2_atd_prenatal_aps_historico' AS observacao
FROM estatisticas_consultas

UNION ALL

-- Linha em branco
SELECT '', '', '', ''

UNION ALL

-- 3. DATAS DE INÍCIO
SELECT
    '3. RANGE DE DATAS DE INÍCIO' AS secao,
    'Data de Início Mínima' AS metrica,
    CAST(data_inicio_minima AS STRING) AS valor,
    'Gestação mais antiga no dataset' AS observacao
FROM datas_inicio

UNION ALL

SELECT
    '',
    'Data de Início Máxima' AS metrica,
    CAST(data_inicio_maxima AS STRING) AS valor,
    'Gestação mais recente no dataset' AS observacao
FROM datas_inicio

UNION ALL

SELECT
    '',
    'Range (dias)' AS metrica,
    CAST(range_dias AS STRING) AS valor,
    'Diferença entre início mais antigo e mais recente' AS observacao
FROM datas_inicio

UNION ALL

-- Linha em branco
SELECT '', '', '', ''

UNION ALL

-- 4. DISTRIBUIÇÃO POR FASE
SELECT
    '4. DISTRIBUIÇÃO POR FASE ATUAL' AS secao,
    fase_atual AS metrica,
    CONCAT(CAST(total AS STRING), ' (', CAST(percentual AS STRING), '%)') AS valor,
    'Total e percentual por fase' AS observacao
FROM distribuicao_fases

UNION ALL

-- Linha em branco
SELECT '', '', '', ''

UNION ALL

-- 5. DISTRIBUIÇÃO POR TRIMESTRE (apenas gestantes ativas)
SELECT
    '5. DISTRIBUIÇÃO POR TRIMESTRE (Gestações Ativas)' AS secao,
    trimestre_atual_gestacao AS metrica,
    CONCAT(CAST(total AS STRING), ' (', CAST(percentual AS STRING), '%)') AS valor,
    'Total e percentual por trimestre gestacional' AS observacao
FROM distribuicao_trimestres

ORDER BY secao, metrica;


-- ============================================================
-- OBSERVAÇÕES IMPORTANTES
-- ============================================================
--
-- 1. CONSULTAS PRÉ-NATAIS:
--    A query de teste (query_teste_gestacoes.sql) NÃO inclui
--    informações sobre consultas pré-natais. Para validar
--    o número de consultas por gestante, é necessário:
--
--    - Executar: proced_2_atd_prenatal_aps_historico
--    - Fonte: _atendimentos_prenatal_aps_historico
--    - Campo: numero_consulta
--
-- 2. DATA DE REFERÊNCIA:
--    A validação usa a mesma data_referencia da query de teste.
--    Por padrão: DATE('2025-01-01')
--    Altere conforme necessário na linha 15 deste script.
--
-- 3. JANELA TEMPORAL:
--    A query de teste aplica filtro temporal de 340 dias
--    antes da data de referência, conforme documentação.
--
-- 4. USO PRÁTICO:
--    Este script pode ser adaptado para validar resultados
--    das procedures do pipeline histórico:
--    - _gestacoes_historico
--    - _atendimentos_prenatal_aps_historico
--    - _linha_tempo_historico
--
-- ============================================================
