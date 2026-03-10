-- ============================================================
-- HISTÓRICO DE GESTAÇÕES - VERSÃO COM DEBUG
-- ============================================================
-- VERSÃO PARAMETRIZADA PARA CONSTRUÇÃO DE HISTÓRICO
-- Parâmetro data_referencia: permite gerar snapshot dos dados em uma data específica
--
-- 🐛 INSTRUÇÕES DE DEBUG:
-- ============================================================
-- Este arquivo contém 5 blocos de debug comentados:
--
-- DEBUG 1: eventos_brutos (linha ~106)
--   → Verifica quantos eventos de gestação foram capturados
--   → Útil para: validar filtros temporais e de CID
--
-- DEBUG 2: inicios_brutos/finais (linha ~149)
--   → Verifica distribuição de eventos ATIVO/RESOLVIDO
--   → Útil para: entender proporção início vs fim
--
-- DEBUG 3: inicios_deduplicados (linha ~232)
--   → Verifica se deduplicação está funcionando
--   → Útil para: encontrar multiplicação de eventos
--   → CRÍTICO: Aqui está a contagem base de gestações
--
-- DEBUG 4: gestacoes_unicas (linha ~297)
--   → Verifica contagem final de gestações
--   → Útil para: validar se subconsulta de data_fim está correta
--   → Esperado: ~28.000 gestações
--
-- DEBUG 5: filtrado (linha ~372)
--   → Verifica resultado final por fase
--   → Útil para: validar filtros de fase e detectar duplicações
--   → Esperado: ~28.000 registros (Gestação + Puerpério)
--
-- COMO USAR:
-- 1. Comente o DELETE e INSERT (linhas 32-35)
-- 2. Descomente UM bloco de debug por vez
-- 3. Execute a query para ver o resultado daquele bloco
-- 4. Compare os números entre os blocos para identificar onde ocorre a inflação
--
-- POSSÍVEIS CAUSAS DE INFLAÇÃO (>28mil):
-- ✗ Janela temporal muito ampla (340 dias)
-- ✗ Deduplicação não está funcionando (verifique DEBUG 3)
-- ✗ Múltiplos id_hci criando gestações duplicadas
-- ✗ Lógica de agrupamento (60 dias) inadequada → ✅ CORRIGIDO: 240 dias
-- ✗ CIDs duplicados no mesmo episódio assistencial
-- ============================================================
--
-- 📋 CONCEITO-CHAVE: IDENTIFICAÇÃO DE GESTAÇÃO ÚNICA
-- ============================================================
-- DEFINIÇÃO CLÍNICA:
-- Uma gestação é identificada univocamente pela combinação:
--   • Paciente (id_paciente)
--   • DUM - Data da Última Menstruação
--
-- IMPLICAÇÃO:
-- Múltiplos atendimentos com MESMA DUM + MESMO paciente = MESMA gestação
--
-- DESAFIO TÉCNICO:
-- • DUM não está explícita nos dados históricos (episodio_assistencial)
-- • Apenas temos: CIDs de gestação (Z321, Z34x, Z35x) com suas datas
--
-- SOLUÇÃO IMPLEMENTADA:
-- • Janela temporal de 240 dias agrupa implicitamente pela DUM
-- • Atendimentos dentro de 240 dias = mesma DUM = mesma gestação
-- • Atendimentos com >240 dias = DUM diferente = gestação diferente
--
-- VALIDAÇÃO:
-- • Protocolo pré-natal: 9-10 consultas a cada 30-45 dias
-- • Período gestacional: 280 dias (40 semanas)
-- • Janela de 240 dias cobre toda a gestação sem fragmentar
-- ============================================================
--
-- CREATE OR REPLACE PROCEDURE `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_referencia DATE)

-- BEGIN

--   -- A consulta que você quer salvar e reutilizar
--   -- Usa data_referencia no lugar de CURRENT_DATE() para permitir análise histórica



-- CREATE OR REPLACE TABLE `rj-sms-sandbox.sub_pav_us._gestacoes_historico` AS
DECLARE data_referencia DATE DEFAULT DATE('2024-01-01');

-- ============================================================
-- MODO DEBUG: Descomente as linhas abaixo para testar com amostra
-- ============================================================
-- DECLARE debug_mode BOOL DEFAULT TRUE;
-- DECLARE sample_pacientes ARRAY<STRING> DEFAULT [
--     'id_paciente_1', 'id_paciente_2', 'id_paciente_3'
-- ];
-- ============================================================

-- ============================================================
-- QUERY DE ANÁLISE DETALHADA (Descomente para usar)
-- Analisa linha do tempo de eventos para pacientes específicos
-- ============================================================
-- WITH pacientes_problema AS (
--     SELECT id_paciente
--     FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
--     WHERE data_snapshot = DATE('2025-01-01')
--     GROUP BY id_paciente
--     HAVING COUNT(*) > 3  -- Pacientes com mais de 3 gestações
--     LIMIT 5
-- ),
-- linha_tempo AS (
--     SELECT
--         ea.paciente.id_paciente,
--         ea.id_hci,
--         c.id as cid,
--         c.situacao,
--         SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) as data_diagnostico
--     FROM `rj-sms.saude_historico_clinico.episodio_assistencial` ea
--     LEFT JOIN UNNEST(condicoes) c
--     WHERE ea.paciente.id_paciente IN (SELECT id_paciente FROM pacientes_problema)
--         AND (c.id = 'Z321' OR c.id LIKE 'Z34%' OR c.id LIKE 'Z35%')
--     ORDER BY ea.paciente.id_paciente, data_diagnostico
-- )
-- SELECT * FROM linha_tempo;
-- ============================================================

-- CREATE OR REPLACE TABLE `rj-sms-sandbox.sub_pav_us._gestacoes_historico` AS
DELETE FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico` 
WHERE data_snapshot = data_referencia;

