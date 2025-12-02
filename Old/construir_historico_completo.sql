-- ============================================================
-- Script Completo para Construção do Histórico de Pré-Natal
-- ============================================================
-- Este script executa TODOS os procedimentos parametrizados na ordem correta
-- para construir o histórico completo do acompanhamento pré-natal
--
-- ORDEM DE EXECUÇÃO (OBRIGATÓRIA):
-- 1. gestacoes_historico
-- 2. atendimentos_prenatal_aps_historico
-- 3. visitas_acs_gestacao_historico
-- 4. consultas_emergenciais_historico
-- 5. encaminhamentos_historico
-- 6. linha_tempo_historico (agregação final)


-- ============================================================
-- EXEMPLO 1: Executar para uma data específica
-- ============================================================

-- Data de referência para o snapshot
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');

-- Passo 1: Gestações
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_ref);

-- Passo 2: Atendimentos Pré-Natal APS
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_ref);

-- Passo 3: Visitas ACS
CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_ref);

-- Passo 4: Consultas Emergenciais
CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_ref);

-- Passo 5: Encaminhamentos SISREG
CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_ref);

-- Passo 6: Linha do Tempo (Agregação Final)
CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_ref);

-- Verificar resultados
SELECT
    'Gestações' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    'Atendimentos PN APS' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    'Visitas ACS' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    'Consultas Emergenciais' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    'Encaminhamentos' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._encaminhamentos_historico`
WHERE data_snapshot = data_ref

UNION ALL

SELECT
    'Linha do Tempo' AS tabela,
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE data_snapshot = data_ref;


-- ============================================================
-- EXEMPLO 2: Criar tabelas históricas acumulativas
-- ============================================================

-- Tabela 1: Gestações Históricas Acumuladas
CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado` (
    data_snapshot DATE,
    id_gestacao STRING,
    id_paciente STRING,
    cpf STRING,
    nome STRING,
    numero_gestacao INT64,
    idade_gestante INT64,
    data_inicio DATE,
    data_fim DATE,
    data_fim_efetiva DATE,
    dpp DATE,
    fase_atual STRING,
    trimestre_atual_gestacao STRING,
    clinica_nome STRING,
    equipe_nome STRING,
    area_programatica STRING,
    faixa_etaria STRING,
    raca STRING
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual;

-- Tabela 2: Atendimentos PN APS Históricos Acumulados
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

-- Tabela 3: Visitas ACS Históricas Acumuladas
CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us.visitas_acs_historico_acumulado` (
    data_snapshot DATE,
    id_gestacao STRING,
    id_paciente STRING,
    entrada_data DATE,
    nome_estabelecimento STRING,
    nome_profissional STRING,
    numero_visita INT64
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente;

-- Tabela 4: Consultas Emergenciais Históricas Acumuladas
CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us.consultas_emergenciais_historico_acumulado` (
    data_snapshot DATE,
    id_gestacao STRING,
    id_paciente STRING,
    data_consulta DATE,
    idade_gestacional_consulta INT64,
    numero_consulta INT64,
    motivo_atendimento STRING,
    desfecho_atendimento STRING,
    cids_emergencia STRING,
    nome_profissional STRING,
    especialidade_profissional STRING,
    nome_estabelecimento STRING
)
PARTITION BY data_snapshot
CLUSTER BY id_paciente;

-- Tabela 5: Linha do Tempo Histórica Acumulada (Agregação Completa)
CREATE TABLE IF NOT EXISTS `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado` AS
SELECT * FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`
WHERE 1=0;  -- Cria estrutura sem dados

ALTER TABLE `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
ADD COLUMN IF NOT EXISTS data_snapshot DATE;

-- Configurar particionamento
ALTER TABLE `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
SET OPTIONS (
  partition_expiration_days = NULL,
  require_partition_filter = TRUE
);


-- ============================================================
-- EXEMPLO 3: Loop para construir série histórica mensal
-- ============================================================

DECLARE data_inicial DATE DEFAULT DATE('2024-01-31');
DECLARE data_final DATE DEFAULT DATE('2024-12-31');
DECLARE data_atual DATE;

SET data_atual = data_inicial;

WHILE data_atual <= data_final DO
    -- Executar todos os procedimentos na ordem
    CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_atual);

    -- Inserir nas tabelas acumulativas
    INSERT INTO `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
    SELECT * FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`;

    INSERT INTO `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
    SELECT * FROM `rj-sms-sandbox.sub_pav_us._atendimentos_prenatal_aps_historico`;

    INSERT INTO `rj-sms-sandbox.sub_pav_us.visitas_acs_historico_acumulado`
    SELECT * FROM `rj-sms-sandbox.sub_pav_us._visitas_acs_gestacao_historico`;

    INSERT INTO `rj-sms-sandbox.sub_pav_us.consultas_emergenciais_historico_acumulado`
    SELECT * FROM `rj-sms-sandbox.sub_pav_us._consultas_emergenciais_historico`;

    INSERT INTO `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
    SELECT * FROM `rj-sms-sandbox.sub_pav_us._linha_tempo_historico`;

    -- Avançar para o último dia do próximo mês
    SET data_atual = LAST_DAY(DATE_ADD(data_atual, INTERVAL 1 MONTH));
END WHILE;


-- ============================================================
-- VALIDAÇÃO DE CONSISTÊNCIA
-- ============================================================

-- Verificar se todos os snapshots têm dados em todas as tabelas
WITH snapshots_por_tabela AS (
    SELECT DISTINCT data_snapshot, 'gestacoes' AS tabela
    FROM `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`

    UNION DISTINCT

    SELECT DISTINCT data_snapshot, 'atendimentos_pn'
    FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`

    UNION DISTINCT

    SELECT DISTINCT data_snapshot, 'visitas_acs'
    FROM `rj-sms-sandbox.sub_pav_us.visitas_acs_historico_acumulado`

    UNION DISTINCT

    SELECT DISTINCT data_snapshot, 'consultas_emergenciais'
    FROM `rj-sms-sandbox.sub_pav_us.consultas_emergenciais_historico_acumulado`

    UNION DISTINCT

    SELECT DISTINCT data_snapshot, 'linha_tempo'
    FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
)
SELECT
    data_snapshot,
    COUNT(DISTINCT tabela) AS tabelas_com_dados,
    STRING_AGG(tabela, ', ' ORDER BY tabela) AS tabelas_presentes
