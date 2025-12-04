-- ============================================================
-- SCRIPT DE VALIDAÇÃO: LÓGICA DE MODA PARA ESTIMATIVA DA DUM
-- ============================================================
-- Objetivo: Validar nova lógica de identificação do início da gestação
-- usando MODA (valor mais frequente) de data_diagnostico
--
-- Data de Criação: 2025-12-03
-- Autor: Claude Code
-- ============================================================

DECLARE data_referencia DATE DEFAULT DATE('2024-10-31');

-- ============================================================
-- SEÇÃO 1: PREPARAÇÃO DOS DADOS
-- ============================================================


WITH

    -- Cadastro de pacientes
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

    -- Eventos brutos de gestação (ATIVO e RESOLVIDO)
    eventos_brutos AS (
        SELECT
            id_hci,
            paciente.id_paciente AS id_paciente,
            paciente_cpf as cpf,
            cp.nome,
            c.id AS cid,
            c.situacao AS situacao_cid,
            SAFE.PARSE_DATE (
                '%Y-%m-%d',
                SUBSTR(c.data_diagnostico, 1, 10)
            ) AS data_evento
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

-- ============================================================
-- SEÇÃO 2: LÓGICA NOVA - MODA (VALOR MAIS FREQUENTE)
-- ============================================================

    -- Agrupar eventos em períodos de gestação (janela de 60 dias)
    eventos_com_periodo AS (
        SELECT
            *,
            LAG(data_evento) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
            ) AS data_evento_anterior,
            CASE
                WHEN LAG(data_evento) OVER (
                    PARTITION BY id_paciente
                    ORDER BY data_evento
                ) IS NULL THEN 1
                WHEN DATE_DIFF(
                    data_evento,
                    LAG(data_evento) OVER (
                        PARTITION BY id_paciente
                        ORDER BY data_evento
                    ),
                    DAY
                ) > 60 THEN 1
                ELSE 0
            END AS nova_gestacao_flag
        FROM eventos_brutos
    ),

    -- Criar ID de período de gestação
    eventos_com_grupo_gestacao AS (
        SELECT
            *,
            SUM(nova_gestacao_flag) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS grupo_gestacao
        FROM eventos_com_periodo
    ),

    -- Calcular frequência de cada data_evento DENTRO de cada grupo de gestação
    frequencia_datas AS (
        SELECT
            id_paciente,
            grupo_gestacao,
            data_evento,
            COUNT(*) AS frequencia,
            COUNT(DISTINCT id_hci) AS atendimentos_distintos,
            STRING_AGG(DISTINCT situacao_cid ORDER BY situacao_cid) AS situacoes,
            ANY_VALUE(cpf) AS cpf,
            ANY_VALUE(nome) AS nome
        FROM eventos_com_grupo_gestacao
        GROUP BY id_paciente, grupo_gestacao, data_evento
    ),

    -- Selecionar MODA (data com maior frequência) DENTRO de cada grupo
    dum_por_moda AS (
        SELECT
            id_paciente,
            grupo_gestacao,
            cpf,
            nome,
            data_evento AS dum_moda,
            frequencia,
            atendimentos_distintos,
            situacoes,
            ROW_NUMBER() OVER (
                PARTITION BY id_paciente, grupo_gestacao
                ORDER BY frequencia DESC, data_evento DESC  -- Empate: pega mais recente
            ) AS rn
        FROM frequencia_datas
    ),

    resultado_moda AS (
        SELECT
            id_paciente,
            grupo_gestacao,
            cpf,
            nome,
            dum_moda,
            frequencia AS vezes_registrada,
            atendimentos_distintos,
            situacoes
        FROM dum_por_moda
        WHERE rn = 1
    ),

    -- Contagem de gestações por paciente
    gestacoes_por_paciente AS (
        SELECT
            id_paciente,
            COUNT(DISTINCT grupo_gestacao) AS total_gestacoes
        FROM resultado_moda
        GROUP BY id_paciente
    ),

-- ============================================================
-- SEÇÃO 3: LÓGICA ANTIGA - PRIMEIRO CID ATIVO (COMPARAÇÃO)
-- ============================================================

    eventos_apenas_ativos AS (
        SELECT *
        FROM eventos_brutos
        WHERE situacao_cid = 'ATIVO'
    ),

    primeiro_ativo AS (
        SELECT
            id_paciente,
            MIN(data_evento) AS dum_primeira_ativa,
            COUNT(DISTINCT data_evento) AS datas_distintas_ativas
        FROM eventos_apenas_ativos
        GROUP BY id_paciente
    ),