INSERT INTO `rj-sms-sandbox.sub_pav_us._gestacoes_historico` 

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
    -- Janela: [data_referencia - 340 dias, data_referencia]
    -- Justificativa: 299 dias (gestação) + 42 dias (puerpério) = 341 dias
    --
    -- ✅ CORREÇÃO: NÃO filtra por situacao_cid = 'ATIVO'
    -- Pega TODOS os CIDs de gestação (ATIVO e RESOLVIDO) pois estamos
    -- olhando dados históricos onde gestações já podem ter sido encerradas
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
            AND c.situacao IN ('ATIVO','RESOLVIDO')
            AND (
                c.id = 'Z321'
                OR c.id LIKE 'Z34%'
                OR c.id LIKE 'Z35%'
            )
            AND paciente.id_paciente IS NOT NULL
            -- Filtro de janela temporal
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) <= data_referencia
            AND SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(c.data_diagnostico, 1, 10)) >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
    ),

    -- ============================================================
    -- DEBUG 1: Eventos Brutos
    -- Descomente para verificar quantos eventos foram capturados
    -- ============================================================
    -- debug_eventos AS (
    --     SELECT
    --         'eventos_brutos' as etapa,
    --         COUNT(*) as total_eventos,
    --         COUNT(DISTINCT id_paciente) as total_pacientes,
    --         COUNT(DISTINCT id_hci) as total_episodios,
    --         ROUND(COUNT(*) / COUNT(DISTINCT id_paciente), 2) as eventos_por_paciente,
    --         COUNTIF(situacao_cid = 'ATIVO') as eventos_ativos,
    --         COUNTIF(situacao_cid = 'RESOLVIDO') as eventos_resolvidos
    --     FROM eventos_brutos
    -- )
    -- SELECT * FROM debug_eventos;
    -- ============================================================

    -- ------------------------------------------------------------
    -- Inícios de Gestação (apenas CIDs ATIVOS)
    -- ------------------------------------------------------------
    -- inicios_brutos AS (
    --     SELECT *
    --     FROM eventos_brutos
    --     WHERE tipo_evento = 'gestacao'
    -- ),


    inicios_brutos AS (
        SELECT *
        FROM eventos_brutos
        WHERE
            tipo_evento = 'gestacao'
            AND situacao_cid = 'ATIVO'
    ),
    finais AS (
        SELECT *
        FROM eventos_brutos
        WHERE
            tipo_evento = 'gestacao'
            AND situacao_cid = 'RESOLVIDO'
    ),

    -- ============================================================
    -- DEBUG 2: Inícios e Finais
    -- Descomente para verificar distribuição de eventos ATIVO/RESOLVIDO
    -- ============================================================
    -- debug_inicios_finais AS (
    --     SELECT
    --         'inicios_brutos' as tipo,
    --         COUNT(*) as total_eventos,
    --         COUNT(DISTINCT id_paciente) as total_pacientes,
    --         COUNT(DISTINCT id_hci) as total_episodios,
    --         ROUND(COUNT(*) / COUNT(DISTINCT id_paciente), 2) as eventos_por_paciente
    --     FROM inicios_brutos
    --     UNION ALL
    --     SELECT
    --         'finais' as tipo,
    --         COUNT(*) as total_eventos,
    --         COUNT(DISTINCT id_paciente) as total_pacientes,
    --         COUNT(DISTINCT id_hci) as total_episodios,
    --         ROUND(COUNT(*) / COUNT(DISTINCT id_paciente), 2) as eventos_por_paciente
    --     FROM finais
    -- )
    -- SELECT * FROM debug_inicios_finais;
    -- ============================================================


    -- ------------------------------------------------------------
    -- Inícios de Gestação com Grupo (janela de 240 dias)
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Aumentado de 60 para 240 dias
    --
    -- RACIONAL DE AGRUPAMENTO:
    -- ========================
    -- Princípio: Atendimentos com a MESMA DUM (Data da Última Menstruação)
    -- e MESMO paciente pertencem à MESMA gestação.
    --
    -- PROBLEMA: Não temos acesso direto à DUM nos dados históricos.
    --
    -- SOLUÇÃO: Usar janela temporal que implicitamente agrupa pela DUM:
    -- • Consultas da mesma gestação têm DUM idêntica ou muito próxima
    -- • Logo, suas datas de atendimento estarão distribuídas ao longo
    --   dos 280 dias de gestação
    -- • Janela de 240 dias garante que TODAS as consultas da mesma
    --   gestação sejam agrupadas juntas
    --
    -- EVIDÊNCIA DOS DADOS:
    -- • 9.49 consultas ATIVO por paciente (DEBUG 2)
    -- • Consultas ocorrem a cada 30-45 dias (protocolo pré-natal)
    -- • 9 consultas × 30 dias = 270 dias (toda a gestação)
    --
    -- RESULTADO:
    -- • Janela de 240 dias efetivamente agrupa eventos pela DUM implícita
    -- • Eventos com >240 dias de diferença = DUM diferente = nova gestação
    -- • Evita fragmentação de gestação única em múltiplos grupos
    --
    -- EXEMPLO VISUAL DE AGRUPAMENTO PELA DUM IMPLÍCITA:
    -- =================================================
    --
    -- Paciente X - DUM: 01/jan/2024 (GESTAÇÃO 1)
    -- ├─ 15/jan: CID Z34.0 ATIVO  │ }
    -- ├─ 15/fev: CID Z34.0 ATIVO  │ } Grupo 1
    -- ├─ 20/mar: CID Z34.0 ATIVO  │ } (240 dias)
    -- ├─ 25/abr: CID Z34.0 ATIVO  │ } = GESTAÇÃO 1
    -- └─ 01/set: CID O80.0 RESOLVIDO │ }
    --
    -- Paciente X - DUM: 15/jan/2025 (GESTAÇÃO 2 - >240 dias depois)
    -- ├─ 30/jan/2025: CID Z34.0 ATIVO │ }
    -- ├─ 01/mar/2025: CID Z34.0 ATIVO │ } Grupo 2
    -- └─ 05/abr/2025: CID Z34.0 ATIVO │ } = GESTAÇÃO 2
    --
    -- SEM JANELA ADEQUADA (60 dias):
    -- • Consulta 1→2 (30d): ✅ mesmo grupo
    -- • Consulta 2→3 (33d): ✅ mesmo grupo
    -- • Consulta 3→4 (36d): ✅ mesmo grupo
    -- • Consulta 4→5 (127d): ❌ NOVO GRUPO (fragmentação!)
    -- → Resultado: 1 gestação = 2+ grupos ❌
    --
    -- COM JANELA 240 DIAS:
    -- • Todas consultas dentro de 240 dias: ✅ mesmo grupo
    -- • Nova gestação após >240 dias: ✅ novo grupo
    -- → Resultado: 1 gestação = 1 grupo ✅
    -- ------------------------------------------------------------
    inicios_com_grupo AS (
        SELECT
            *,
            LAG(data_evento) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
            ) AS data_anterior,
            CASE
                WHEN LAG(data_evento) OVER (
                    PARTITION BY id_paciente
                    ORDER BY data_evento
                ) IS NULL THEN 1
                WHEN DATE_DIFF (
                    data_evento,
                    LAG(data_evento) OVER (
                        PARTITION BY id_paciente
                        ORDER BY data_evento
                    ),
                    DAY
                ) >= 240 THEN 1  -- ✅ ALTERADO: 60 → 240 dias
                ELSE 0
            END AS nova_ocorrencia_flag
        FROM inicios_brutos
    ),

    -- ------------------------------------------------------------
    -- Grupos de Inícios de Gestação
    -- ------------------------------------------------------------
    grupos_inicios AS (
        SELECT *, SUM(nova_ocorrencia_flag) OVER (
                PARTITION BY id_paciente
                ORDER BY data_evento
            ) AS grupo_id
        FROM inicios_com_grupo
    ),

    -- ------------------------------------------------------------
    -- Inícios de Gestação Deduplicados (DATA MAIS RECENTE)
    -- ------------------------------------------------------------
    -- ✅ CORREÇÃO: Usar DATA MAIS RECENTE do grupo (não MODA)
    -- query_teste_gestacoes.sql usa esta abordagem
    -- ------------------------------------------------------------
    inicios_deduplicados AS (
        SELECT *
        FROM (
                SELECT *, ROW_NUMBER() OVER (
                        PARTITION BY id_paciente, grupo_id
                        ORDER BY data_evento DESC  -- ✅ DATA MAIS RECENTE
                    ) AS rn
                FROM grupos_inicios
            )
        WHERE rn = 1
    ),

    -- ============================================================
    -- DEBUG 3: Deduplicação de Inícios
    -- CRÍTICO: Verificar se deduplicação está funcionando
    -- Valores esperados: ~28.000 gestações
    -- ============================================================
    -- debug_deduplicacao AS (
    --     SELECT
    --         'grupos_inicios' as etapa,
    --         COUNT(*) as total_registros,
    --         COUNT(DISTINCT id_paciente) as total_pacientes,
    --         COUNT(DISTINCT CONCAT(id_paciente, '-', CAST(grupo_id AS STRING))) as total_grupos,
    --         ROUND(COUNT(*) / COUNT(DISTINCT id_paciente), 2) as registros_por_paciente
    --     FROM grupos_inicios
    --     UNION ALL
    --     SELECT
    --         'inicios_deduplicados' as etapa,
    --         COUNT(*) as total_registros,
    --         COUNT(DISTINCT id_paciente) as total_pacientes,
    --         COUNT(DISTINCT CONCAT(id_paciente, '-', CAST(grupo_id AS STRING))) as total_grupos,
    --         ROUND(COUNT(*) / COUNT(DISTINCT id_paciente), 2) as registros_por_paciente
    --     FROM inicios_deduplicados
    -- )
    -- SELECT * FROM debug_deduplicacao;
    -- ============================================================

    -- ------------------------------------------------------------
    -- Gestações Únicas
    -- ------------------------------------------------------------
    -- Define cada gestação única com sua data de início e data de fim.
    -- A data de fim é o primeiro evento 'RESOLVIDO' (de 'finais') que ocorre após a data de início da gestação.
    -- Gera um 'numero_gestacao' e um 'id_gestacao' único para cada gestação da paciente.
    -- ------------------------------------------------------------
    gestacoes_unicas AS (
        SELECT
            i.id_hci,
            i.id_paciente,
            i.cpf,
            i.nome,
            i.idade_gestante,
            i.data_evento AS data_inicio,
            -- Subconsulta para encontrar a data de fim mais próxima após o início
            (
                SELECT MIN(f.data_evento)
                FROM finais f
                WHERE
                    f.id_paciente = i.id_paciente
                    AND f.data_evento > i.data_evento
            ) AS data_fim,
            ROW_NUMBER() OVER (
                PARTITION BY i.id_paciente
                ORDER BY i.data_evento
            ) AS numero_gestacao,
            CONCAT(
                i.id_paciente,
                '-',
                CAST(
                    ROW_NUMBER() OVER (
                        PARTITION BY i.id_paciente
                        ORDER BY i.data_evento
                    ) AS STRING
                )
            ) AS id_gestacao
        FROM inicios_deduplicados i
    ),

    -- ============================================================
    -- DEBUG 4: Gestações Únicas
    -- CRÍTICO: Verificar contagem final de gestações
    -- Esperado: ~28.000 gestações (Gestação + Puerpério)
    -- ============================================================
    -- debug_gestacoes AS (
    --     SELECT
    --         'gestacoes_unicas' as etapa,
    --         COUNT(*) as total_gestacoes,
    --         COUNT(DISTINCT id_paciente) as total_pacientes,
    --         COUNT(DISTINCT id_gestacao) as total_ids_gestacao,
    --         ROUND(COUNT(*) / COUNT(DISTINCT id_paciente), 2) as gestacoes_por_paciente,
    --         COUNTIF(data_fim IS NOT NULL) as com_data_fim,
    --         COUNTIF(data_fim IS NULL) as sem_data_fim,
    --         MIN(data_inicio) as data_inicio_min,
    --         MAX(data_inicio) as data_inicio_max
    --     FROM gestacoes_unicas
    -- )
    -- SELECT * FROM debug_gestacoes;
    --
    -- -- Verificar distribuição de gestações por paciente
    -- debug_dist_paciente AS (
    --     SELECT
    --         'distribuicao_gestacoes_por_paciente' as metrica,
    --         COUNT(*) as qtd_pacientes,
    --         numero_gestacao as gestacoes
    --     FROM gestacoes_unicas
    --     GROUP BY numero_gestacao
    --     ORDER BY numero_gestacao
    -- )
    -- SELECT * FROM debug_dist_paciente;
    -- ============================================================


    -- ------------------------------------------------------------
    -- Gestações com Status
    -- ------------------------------------------------------------
    -- Calcula a 'data_fim_efetiva' (data de fim real ou estimada após 299 dias se não houver fim registrado e já passou o período).
    -- Calcula a DPP (Data Provável do Parto) como 40 semanas após a data de início.
    -- ------------------------------------------------------------
    gestacoes_com_status AS (
        SELECT
            *,
            CASE
                WHEN data_fim IS NOT NULL THEN data_fim -- Usa a data de fim registrada se existir
                WHEN DATE_ADD(data_inicio, INTERVAL 299 DAY) <= data_referencia THEN DATE_ADD(data_inicio, INTERVAL 299 DAY) -- Se passou 299 dias (42sem + 5 dias) e não tem data_fim, considera encerrada
                ELSE NULL -- Ainda em curso e sem data de fim, ou não atingiu 299 dias. Será tratada pela fase_atual.
            END AS data_fim_efetiva,
            DATE_ADD(data_inicio, INTERVAL 40 WEEK) AS dpp
        FROM gestacoes_unicas
    ),

    -- ------------------------------------------------------------
    -- Definição de Fase e Trimestre da Gestação
    -- ------------------------------------------------------------
    filtrado AS (
        SELECT
            gcs.*,
            CASE
                WHEN gcs.data_fim IS NULL
                AND DATE_ADD(gcs.data_inicio, INTERVAL 299 DAY) > data_referencia THEN 'Gestação' -- Sem data de fim e dentro dos 299 dias esperados
                WHEN gcs.data_fim IS NOT NULL
                AND DATE_DIFF(data_referencia, gcs.data_fim, DAY) <= 45 THEN 'Puerpério' -- Com data de fim, e dentro de 45 dias do fim
                ELSE 'Encerrada' -- Outros casos (com data de fim e > 45 dias, ou sem data de fim mas > 299 dias)
            END AS fase_atual,
            -- Adicionando o cálculo do trimestre aqui para evitar uma CTE separada depois
            CASE
                WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) <= 13 THEN '1º trimestre'
                WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) BETWEEN 14 AND 27  THEN '2º trimestre'
                WHEN DATE_DIFF(data_referencia, gcs.data_inicio, WEEK) >= 28 THEN '3º trimestre'
                ELSE 'Data inválida ou encerrada' -- Pode precisar ajustar essa lógica se `fase_atual` != 'Gestação'
            END AS trimestre_atual_gestacao -- Renomeado para clareza
        FROM gestacoes_com_status gcs
    ),

    -- ============================================================
    -- DEBUG 5: Filtrado por Fase
    -- CRÍTICO: Resultado final antes do SELECT
    -- Esperado: ~28.000 registros (apenas Gestação + Puerpério)
    -- ============================================================
    -- debug_filtrado AS (
    --     SELECT
    --         'filtrado_por_fase' as etapa,
    --         fase_atual,
    --         COUNT(*) as total_registros,
    --         COUNT(DISTINCT id_paciente) as total_pacientes,
    --         COUNT(DISTINCT id_gestacao) as total_gestacoes_unicas,
    --         ROUND(COUNT(*) / COUNT(DISTINCT id_paciente), 2) as registros_por_paciente
    --     FROM filtrado
    --     GROUP BY fase_atual
    -- )
    -- SELECT * FROM debug_filtrado;
    --
    -- -- Verificar se há duplicação de id_gestacao
    -- debug_duplicados AS (
    --     SELECT
    --         id_gestacao,
    --         COUNT(*) as ocorrencias
    --     FROM filtrado
    --     GROUP BY id_gestacao
    --     HAVING COUNT(*) > 1
    -- )
    -- SELECT 'gestacoes_duplicadas' as alerta, COUNT(*) as qtd_duplicadas FROM debug_duplicados;
    -- ============================================================

    -- ------------------------------------------------------------
    -- Descobrindo Equipe da Saúde da Gestação
    -- ------------------------------------------------------------
    unnested_equipes AS (
        SELECT
            p.dados.id_paciente AS id_paciente,
            eq.datahora_ultima_atualizacao,
            eq.nome AS equipe_nome,
            eq.clinica_familia.nome AS clinica_nome
        FROM
            `rj-sms.saude_historico_clinico.paciente` p
            LEFT JOIN UNNEST (p.equipe_saude_familia) AS eq
    ),
    equipe_durante_gestacao AS (
        SELECT
            f.id_gestacao,
            eq.equipe_nome,
            eq.clinica_nome,
            ROW_NUMBER() OVER (
                PARTITION BY f.id_gestacao
                ORDER BY eq.datahora_ultima_atualizacao DESC NULLS LAST
            ) AS rn
        FROM
            filtrado f
            LEFT JOIN unnested_equipes eq ON f.id_paciente = eq.id_paciente
            -- A equipe deve ter sido atualizada ANTES ou NO MÁXIMO na data de fim da gestação
            AND (
                eq.datahora_ultima_atualizacao IS NULL
                OR DATE(eq.datahora_ultima_atualizacao) <= COALESCE(
                    f.data_fim_efetiva,
                    data_referencia
                )
            )
    ),
    equipe_durante_final AS (
        SELECT
            id_gestacao,
            equipe_nome,
            clinica_nome
        FROM equipe_durante_gestacao
        WHERE rn = 1
    )

