# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Sistema de Histórico de Atendimentos Pré-Natal**
Complete historical snapshot system for prenatal care tracking in Rio de Janeiro's municipal health network.

**Purpose**: Reconstruct temporal states of pregnancy monitoring system, enabling historical analysis of prenatal care coverage, clinical conditions, and health outcomes.

**Technology Stack**: BigQuery SQL (Google Cloud Platform)

## Getting Started

### Quick Start (5 minutes)

**For batch execution (recommended):**

1. **Create procedures** (one-time setup):
```bash
# Via BigQuery CLI
bq query --use_legacy_sql=false < "gestante_historico.sql"
bq query --use_legacy_sql=false < "2_atd_prenatal_aps_historico.sql"
bq query --use_legacy_sql=false < "3_visitas_acs_gestacao_historico.sql"
bq query --use_legacy_sql=false < "4_consultas_emergenciais_historico.sql"
bq query --use_legacy_sql=false < "5_encaminhamentos_historico.sql"
bq query --use_legacy_sql=false < "6_linha_tempo_historico.sql"
```

Or copy/paste each file into BigQuery Console manually.

2. **Configure dates** in `executar_pipeline_datas_customizadas.sql` (lines 19-42):
```sql
DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-10-31')  -- Start with 1 date for testing
];
```

3. **Execute** the complete script in BigQuery Console

See `QUICK_START.md` for detailed guide.

## Database Context

- **Database Type**: BigQuery (Google Cloud Platform)
- **Project**: `rj-sms-sandbox.sub_pav_us`
- **Domain**: Healthcare/Prenatal care - Public Health Data (PHI/LGPD protected)
- **Primary Focus**: Historical reconstruction of pregnancy attendance records

## Project Structure

### Directory Organization

```
Histórico de atendimentos/
├── CLAUDE.md                                    # This file
├── QUICK_START.md                               # 5-minute quick start guide
├── README_HISTORICO_COMPLETO.md                 # Complete system documentation (PT)
├── GUIA_EXECUCAO_LOTE.md                        # Batch execution guide (PT)
│
├── executar_pipeline_datas_customizadas.sql     # ⭐ RECOMMENDED: Batch execution script
├── construir_historico_completo.sql             # Manual execution script with examples
├── teste_procedimentos_3_a_6.sql                # Comprehensive test script
│
├── gestante_historico.sql                       # Procedure 1: Pregnancy identification
├── 2_atd_prenatal_aps_historico.sql            # Procedure 2: Prenatal visits
├── 3_visitas_acs_gestacao_historico.sql        # Procedure 3: ACS visits
├── 4_consultas_emergenciais_historico.sql      # Procedure 4: Emergency visits
├── 5_encaminhamentos_historico.sql             # Procedure 5: High-risk referrals
├── 6_linha_tempo_historico.sql                 # Procedure 6: Complete aggregation
│
├── README_TESTES.md                             # Testing guide (PT)
├── README_ATENDIMENTOS_HISTORICO.md            # Prenatal visits documentation (PT)
├── RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md     # Test report (PT)
├── INSTRUCOES_TESTE.md                         # Test instructions (PT)
│
└── SQL_original/                                # Original non-historical versions
    ├── 1_gestacoes.sql
    ├── 2_atd_prenatal_aps.sql
    ├── 3_visitas_acs_gestacao.sql
    ├── 4_consultas_emergenciais.sql
    ├── 5_encaminhamentos.sql
    ├── 6_linha_tempo.sql
    └── 7_categorias_risco.sql
```

### Historical vs Original Versions

- **Original** (`SQL_original/`): Real-time views using `CURRENT_DATE()`, no time-travel capability
- **Historical** (root): Parametrized procedures accepting `data_referencia DATE` for point-in-time snapshots
- **Key Difference**: Historical versions enable temporal analysis by reconstructing system state at specific dates

## Architecture

### Pipeline Structure

The system consists of 6 parametrized stored procedures executed sequentially:

