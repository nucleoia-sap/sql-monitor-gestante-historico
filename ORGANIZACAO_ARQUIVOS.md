# Organização de Arquivos - Histórico de Atendimentos

**Data da organização**: 2025-12-03

## Estrutura Atual

### Raiz (Arquivos Ativos)

#### Procedures SQL (Sistema Principal)
1. `1_gestacoes_historico.sql` - ✅ Procedure 1: Identificação de gestações (V1 oficial)
2. `2_atd_prenatal_aps_historico.sql` - Procedure 2: Atendimentos pré-natal
3. `3_visitas_acs_gestacao_historico.sql` - Procedure 3: Visitas ACS
4. `4_consultas_emergenciais_historico.sql` - Procedure 4: Consultas emergenciais
5. `5_encaminhamentos_historico.sql` - Procedure 5: Encaminhamentos alto risco
6. `6_linha_tempo_historico.sql` - Procedure 6: Agregação completa

#### Scripts de Execução
- `executar_pipeline_datas_customizadas.sql` - ⭐ Script principal de execução em lote
- `teste_procedimentos_3_a_6.sql` - Script de testes integrados

#### Documentação Ativa
- `CLAUDE.md` - Instruções principais do projeto para Claude Code
- `QUICK_START.md` - Guia rápido de início (5 minutos)
- `GUIA_EXECUCAO_LOTE.md` - Guia de execução em lote
- `README_HISTORICO_COMPLETO.md` - Documentação completa do sistema
- `README_TESTES.md` - Guia de testes e validação
- `README_ATENDIMENTOS_HISTORICO.md` - Documentação de atendimentos pré-natal
- `README_VALIDACAO_MODA.md` - ✅ Documentação da validação da lógica de MODA (atual)
- `RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md` - Relatório de testes dos procedures 3-6
- `INDICE_DOCUMENTACAO.md` - Índice de toda documentação

### Pastas

#### `/SQL_original`
Versões originais não-históricas (tempo real, sem parametrização)
- Mantido como referência

#### `/SQL_histórico`
Versões históricas antigas (se existirem)
- Mantido como referência

#### `/tentativas_descartadas`
Tentativas recentes descartadas (V2, investigações, etc.)
- Criada em 2025-12-03 para arquivar tentativa V2 de agrupamento por data_atendimento

#### `/Old`
Arquivos antigos organizados em subpastas:

##### `/Old/versoes_antigas`
- `gestante_historico_V4.sql` - Versão 4 antiga (substituída por V1 atual)

##### `/Old/analises_antigas`
- `analise_query_teste.sql` - Análise de query de teste (concluída)
- `ANALISE_RESULTADOS_QUERY_TESTE.md` - Resultados da análise (concluída)
- `check_casos_corrigidos.sql` - Verificação de casos corrigidos (concluída)
- `query_analise_estatistica.sql` - Query de análise estatística (concluída)

##### `/Old/testes_antigos`
- `query_teste_gestacoes.sql` - Query de teste de gestações (concluída)
- `teste_duplicacoes_moda.sql` - Teste de duplicações na lógica de MODA (concluído)
- `validacao_deduplicacao.sql` - Validação de deduplicação (concluída)
- `validacao_logica_moda_dum.sql` - Validação antiga da lógica de MODA/DUM (concluída)
- `validacao_query_teste.sql` - Validação de query de teste (concluída)

##### `/Old/documentacao_antiga`
- `CORRECAO_CONCEITUAL_HISTORICO.md` - Documentação de correção conceitual antiga
- `CORRECAO_V2_FIM_GESTACAO.md` - Documentação de correção V2 fim gestação
- `HISTORICO_CORRECOES_COMPLETO.md` - Histórico completo de correções antigas
- `INSTRUCOES_TESTE.md` - Instruções de teste antigas (substituídas por README_TESTES.md)
- `REGRAS_DEFINITIVAS_V3_CORRIGIDO.md` - Regras definitivas V3 corrigidas (antigas)
- `REGRAS_DEFINITIVAS_V3.md` - Regras definitivas V3 (antigas)
- `RELATORIO_CORRECAO_DEDUPLICACAO.md` - Relatório de correção de deduplicação
- `RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md` - Relatório de testes de outubro (números desatualizados: 293K gestações)

