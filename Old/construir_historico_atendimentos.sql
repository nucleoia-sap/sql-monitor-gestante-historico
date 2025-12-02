-- ============================================================
-- Script para Construir Histórico de Atendimentos Pré-Natal
-- ============================================================
-- Este script executa os procedimentos parametrizados em sequência
-- para diferentes datas, permitindo análise temporal

-- ============================================================
-- IMPORTANTE: Executar procedimentos na ordem correta
-- ============================================================
-- 1º) proced_1_gestacoes_historico - Gera snapshot das gestações
-- 2º) proced_2_atd_prenatal_aps_historico - Gera atendimentos baseados no snapshot


-- ============================================================
-- EXEMPLO 1: Snapshot para uma data específica
-- ============================================================

-- Passo 1: Gerar snapshot de gestações
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-10-31'));

-- Passo 2: Gerar atendimentos baseados nesse snapshot
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-10-31'));

-- Verificar resultado
SELECT
    data_snapshot,
    COUNT(*) as total_atendimentos,
    COUNT(DISTINCT id_gestacao) as gestacoes_com_atendimento,
    COUNT(DISTINCT id_paciente) as pacientes_atendidas,
    AVG(numero_consulta) as media_consultas,
    AVG(ganho_peso_acumulado) as media_ganho_peso
FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`
GROUP BY data_snapshot;


-- ============================================================
-- EXEMPLO 2: Construir histórico mensal completo
-- ============================================================

-- Janeiro 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-01-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-01-31'));

-- Fevereiro 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-02-29'));
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-02-29'));

-- Março 2024
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-03-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-03-31'));


-- ============================================================
-- EXEMPLO 3: Tabela histórica acumulativa
-- ============================================================

CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado` (
    data_snapshot DATE,
    id_gestacao STRING,
    id_paciente STRING,
    data_consulta DATE,
    numero_consulta INT64,
    ig_consulta INT64,
    trimestre_consulta INT64,
    fase_atual STRING,
    peso_inicio FLOAT64,
    altura_inicio FLOAT64,
    imc_inicio FLOAT64,
    classificacao_imc_inicio STRING,
    peso FLOAT64,
    imc_consulta FLOAT64,
    ganho_peso_acumulado FLOAT64,
    pressao_sistolica INT64,
    pressao_diastolica INT64,
    descricao_s STRING,
    cid STRING,
    desfecho STRING,
    prescricoes STRING,
    estabelecimento STRING,
    profissional_nome STRING,
    profissional_categoria STRING
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual;


-- Inserir snapshot na tabela acumulativa
INSERT INTO `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
SELECT * FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`;


-- ============================================================
-- EXEMPLO 4: Loop automático para gerar histórico mensal
-- ============================================================

DECLARE data_inicial DATE DEFAULT DATE('2024-01-31');
DECLARE data_final DATE DEFAULT DATE('2024-12-31');
DECLARE data_atual DATE;

SET data_atual = data_inicial;

WHILE data_atual <= data_final DO
    -- Passo 1: Executar procedimento de gestações
    CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);

    -- Passo 2: Executar procedimento de atendimentos
    CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_atual);

    -- Inserir na tabela acumulativa
    INSERT INTO `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
    SELECT * FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`;

    -- Avançar para o último dia do próximo mês
    SET data_atual = LAST_DAY(DATE_ADD(data_atual, INTERVAL 1 MONTH));
END WHILE;


-- ============================================================
-- ANÁLISES COM HISTÓRICO
-- ============================================================

-- Evolução do número de consultas ao longo do tempo
SELECT
    data_snapshot,
    COUNT(*) as total_atendimentos,
    COUNT(DISTINCT id_gestacao) as gestacoes_atendidas,
    AVG(numero_consulta) as media_numero_consulta,
    COUNTIF(numero_consulta = 1) as primeira_consulta,
    COUNTIF(numero_consulta >= 6) as seis_ou_mais_consultas
FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;


-- Evolução do IMC e ganho de peso ao longo do tempo
SELECT
    data_snapshot,
    classificacao_imc_inicio,
    COUNT(*) as total,
    AVG(ganho_peso_acumulado) as ganho_peso_medio,
    AVG(imc_consulta) as imc_medio_consulta
FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
WHERE ganho_peso_acumulado IS NOT NULL
GROUP BY data_snapshot, classificacao_imc_inicio
ORDER BY data_snapshot, classificacao_imc_inicio;


-- Distribuição de consultas por trimestre ao longo do tempo
SELECT
    data_snapshot,
    trimestre_consulta,
    COUNT(*) as total_consultas,
    AVG(ig_consulta) as ig_media
FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
GROUP BY data_snapshot, trimestre_consulta
ORDER BY data_snapshot, trimestre_consulta;


-- Análise de pressão arterial ao longo do tempo
SELECT
    data_snapshot,
    COUNT(*) as total_afericoes,
    AVG(pressao_sistolica) as sistolica_media,
    AVG(pressao_diastolica) as diastolica_media,
    COUNTIF(pressao_sistolica >= 140 OR pressao_diastolica >= 90) as hipertensas
FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
WHERE pressao_sistolica IS NOT NULL
GROUP BY data_snapshot
ORDER BY data_snapshot;


-- Acompanhamento de gestação individual ao longo do tempo
SELECT
    data_snapshot,
    id_gestacao,
    data_consulta,
    numero_consulta,
    ig_consulta,
    peso,
    ganho_peso_acumulado,
    pressao_sistolica,
    pressao_diastolica
FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
WHERE id_gestacao = 'ID_GESTACAO_EXEMPLO'
ORDER BY data_snapshot, data_consulta;


-- Comparação entre dois meses
WITH
    janeiro AS (
        SELECT
            trimestre_consulta,
            COUNT(*) as total,
            AVG(ganho_peso_acumulado) as ganho_peso_medio
        FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
        WHERE data_snapshot = DATE('2024-01-31')
        GROUP BY trimestre_consulta
    ),
    fevereiro AS (
        SELECT
            trimestre_consulta,
            COUNT(*) as total,
            AVG(ganho_peso_acumulado) as ganho_peso_medio
        FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
        WHERE data_snapshot = DATE('2024-02-29')
        GROUP BY trimestre_consulta
    )
SELECT
    j.trimestre_consulta,
    j.total as total_janeiro,
    f.total as total_fevereiro,
    f.total - j.total as diferenca,
    j.ganho_peso_medio as ganho_peso_janeiro,
    f.ganho_peso_medio as ganho_peso_fevereiro
FROM janeiro j
FULL OUTER JOIN fevereiro f ON j.trimestre_consulta = f.trimestre_consulta
ORDER BY trimestre_consulta;


-- ============================================================
-- DICAS DE USO
-- ============================================================

-- 1. SEMPRE executar os procedimentos na ordem:
--    1º) proced_1_gestacoes_historico
--    2º) proced_2_atd_prenatal_aps_historico

-- 2. Para análises temporais, usar a tabela acumulativa
--    com agregações por data_snapshot

-- 3. Para reconstruir histórico, executar em loop
--    para todas as datas desejadas

-- 4. Performance: Use particionamento e clustering
--    para otimizar consultas temporais