```
data_referencia → 1_gestacoes_historico
                      ↓
                  2_atd_prenatal_aps_historico
                      ↓
        ┌─────────────┼─────────────────┐
        ↓             ↓                 ↓
  3_visitas_acs  4_consultas_emerg  5_encaminhamentos
        ↓             ↓                 ↓
        └─────────────┼─────────────────┘
                      ↓
              6_linha_tempo_historico
```

### Key Files & Procedures

| File | Procedure | Output Table | Purpose |
|------|-----------|--------------|---------|
| `gestante_historico.sql` | `proced_1_gestacoes_historico` | `_gestacoes_historico` | Identify and classify pregnancies |
| `2_atd_prenatal_aps_historico.sql` | `proced_2_atd_prenatal_aps_historico` | `_atendimentos_prenatal_aps_historico` | Prenatal SOAP visits with vitals |
| `3_visitas_acs_gestacao_historico.sql` | `proced_3_visitas_acs_gestacao_historico` | `_visitas_acs_gestacao_historico` | Community health agent visits |
| `4_consultas_emergenciais_historico.sql` | `proced_4_consultas_emergenciais_historico` | `_consultas_emergenciais_historico` | Emergency department visits |
| `5_encaminhamentos_historico.sql` | `proced_5_encaminhamentos_historico` | `_encaminhamentos_historico` | High-risk referrals (SISREG) |
| `6_linha_tempo_historico.sql` | `proced_6_linha_tempo_historico` | `_linha_tempo_historico` | Complete aggregation with indicators |

### Documentation Files

- **`QUICK_START.md`**: 5-minute getting started guide (Portuguese)
- **`README_HISTORICO_COMPLETO.md`**: Complete system documentation (Portuguese)
- **`GUIA_EXECUCAO_LOTE.md`**: Batch execution guide with use cases (Portuguese)
- **`README_ATENDIMENTOS_HISTORICO.md`**: Prenatal visits documentation (Portuguese)
- **`README_TESTES.md`**: Testing guide with validation queries (Portuguese)
- **`RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md`**: Complete test report with results (Portuguese)

## Core Concepts

### Parametrization Strategy

All procedures accept `data_referencia DATE` parameter to generate point-in-time snapshots:

```sql
CALL proced_1_gestacoes_historico(DATE('2024-10-31'));
```

**Key Changes from Original**:
- Replace `CURRENT_DATE()` with `data_referencia` parameter
- Change source from `_gestacoes` to `_gestacoes_historico WHERE data_snapshot = data_referencia`
- Add `data_snapshot` column to all output tables

### Dependency Chain

**CRITICAL**: Procedures MUST execute in order:
1. Gestações (base for all others)
2. Atendimentos PN APS (depends on gestações)
3. Visitas ACS (depends on gestações) - can parallelize with 4,5
4. Consultas Emergenciais (depends on gestações) - can parallelize with 3,5
5. Encaminhamentos (depends on gestações) - can parallelize with 3,4
6. Linha Tempo (depends on all previous)

### Business Logic

#### Pregnancy Identification (Procedure 1)

**✅ CRITICAL UPDATE (2025-12-03)**: Pregnancy start date logic completely revised

**ICD Codes**: Z32.1 (confirmed pregnancy), Z34% (normal supervision), Z35% (high-risk)

**DUM (Data da Última Menstruação) Estimation - NEW LOGIC**:
- **Method**: MODE (most frequent value) of `c.data_diagnostico` across all visits
- **Rationale**:
  - 1st visit: DUM imprecise (patient recall)
  - Subsequent visits: DUM refined progressively
  - After ultrasound: DUM becomes accurate and **repeats in all future visits**
  - **Most frequent date** = best consolidated estimate (validated by ultrasound)
- **Historical Context**: Does NOT filter by `situacao_cid = 'ATIVO'` because in historical snapshots, completed pregnancies will have `RESOLVIDO` status
- **Implementation**:
  ```sql
  -- Count frequency of each data_evento per patient
  -- Select date with HIGHEST frequency (MODE)
  -- In case of tie, use most recent date
  ```

**Grouping Window**: 60 days to merge multiple pregnancies into single pregnancy record

**Auto-close**: 299 days after start if no end date