## Histórico de Mudanças

### 2025-12-03 - Organização Completa (Fase 1: SQL + MD desatualizados)
**Motivação**: Limpar arquivos antigos após validação da V1 como solução oficial

#### Fase 1: Arquivos SQL e análises
**Arquivos movidos para /Old**: 17 arquivos
- 1 versão antiga de procedure
- 4 análises concluídas
- 5 testes concluídos
- 7 documentações antigas

#### Fase 2: Arquivos .md desatualizados
**Arquivo movido adicional**: 1 arquivo
- `RELATORIO_TESTES_PROCEDIMENTOS_3_A_6.md` → `/Old/documentacao_antiga/`
  - **Motivo**: Mostra 293.382 gestações (número desatualizado da lógica antiga)
  - **Data do arquivo**: 28 de outubro (antes da mudança para lógica MODA)
  - **Data de referência usada**: 2024-10-31 (diferente das datas atuais)

**Total de arquivos movidos para /Old**: 18 arquivos

**Arquivos .md mantidos na raiz**: 9 arquivos
- ✅ `CLAUDE.md` - Instruções principais (atualizado com lógica MODA em 3/dez)
- ✅ `README_VALIDACAO_MODA.md` - Nova documentação da validação MODA (3/dez)
- ✅ `ORGANIZACAO_ARQUIVOS.md` - Este arquivo (3/dez)
- ✅ `INDICE_DOCUMENTACAO.md` - Índice de documentação (2/dez)
- ✅ `QUICK_START.md` - Guia rápido genérico (não menciona lógica específica)
- ✅ `GUIA_EXECUCAO_LOTE.md` - Guia de execução genérico
- ✅ `README_HISTORICO_COMPLETO.md` - Documentação arquitetura geral
- ✅ `README_TESTES.md` - Guia de COMO testar (não resultados específicos)
- ✅ `README_ATENDIMENTOS_HISTORICO.md` - Documentação do procedure 2

**Arquivos SQL na raiz**: 8 arquivos
- 6 procedures SQL (sistema principal)
- 2 scripts de execução (`executar_pipeline_datas_customizadas.sql`, `teste_procedimentos_3_a_6.sql`)

**Resultado**: Raiz limpa com apenas arquivos necessários para operação e manutenção do sistema

## Critérios de Organização

### Mantido na Raiz
- ✅ Procedures SQL atuais (1-6)
- ✅ Scripts de execução ativos
- ✅ Documentação atualizada e relevante
- ✅ Guias de uso e referência

### Movido para /Old
- ❌ Versões antigas de procedures (substituídas)
- ❌ Análises já concluídas e não mais necessárias
- ❌ Testes executados e validados
- ❌ Documentação de correções antigas (histórico)
- ❌ Regras e relatórios superados por versões mais recentes

## Notas Importantes

### V1 como Solução Oficial
A versão atual `1_gestacoes_historico.sql` (V1) foi validada com ~28.000 gestações (número esperado).
- **V4 antiga**: Movida para `/Old/versoes_antigas/`
- **V2 tentativa**: Movida para `/tentativas_descartadas/` (criou 183% mais gestações - incorreta)

### Documentação Consolidada
- `README_VALIDACAO_MODA.md` substitui análises antigas de MODA/DUM
- `README_TESTES.md` substitui `INSTRUCOES_TESTE.md`
- `INDICE_DOCUMENTACAO.md` centraliza acesso a toda documentação

### Referências Preservadas
Pastas `/SQL_original` e `/SQL_histórico` mantidas como referência técnica e histórica.
