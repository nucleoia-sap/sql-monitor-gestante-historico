-- ============================================================
-- Script para Construir Histórico de Gestações
-- ============================================================
-- Este script executa o procedimento parametrizado para diferentes
-- datas, permitindo análise temporal dos dados de gestação

-- ============================================================
-- EXEMPLO 1: Snapshot para uma data específica
-- ============================================================
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-31'));

-- Verificar resultado
SELECT
    data_snapshot,
    COUNT(*) as total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') as em_gestacao,
    COUNTIF(fase_atual = 'Puerpério') as em_puerperio,
    COUNTIF(fase_atual = 'Encerrada') as encerradas
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
GROUP BY data_snapshot
ORDER BY data_snapshot DESC;


-- ============================================================
-- EXEMPLO 2: Construir histórico mensal (último dia de cada mês)
-- ============================================================

-- Janeiro 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-31'));

-- Fevereiro 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-02-29'));

-- Março 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-03-31'));

-- Abril 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-04-30'));

-- Maio 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-05-31'));

-- Junho 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-06-30'));


-- ============================================================
-- EXEMPLO 3: Construir histórico semanal (todas as segundas-feiras)
-- ============================================================

-- Semana 1 - Janeiro 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-08'));

-- Semana 2
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-15'));

-- Semana 3
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-22'));

-- Semana 4
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-29'));


-- ============================================================
-- EXEMPLO 4: Tabela histórica acumulativa
-- ============================================================
-- Criar tabela para acumular snapshots ao longo do tempo

CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado` (
    data_snapshot DATE,
    id_hci STRING,
    id_gestacao STRING,
    id_paciente STRING,
    cpf STRING,
    nome STRING,
    idade_gestante INT64,
    numero_gestacao INT64,
    data_inicio DATE,
    data_fim DATE,
    data_fim_efetiva DATE,
    dpp DATE,
    fase_atual STRING,
    trimestre_atual_gestacao STRING,
    equipe_nome STRING,
    clinica_nome STRING
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual;


-- Inserir snapshot na tabela acumulativa
INSERT INTO `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
SELECT * FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`;


-- ============================================================
-- EXEMPLO 5: Análise temporal - Evolução de gestações
-- ============================================================

-- Ver evolução de uma gestação específica ao longo do tempo
SELECT
    data_snapshot,
    id_gestacao,
    nome,
    fase_atual,
    trimestre_atual_gestacao,
    data_inicio,
    dpp,
    DATE_DIFF(data_snapshot, data_inicio, WEEK) as semanas_gestacao
FROM `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
WHERE id_gestacao = 'ID_GESTACAO_EXEMPLO'
ORDER BY data_snapshot;


-- Ver mudanças de fase ao longo do tempo (agregado)
SELECT
    data_snapshot,
    fase_atual,
    COUNT(*) as total,
    COUNT(DISTINCT id_paciente) as pacientes_unicas
FROM `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
GROUP BY data_snapshot, fase_atual
ORDER BY data_snapshot, fase_atual;


-- Comparar trimestres entre snapshots
SELECT
    data_snapshot,
    trimestre_atual_gestacao,
    COUNT(*) as total_gestacoes
FROM `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot, trimestre_atual_gestacao
ORDER BY data_snapshot,
    CASE trimestre_atual_gestacao
        WHEN '1º trimestre' THEN 1
        WHEN '2º trimestre' THEN 2
        WHEN '3º trimestre' THEN 3
        ELSE 4
    END;


-- ============================================================
-- EXEMPLO 6: Loop automático para gerar histórico mensal
-- ============================================================
-- Script para gerar histórico automaticamente para um período

DECLARE data_inicial DATE DEFAULT DATE('2024-01-31');
DECLARE data_final DATE DEFAULT DATE('2024-12-31');
DECLARE data_atual DATE;

SET data_atual = data_inicial;

WHILE data_atual <= data_final DO
    -- Executar procedimento para o último dia do mês
    CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);

    -- Inserir na tabela acumulativa
    INSERT INTO `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
    SELECT * FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`;

    -- Avançar para o último dia do próximo mês
    SET data_atual = LAST_DAY(DATE_ADD(data_atual, INTERVAL 1 MONTH));
END WHILE;


-- ============================================================
-- EXEMPLO 7: Comparação entre dois momentos no tempo
-- ============================================================

-- Ver gestações que mudaram de fase entre duas datas
WITH
    snapshot_anterior AS (
        SELECT *
        FROM `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
        WHERE data_snapshot = DATE('2024-01-31')
    ),
    snapshot_atual AS (
        SELECT *
        FROM `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
        WHERE data_snapshot = DATE('2024-02-29')
    )
SELECT
    a.id_gestacao,
    a.nome,
    ant.fase_atual AS fase_janeiro,
    a.fase_atual AS fase_fevereiro,
    ant.trimestre_atual_gestacao AS trimestre_janeiro,
    a.trimestre_atual_gestacao AS trimestre_fevereiro
FROM snapshot_atual a
LEFT JOIN snapshot_anterior ant ON a.id_gestacao = ant.id_gestacao
WHERE ant.fase_atual != a.fase_atual
   OR ant.trimestre_atual_gestacao != a.trimestre_atual_gestacao;


-- ============================================================
-- DICAS DE USO
-- ============================================================

-- 1. Para construir histórico diário:
--    Execute o procedimento todos os dias com a data correspondente

-- 2. Para reconstruir histórico passado:
--    Execute em loop para todas as datas desejadas

-- 3. Para análise de tendências:
--    Use a tabela acumulativa com agregações temporais

-- 4. Para otimizar performance:
--    - Use particionamento por data_snapshot
--    - Use clustering por id_paciente e fase_atual
--    - Considere materialized views para consultas frequentes