FROM snapshots_por_tabela
GROUP BY data_snapshot
HAVING COUNT(DISTINCT tabela) < 5  -- Alerta se não tiver as 5 tabelas
ORDER BY data_snapshot;


-- ============================================================
-- ANÁLISES TEMPORAIS EXEMPLO
-- ============================================================

-- Evolução do total de gestações ativas ao longo do tempo
SELECT
    data_snapshot,
    COUNT(*) AS total_gestacoes,
    COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas,
    COUNTIF(fase_atual = 'Puerpério') AS em_puerperio,
    COUNTIF(fase_atual = 'Encerrada') AS encerradas,
    AVG(idade_gestante) AS idade_media
FROM `rj-sms-sandbox.sub_pav_us.gestacoes_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;

-- Evolução da cobertura de consultas pré-natal
SELECT
    data_snapshot,
    COUNT(DISTINCT id_gestacao) AS gestacoes_com_consulta,
    COUNT(*) AS total_consultas,
    AVG(numero_consulta) AS media_consultas_por_gestacao,
    COUNTIF(numero_consulta >= 6) AS com_6_ou_mais_consultas
FROM `rj-sms-sandbox.sub_pav_us.atendimentos_prenatal_historico_acumulado`
GROUP BY data_snapshot
ORDER BY data_snapshot;

-- Evolução do controle de hipertensão
SELECT
    data_snapshot,
    COUNT(*) AS total_gestantes,
    COUNTIF(hipertensao_total = 1) AS com_hipertensao,
    COUNTIF(tem_anti_hipertensivo = 1) AS com_medicacao,
    COUNTIF(tem_encaminhamento_has = 1) AS encaminhadas_alto_risco,
    AVG(qtd_pas_alteradas) AS media_pas_alteradas
FROM `rj-sms-sandbox.sub_pav_us.linha_tempo_historico_acumulado`
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot
ORDER BY data_snapshot;


-- ============================================================
-- DICAS DE PERFORMANCE
-- ============================================================

-- 1. Execute em horários de baixo uso para grandes volumes
-- 2. Use particionamento por data_snapshot para queries temporais
-- 3. Use clustering para otimizar filtros por id_paciente e fase_atual
-- 4. Considere materializar tabelas intermediárias para análises frequentes
-- 5. Execute validações de consistência após cada carga

-- ============================================================
-- TROUBLESHOOTING
-- ============================================================

-- Se houver erro em alguma tabela, verificar:
-- 1. Se o procedimento anterior foi executado com sucesso
-- 2. Se a data_snapshot está presente na tabela dependente
-- 3. Se há dados suficientes para aquela data específica

-- Exemplo de verificação de dependência:
SELECT
    'Gestações' AS tabela_origem,
    COUNT(DISTINCT id_gestacao) AS registros_disponiveis
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31');