**Phase Classification**:
  - Gestação (Pregnancy): data_inicio ≤ data_referencia AND (data_fim IS NULL OR data_fim ≥ data_referencia) AND ≤ 299 days
  - Puerpério (Postpartum): data_fim < data_referencia ≤ (data_fim + 42 days)
  - Encerrada (Closed): data_referencia > (data_fim + 42 days) OR > 299 days without end

**Key Difference from Original**:
- ❌ **OLD**: Used first ACTIVE CID date → incorrect for historical data
- ✅ **NEW**: Uses MODE of all CID dates → clinically validated, works with historical snapshots

#### Prenatal Visits (Procedure 2)
- **Initial Weight**: Measured -180 to +84 days from pregnancy start
- **Height**: Mode of measurements between 1 year before and pregnancy end
- **BMI Classification**: Underweight (<18), Normal (18-24.9), Overweight (25-29.9), Obese (≥30)
- **Gestational Age (IG)**: Weeks from pregnancy start to visit date
- **Trimester**: T1 (≤13 weeks), T2 (14-27 weeks), T3 (≥28 weeks)
- **Weight Gain**: Current weight - initial weight

#### Hypertension Analysis (Procedure 6)
- **Altered BP**: ≥140/90 mmHg
- **Severe BP**: >160/110 mmHg
- **Safe Medications**: Methyldopa, Hydralazine, Nifedipine
- **Contraindicated**: ACE inhibitors, ARBs, Atenolol, etc.
- **Probable Undiagnosed**: ≥2 altered BPs OR severe BP OR antihypertensive prescription WITHOUT formal diagnosis CID

## Common Commands

### ⭐ Execute Pipeline for Multiple Dates (RECOMMENDED)

**Use the batch script for processing multiple dates efficiently:**

```sql
-- Edit executar_pipeline_datas_customizadas.sql
-- Configure your date list in the CONFIGURAÇÃO USUÁRIO section

DECLARE datas_processar ARRAY<DATE> DEFAULT [
    DATE('2024-01-31'),
    DATE('2024-02-29'),
    DATE('2024-03-31')
    -- Add your dates here
];

-- Then execute the complete script in BigQuery Console
-- The script will:
-- 1. Create accumulative table (if not exists)
-- 2. Process each date sequentially (all 6 procedures)
-- 3. Materialize ONLY table 6 (linha_tempo_historico)
-- 4. Generate detailed logs and final report
```

**Benefits**:
- ✅ Processes multiple dates automatically
- ✅ Only materializes table 6 (saves storage)
- ✅ Error handling per date (continues on failure)
- ✅ Progress tracking with detailed logs
- ✅ Final consolidated report

See `GUIA_EXECUCAO_LOTE.md` for complete usage guide.

### Execute Complete Pipeline for Single Date

```sql
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(DATE('2024-10-31'));
CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(DATE('2024-10-31'));
```

### Build Monthly Historical Series

```sql
DECLARE data_inicial DATE DEFAULT DATE('2024-01-31');
DECLARE data_final DATE DEFAULT DATE('2024-12-31');
DECLARE data_atual DATE;

SET data_atual = data_inicial;

WHILE data_atual <= data_final DO
    -- Execute all 6 procedures
    CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_2_atd_prenatal_aps_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_3_visitas_acs_gestacao_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_4_consultas_emergenciais_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_5_encaminhamentos_historico`(data_atual);
    CALL `rj-sms-sandbox.sub_pav_us.proced_6_linha_tempo_historico`(data_atual);

    -- Insert into cumulative tables
    INSERT INTO linha_tempo_historico_acumulado
    SELECT * FROM _linha_tempo_historico;

    SET data_atual = LAST_DAY(DATE_ADD(data_atual, INTERVAL 1 MONTH));
END WHILE;
```

### Query Historical Data

```sql
-- Temporal evolution of prenatal coverage
SELECT
    data_snapshot,
    COUNT(DISTINCT id_gestacao) AS pregnancies_with_visits,
    COUNT(*) AS total_visits,
    AVG(numero_consulta) AS avg_visits_per_pregnancy
FROM atendimentos_prenatal_historico_acumulado
GROUP BY data_snapshot
ORDER BY data_snapshot;