-- ============================================================
-- SEÇÃO 4: COMPARAÇÃO ENTRE LÓGICAS (apenas primeira gestação)
-- ============================================================

    -- Seleciona apenas primeira gestação de cada paciente na nova lógica
    primeira_gestacao_moda AS (
        SELECT
            id_paciente,
            cpf,
            nome,
            dum_moda,
            vezes_registrada,
            atendimentos_distintos,
            situacoes
        FROM resultado_moda
        WHERE grupo_gestacao = 0  -- Primeira gestação identificada
    ),

    comparacao AS (
        SELECT
            m.id_paciente,
            m.cpf,
            m.nome,
            m.dum_moda,
            m.vezes_registrada,
            m.atendimentos_distintos,
            m.situacoes AS situacoes_moda,
            a.dum_primeira_ativa,
            a.datas_distintas_ativas,
            DATE_DIFF(m.dum_moda, a.dum_primeira_ativa, DAY) AS diferenca_dias,
            CASE
                WHEN m.dum_moda = a.dum_primeira_ativa THEN 'Igual'
                WHEN a.dum_primeira_ativa IS NULL THEN 'Somente MODA (sem ATIVO)'
                WHEN m.dum_moda > a.dum_primeira_ativa THEN 'MODA posterior'
                WHEN m.dum_moda < a.dum_primeira_ativa THEN 'MODA anterior'
            END AS classificacao_diferenca
        FROM primeira_gestacao_moda m
        LEFT JOIN primeiro_ativo a ON m.id_paciente = a.id_paciente
    ),

-- ============================================================
-- SEÇÃO 5: ANÁLISE DE DISTRIBUIÇÃO DE FREQUÊNCIAS
-- ============================================================

    distribuicao_frequencias AS (
        SELECT
            vezes_registrada AS vezes_dum_registrada,
            COUNT(*) AS quantidade_pacientes,
            ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentual
        FROM resultado_moda
        GROUP BY vezes_registrada
    ),

-- ============================================================
-- SEÇÃO 6: CASOS EXTREMOS E OUTLIERS
-- ============================================================

    casos_extremos AS (
        SELECT
            'DUM registrada apenas 1 vez' AS tipo_caso,
            COUNT(*) AS quantidade
        FROM resultado_moda
        WHERE vezes_registrada = 1

        UNION ALL

        SELECT
            'DUM registrada 10+ vezes',
            COUNT(*)
        FROM resultado_moda
        WHERE vezes_registrada >= 10

        UNION ALL

        SELECT
            'Diferença > 30 dias entre MODA e 1º ATIVO',
            COUNT(*)
        FROM comparacao
        WHERE ABS(diferenca_dias) > 30

        UNION ALL

        SELECT
            'Casos onde MODA é NULL mas 1º ATIVO existe',
            COUNT(*)
        FROM comparacao
        WHERE dum_moda IS NULL AND dum_primeira_ativa IS NOT NULL

        UNION ALL

        SELECT
            'Casos onde MODA existe mas 1º ATIVO é NULL',
            COUNT(*)
        FROM comparacao
        WHERE dum_moda IS NOT NULL AND dum_primeira_ativa IS NULL
    ),

-- ============================================================
-- SEÇÃO 7: EXEMPLOS DETALHADOS DE PACIENTES
-- ============================================================

    -- Seleciona pacientes de exemplo de cada categoria usando ROW_NUMBER
    pacientes_exemplo AS (
        SELECT id_paciente, classificacao_diferenca
        FROM (
            SELECT
                id_paciente,
                classificacao_diferenca,
                ROW_NUMBER() OVER (PARTITION BY classificacao_diferenca ORDER BY id_paciente) AS rn
            FROM comparacao
            WHERE classificacao_diferenca IN ('MODA posterior', 'MODA anterior', 'Somente MODA (sem ATIVO)')
        )
        WHERE rn <= 5
    ),

    exemplos_detalhados AS (
        SELECT
            eb.id_paciente,
            eb.cpf,
            eb.nome,
            eb.data_evento,
            eb.situacao_cid,
            eb.cid,
            COUNT(*) OVER (PARTITION BY eb.id_paciente, eb.data_evento) AS freq_desta_data,
            ROW_NUMBER() OVER (PARTITION BY eb.id_paciente ORDER BY eb.data_evento) AS ordem_cronologica
        FROM eventos_brutos eb
        INNER JOIN pacientes_exemplo pe ON eb.id_paciente = pe.id_paciente
    )

-- ============================================================
-- SEÇÃO 8: RELATÓRIO FINAL
-- ============================================================

-- OPÇÃO 1: Resumo Estatístico Completo
-- ------------------------------------------------------------
SELECT
    '=== RESUMO GERAL ===' AS secao,
    CAST(NULL AS STRING) AS metrica,
    CAST(NULL AS INT64) AS valor,
    CAST(NULL AS STRING) AS observacao

UNION ALL