-- ------------------------------------------------------------
-- Finalização do Modelo
-- Adiciona coluna data_snapshot para identificar o snapshot
-- ------------------------------------------------------------
SELECT
    data_referencia AS data_snapshot,
    filtrado.id_hci,
    filtrado.id_gestacao,
    filtrado.id_paciente,
    filtrado.cpf,
    filtrado.nome,
    filtrado.idade_gestante,
    filtrado.numero_gestacao,
    filtrado.data_inicio,
    filtrado.data_fim,
    filtrado.data_fim_efetiva,
    CAST(NULL AS STRING) AS tipo_desfecho,  -- Placeholder para lógica futura de desfechos
    CAST(NULL AS STRING) AS cid_desfecho,   -- Placeholder para lógica futura de desfechos
    filtrado.dpp,
    filtrado.fase_atual,
    filtrado.trimestre_atual_gestacao,
    -- Calcula IG atual em semanas (idade gestacional no snapshot)
    DATE_DIFF(data_referencia, filtrado.data_inicio, WEEK) AS ig_atual_semanas,
    -- Calcula IG final em semanas (se gestação terminou)
    CASE
        WHEN filtrado.data_fim IS NOT NULL
        THEN DATE_DIFF(filtrado.data_fim, filtrado.data_inicio, WEEK)
        ELSE NULL
    END AS ig_final_semanas,
    edf.equipe_nome,
    edf.clinica_nome
FROM filtrado
    LEFT JOIN equipe_durante_final edf ON filtrado.id_gestacao = edf.id_gestacao;

-- END;