-- Hypertension control over time
SELECT
    data_snapshot,
    COUNT(*) AS total_pregnant,
    COUNTIF(hipertensao_total = 1) AS with_hypertension,
    COUNTIF(tem_anti_hipertensivo_seguro = 1) AS with_safe_medication,
    AVG(percentual_pa_controlada) AS avg_bp_control_pct
FROM linha_tempo_historico_acumulado
WHERE fase_atual = 'Gestação'
GROUP BY data_snapshot
ORDER BY data_snapshot;
```

## Development Workflow

### Creating New Historical Procedures

When converting existing procedures to historical versions:

1. **Add parameter**: `CREATE OR REPLACE PROCEDURE proc_name(data_referencia DATE)`
2. **Replace CURRENT_DATE()**: Find all occurrences and replace with `data_referencia`
3. **Update sources**: Change from `_table` to `_table_historico WHERE data_snapshot = data_referencia`
4. **Add snapshot column**: Include `data_referencia AS data_snapshot` in final SELECT
5. **Test**: Execute with specific date and verify results

### Testing Historical Procedures

⚠️ **Comprehensive Testing Script Available**: Use `teste_procedimentos_3_a_6.sql` for complete testing

See `README_TESTES.md` for detailed testing guide with:
- Pre-requisite validation
- Individual procedure testing
- Consistency checks between tables
- Performance metrics
- Common issues and solutions

**Quick Test Example**:
```sql
-- Test single procedure
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2024-10-31'));

-- Verify results
SELECT
    data_snapshot,
    COUNT(*) AS total,
    COUNT(DISTINCT id_paciente) AS unique_patients,
    COUNTIF(fase_atual = 'Gestação') AS active_pregnancies
FROM `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
WHERE data_snapshot = DATE('2024-10-31')
GROUP BY data_snapshot;
```

**Testing Status**:
- ✅ Procedure 1 (gestacoes_historico): Tested and validated on 2024-10-31
- ✅ Procedure 2 (atd_prenatal_aps_historico): Tested and validated on 2024-10-31
- ✅ Procedure 3 (visitas_acs_gestacao_historico): Tested and validated on 2024-10-31 (**1,817,752 records**)
- ✅ Procedure 4 (consultas_emergenciais_historico): Tested and validated on 2024-10-31 (**167,098 records**)
- ✅ Procedure 5 (encaminhamentos_historico): Tested and validated on 2024-10-31 (**31,993 records**)
- ✅ Procedure 6 (linha_tempo_historico): Tested and validated on 2024-10-31 (**85,633 gestations aggregated**)

**Latest Test Results** (2025-10-28):
- Complete test report available in `RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md`
- All 6 procedures created and executed successfully via BigQuery CLI
- Referential integrity validated: **0 orphan records**
- Fixed schema error in Procedure 6 (removed non-existent fields from CTE `categorias_risco_gestacional`)

### Validation Checks

```sql
-- Check all tables have data for same snapshot
SELECT
    data_snapshot,
    COUNT(DISTINCT tabela) AS tables_with_data,
    STRING_AGG(tabela, ', ') AS tables_present
FROM (
    SELECT DISTINCT data_snapshot, 'gestacoes' AS tabela FROM gestacoes_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'atendimentos' FROM atendimentos_prenatal_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'visitas_acs' FROM visitas_acs_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'consultas_emerg' FROM consultas_emergenciais_historico_acumulado
    UNION ALL
    SELECT DISTINCT data_snapshot, 'linha_tempo' FROM linha_tempo_historico_acumulado
)
GROUP BY data_snapshot
HAVING COUNT(DISTINCT tabela) < 5
ORDER BY data_snapshot;
```

## Data Protection & Compliance

⚠️ **CRITICAL**: This project handles Protected Health Information (PHI)

### LGPD/HIPAA Compliance
- All patient data must be handled according to Brazilian LGPD regulations
- Never expose CPF, full names, or addresses in logs or outputs
- Always use aggregated data for analysis when possible
- Implement proper access controls and audit logs

### Security Best Practices
- Use parameterized queries only (all procedures use parameters)
- Never concatenate user input into SQL
- Restrict table access to authorized personnel
- Log all data access for audit purposes

