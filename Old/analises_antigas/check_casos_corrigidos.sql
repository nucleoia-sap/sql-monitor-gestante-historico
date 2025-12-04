-- Verificação rápida dos casos problemáticos após correção
-- Data de referência: 2025-07-01

DECLARE data_referencia DATE DEFAULT DATE('2025-07-01');

WITH
    cadastro_paciente AS (
        SELECT
            dados.id_paciente,
            dados.nome,
            DATE_DIFF(data_referencia, dados.data_nascimento, YEAR) AS idade_gestante
        FROM `rj-sms.saude_historico_clinico.paciente`
    ),

    eventos_brutos AS (
        SELECT
            id_hci,
            paciente.id_paciente AS id_paciente,
            paciente_cpf as cpf,
            cp.nome,
            c.situacao AS situacao_cid,
            SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) AS data_evento,
            CASE
                WHEN c.id = 'Z321' OR c.id LIKE 'Z34%' OR c.id LIKE 'Z35%' THEN 'gestacao'
                ELSE NULL
            END AS tipo_evento
        FROM `rj-sms.saude_historico_clinico.episodio_assistencial`
            LEFT JOIN UNNEST(condicoes) c
            INNER JOIN cadastro_paciente cp ON paciente.id_paciente = cp.id_paciente
        WHERE
            c.data_diagnostico IS NOT NULL
            AND paciente.id_paciente IS NOT NULL
            AND c.situacao IN ('ATIVO', 'RESOLVIDO')
            AND (c.id = 'Z321' OR c.id LIKE 'Z34%' OR c.id LIKE 'Z35%')
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
    ),

    inicios_brutos AS (
        SELECT * FROM eventos_brutos
        WHERE tipo_evento = 'gestacao' AND situacao_cid = 'ATIVO'
    ),

    inicios_com_grupo AS (
        SELECT
            *,
            CASE
                WHEN LAG(data_evento) OVER(PARTITION BY id_paciente ORDER BY data_evento) IS NULL THEN 1
                WHEN DATE_DIFF(data_evento, LAG(data_evento) OVER(PARTITION BY id_paciente ORDER BY data_evento), DAY) >= 60 THEN 1
                ELSE 0
            END AS nova_ocorrencia_flag
        FROM inicios_brutos
    ),

    grupos_inicios AS (
        SELECT
            *,
            SUM(nova_ocorrencia_flag) OVER(PARTITION BY id_paciente ORDER BY data_evento) AS grupo_id
        FROM inicios_com_grupo
    ),

    inicios_deduplicados AS (
        SELECT * FROM (
            SELECT
                *,
                ROW_NUMBER() OVER(PARTITION BY id_paciente, grupo_id ORDER BY data_evento DESC) AS rn
            FROM grupos_inicios
        )
        WHERE rn = 1
    )

-- Validação dos casos específicos
SELECT
    cpf,
    nome,
    COUNT(*) as gestacoes_encontradas,
    STRING_AGG(DISTINCT CAST(data_evento AS STRING), ', ' ORDER BY CAST(data_evento AS STRING)) as datas_inicio,
    CASE
        WHEN COUNT(*) = 1 THEN '✅ CORRIGIDO - 1 gestação'
        ELSE CONCAT('⚠️ AINDA TEM ', CAST(COUNT(*) AS STRING), ' REGISTROS')
    END AS status
FROM inicios_deduplicados
WHERE cpf IN ('20469417722', '17361746730', '12535785757', '09606275701')
GROUP BY cpf, nome
ORDER BY cpf;