SELECT
    '',
    'Total de pacientes analisados',
    COUNT(*),
    'Pacientes com pelo menos 1 CID gestacional na janela temporal'
FROM resultado_moda

UNION ALL

SELECT
    '',
    'Pacientes com DUM válida (MODA)',
    COUNT(*),
    'Conseguiu calcular DUM via MODA'
FROM resultado_moda
WHERE dum_moda IS NOT NULL

UNION ALL

SELECT
    '',
    'Pacientes com DUM via 1º ATIVO',
    COUNT(*),
    'Teria DUM na lógica antiga'
FROM primeiro_ativo
WHERE dum_primeira_ativa IS NOT NULL

UNION ALL

SELECT
    '=== COMPARAÇÃO LÓGICAS ===',
    '',
    NULL,
    ''

UNION ALL

SELECT
    '',
    classificacao_diferenca,
    COUNT(*),
    CONCAT(CAST(ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS STRING), '%')
FROM comparacao
GROUP BY classificacao_diferenca

UNION ALL

SELECT
    '=== GESTAÇÕES MÚLTIPLAS ===',
    '',
    NULL,
    ''

UNION ALL

SELECT
    '',
    'Pacientes com 1 gestação',
    COUNTIF(total_gestacoes = 1),
    CONCAT(CAST(ROUND(COUNTIF(total_gestacoes = 1) * 100.0 / COUNT(*), 2) AS STRING), '%')
FROM gestacoes_por_paciente

UNION ALL

SELECT
    '',
    'Pacientes com 2+ gestações',
    COUNTIF(total_gestacoes >= 2),
    CONCAT(CAST(ROUND(COUNTIF(total_gestacoes >= 2) * 100.0 / COUNT(*), 2) AS STRING), '%')
FROM gestacoes_por_paciente

UNION ALL

SELECT
    '',
    'Total de gestações identificadas',
    SUM(total_gestacoes),
    'Somando todas as gestações de todas pacientes'
FROM gestacoes_por_paciente

UNION ALL

SELECT
    '=== DISTRIBUIÇÃO DE FREQUÊNCIAS ===',
    '',
    NULL,
    ''

UNION ALL

SELECT
    '',
    CONCAT('DUM registrada ', CAST(vezes_dum_registrada AS STRING), ' vezes'),
    quantidade_pacientes,
    CONCAT(CAST(percentual AS STRING), '%')
FROM distribuicao_frequencias

UNION ALL

SELECT
    '=== CASOS EXTREMOS ===',
    '',
    NULL,
    ''

UNION ALL

SELECT
    '',
    tipo_caso,
    quantidade,
    ''
FROM casos_extremos

UNION ALL

SELECT
    '=== ESTATÍSTICAS DE DIFERENÇA (MODA vs 1º ATIVO) ===',
    '',
    NULL,
    ''

UNION ALL

SELECT
    '',
    'Diferença média (dias)',
    CAST(ROUND(AVG(diferenca_dias), 2) AS INT64),
    'Positivo = MODA posterior ao 1º ATIVO'
FROM comparacao
WHERE diferenca_dias IS NOT NULL

UNION ALL

SELECT
    '',
    'Diferença mediana (dias)',
    CAST(APPROX_QUANTILES(diferenca_dias, 2)[OFFSET(1)] AS INT64),
    ''
FROM comparacao
WHERE diferenca_dias IS NOT NULL

UNION ALL

SELECT
    '',
    'Diferença máxima (dias)',
    MAX(ABS(diferenca_dias)),
    ''
FROM comparacao
WHERE diferenca_dias IS NOT NULL

UNION ALL

SELECT
    '',
    'Diferença mínima (dias)',
    MIN(ABS(diferenca_dias)),
    ''
FROM comparacao
WHERE diferenca_dias IS NOT NULL AND diferenca_dias != 0

ORDER BY secao, metrica;


-- OPÇÃO 2: Detalhamento de Casos Específicos (descomente para usar)
-- ------------------------------------------------------------
-- SELECT
--     cpf,
--     nome,
--     dum_moda,
--     vezes_registrada,
--     atendimentos_distintos,
--     situacoes_moda,
--     dum_primeira_ativa,
--     diferenca_dias,
--     classificacao_diferenca
-- FROM comparacao
-- WHERE classificacao_diferenca != 'Igual'
-- ORDER BY ABS(diferenca_dias) DESC
-- LIMIT 100;


-- OPÇÃO 3: Timeline de Registros para Pacientes Específicos (descomente para usar)
-- ------------------------------------------------------------
-- SELECT
--     cpf,
--     nome,
--     ordem_cronologica,
--     data_evento,
--     situacao_cid,
--     cid,
--     freq_desta_data AS frequencia_desta_data
-- FROM exemplos_detalhados
-- ORDER BY cpf, ordem_cronologica;