## Performance Considerations

### Partitioning Strategy
All cumulative tables should use:
```sql
PARTITION BY data_snapshot
CLUSTER BY id_paciente, fase_atual
```

### Query Optimization
- Always filter by `data_snapshot` to leverage partitioning
- Use clustering columns (id_paciente, fase_atual) in WHERE clauses
- Materialize frequently used aggregations
- Execute large historical builds during off-peak hours

### Resource Management
- Complete pipeline for single date: ~5-10 minutes
- Monthly series (12 snapshots): ~1-2 hours
- Consider increasing processing slots for large volumes

## Troubleshooting

### Common Issues

**Error: "Table not found: _gestacoes_historico"**
- **Cause**: Procedure 1 not executed or failed
- **Solution**: Execute `proced_1_gestacoes_historico` first

**Error: "Procedure not found"**
- **Cause**: Procedures not created in BigQuery
- **Solution**: Run procedure creation scripts via BigQuery CLI or Console

**Empty results in downstream table**
- **Cause**: Missing snapshot in dependency table
- **Solution**: Verify all previous procedures executed successfully

**Performance degradation**
- **Cause**: Missing partitioning/clustering, large data volume
- **Solution**: Check table configuration, execute during off-peak hours

**Inconsistent data between tables**
- **Cause**: Partial pipeline execution
- **Solution**: Run consistency validation query, reprocess complete date

**Script interrupted mid-execution**
- **Cause**: Timeout or connection loss
- **Solution**: Check which dates were processed, remove from array, re-run with remaining dates

## Key Indicators

The system enables calculation of:

### Coverage Indicators
- % pregnancies with ≥1 prenatal visit
- % pregnancies with ≥6 visits (Ministry of Health adequacy)
- % early initiation (1st visit in 1st trimester)
- % ACS visit coverage

### Clinical Indicators
- Diabetes prevalence (previous, gestational)
- Hypertension prevalence (previous, pre-eclampsia, undiagnosed)
- HIV, Syphilis, Tuberculosis prevalence
- % adequate weight gain by initial BMI

### Treatment Indicators
- % hypertensive patients with controlled BP
- % safe vs contraindicated antihypertensive use
- % adequate AAS prescription for pre-eclampsia risk
- % folic acid and calcium supplementation

### Outcome Indicators
- Referral to high-risk care rates
- Birth type distribution (vaginal/cesarean/abortion)
- Gestational age at birth
- Team continuity during pregnancy

## Working with this Codebase

### File Naming Conventions
- **Numbered procedures** (1-6): Execute in order
- **`_historico` suffix**: Indicates historical/parametrized version
- **`_acumulado` suffix**: Indicates cumulative/materialized table
- **Portuguese documentation**: Most README files are in Portuguese (PT-BR)

### Code Modification Guidelines
- Never modify dependency order (procedures 1-6 sequence)
- Always test with single date before batch processing
- Maintain `data_snapshot` column in all new tables
- Use parameterized queries (never hardcode dates)
- Follow existing naming patterns (proced_N_name_historico)

### Best Practices for Development
- **Test first**: Always validate with `DATE('2024-10-31')` single date test
- **Version control**: Keep SQL_original/ unchanged as reference
- **Documentation**: Update README files when changing business logic
- **Validation**: Run consistency checks after modifications
- **Performance**: Monitor query costs before large batch operations

## Notes for Future Development

When the project evolves, update this file with:
- New procedures or tables added to pipeline
- Changes to business logic or clinical criteria
- New calculated indicators or metrics
- Integration with dashboards or reporting systems
- Migration or deployment procedures

## Additional Resources

- **Brazilian Ministry of Health**: Cadernos de Atenção Básica nº 32 (Prenatal Care)
- **ICD-10 Codes**: Z30-Z39 (Pregnancy, childbirth and puerperium)
- **LGPD**: Lei Geral de Proteção de Dados (Brazilian data protection law)
- **BigQuery Documentation**: https://cloud.google.com/bigquery/docs
- **BigQuery CLI**: https://cloud.google.com/bigquery/docs/bq-command-line-tool
