# Validação: Procedimento 1 - Gestações Histórico

## 1. Visão Geral

### Propósito
Script de validação abrangente para o Procedimento 1 (`_gestacoes_historico`), verificando qualidade e correção dos dados de gestações históricas.

### Escopo
- **Valida apenas**: Procedimento 1 - Gestações Histórico
- **Não valida**: Procedimentos 2-6 (fora de escopo)
- **Comportamento**: Report-only (não bloqueia, não alerta automaticamente)
- **Execução**: Manual via BigQuery Console ou `bq` CLI

### O que o Script Faz
- Executa 14 módulos de validação organizados em 5 seções
- Verifica integridade, consistência e lógica de negócio dos dados
- Gera relatório detalhado com status visual (✅❌⚠️⏭️)
- Fornece queries adicionais para investigação de falhas

---

## 2. Pré-requisitos

### Dados Necessários
- Procedimento 1 executado para a data desejada
- Tabela `_gestacoes_historico` populada com dados do snapshot

### Acesso Requerido
- Acesso de leitura a:
  - `rj-sms-sandbox.sub_pav_us._gestacoes_historico`
  - `rj-sms.saude_historico_clinico.paciente`
- Permissão para executar queries no BigQuery

---

## 3. Como Executar

### Opção 1: BigQuery Console (Recomendado)

1. **Abra o BigQuery Console**: https://console.cloud.google.com/bigquery

2. **Configure a data de referência**:
   - Abra o arquivo `validacao_gestacoes_historico.sql`
   - Edite a linha 15:
     ```sql
     DECLARE data_referencia DATE DEFAULT DATE('2025-07-01');
     ```
   - Substitua `'2025-07-01'` pela data que deseja validar

3. **Execute o script completo**:
   - Copie todo o conteúdo do arquivo
   - Cole na janela de query do BigQuery Console
   - Clique em "Executar" (Run)

4. **Aguarde a execução**: ~30-60 segundos para snapshot típico

5. **Analise os resultados**: Revise cada seção do output

### Opção 2: BigQuery CLI

```bash
# Edite a data no arquivo primeiro
vim validacao_gestacoes_historico.sql

# Execute via bq CLI
bq query --use_legacy_sql=false < validacao_gestacoes_historico.sql
```

---

## 4. Estrutura de Validações

### Resumo das Seções

| Seção | Descrição | Módulos | Tipo |
|-------|-----------|---------|------|
| 1. Pré-requisitos | Verificação de existência de dados | 1 | Verificação |
| 2. Validações Críticas | Validações obrigatórias para aprovação | 4 | **CRÍTICO** |
| 3. Qualidade de Dados | Integridade e completude | 5 | Qualidade |
| 4. Lógica de Negócio | Regras de negócio específicas | 4 | Negócio |
| 5. Resumo Consolidado | Visão geral e relatório final | 1 | Resumo |

### Detalhamento dos Módulos

#### SEÇÃO 1: Pré-requisitos

**1.1 - Verificação de Dados**
- **O que valida**: Existência de registros para a data_referencia
- **Threshold**: ≥1 registro
- **Ação em FAIL**: Verificar se Procedimento 1 foi executado

#### SEÇÃO 2: Validações Críticas (OBRIGATÓRIAS)

**2.1 - Duplicatas de id_gestacao**
- **O que valida**: Unicidade de id_gestacao no snapshot
- **Threshold**: 0 duplicatas
- **Ação em FAIL**: Investigar lógica de criação de id_gestacao

**2.2 - Datas Futuras**
- **O que valida**: Nenhuma data_inicio, data_fim ou data_fim_efetiva > data_referencia
- **Threshold**: 0 datas futuras
- **Ação em FAIL**: Verificar filtro temporal no procedimento

**2.3 - Inflação de Contagem**
- **O que valida**: Variação de gestações ativas comparada ao snapshot anterior
- **Thresholds**:
  - SKIP ⏭️: Primeiro snapshot OU snapshot anterior com 0 gestações (sem baseline válido)
  - PASS ✅: ≤ 10% variação
  - WARNING ⚠️: 10-20% variação
  - FAIL ❌: > 20% variação
- **Ação em FAIL**: Investigar mudanças no código ou dados de origem

**2.4 - Classificação de Fases**
- **O que valida**: Fases (Gestação/Puerpério/Encerrada) consistentes com datas
- **Threshold**: 0 classificações incorretas
- **Ação em FAIL**: Verificar lógica de classificação de fases

#### SEÇÃO 3: Qualidade de Dados

**3.1 - Completude de Campos**
- **O que valida**: Presença de valores em id_paciente, data_inicio, fase_atual
- **Threshold**: 0 campos NULL
- **Ação em FAIL**: Verificar query de origem dos dados

**3.2 - Integridade Referencial**
- **O que valida**: Todos os id_paciente existem na tabela de cadastro
- **Threshold**: 0 pacientes órfãos
- **Ação em FAIL**: Investigar sincronização com tabela de pacientes

**3.3 - Coerência Temporal**
- **O que valida**: data_inicio ≤ data_fim (quando ambas existem)
- **Threshold**: 0 incoerências
- **Ação em FAIL**: Verificar lógica de cálculo de data_fim

**3.4 - Lógica Clínica - IG**
- **O que valida**: Idade gestacional (IG) entre 0-44 semanas
- **Thresholds**:
  - PASS ✅: 0 IGs inválidas
  - WARNING ⚠️: ≤5 IGs inválidas
  - FAIL ❌: >5 IGs inválidas
- **Ação em WARNING/FAIL**: Revisar casos clínicos específicos

**3.5 - Distribuição de Fases**
- **O que valida**: Proporção de fases dentro do esperado
- **Esperado**:
  - Gestação: 60-80%
  - Puerpério: 5-15%
  - Encerrada: 10-30%
- **Ação em WARNING**: Avaliar se distribuição reflete realidade

#### SEÇÃO 4: Lógica de Negócio

**4.1 - DUM dentro da Janela 340 dias**
- **O que valida**: data_inicio nos últimos 340 dias para gestações ativas/puerpério
- **Cálculo**: 340 dias = 299 (gestação) + 42 (puerpério) - 1
- **Threshold**: 0 fora da janela
- **Ação em FAIL**: Verificar filtro temporal aplicado após cálculo de DUM

**4.2 - Separação 60 dias entre Gestações**
- **O que valida**: Intervalo mínimo de 60 dias entre gestações da mesma paciente
- **Thresholds**:
  - PASS ✅: 0 gestações próximas
  - WARNING ⚠️: ≤10 gestações próximas
  - FAIL ❌: >10 gestações próximas
- **Ação em WARNING/FAIL**: Revisar lógica de agrupamento de gestações

**4.3 - Auto-encerramento 299 dias**
- **O que valida**: Gestações sem data_fim são auto-encerradas após 299 dias
- **Threshold**: 0 auto-encerramentos incorretos
- **Ação em FAIL**: Verificar lógica de data_fim_efetiva

**4.4 - Transição Puerpério (42 dias)**
- **O que valida**: Transição Puerpério → Encerrada ocorre aos 42 dias pós-parto
- **Threshold**: 0 transições incorretas
- **Ação em FAIL**: Verificar lógica de classificação de fases

---

## 5. Interpretando Resultados

### Status Indicators

| Símbolo | Significado | Ação Requerida |
|---------|-------------|----------------|
| ✅ PASS | Validação bem-sucedida | Nenhuma |
| ❌ FAIL | Validação falhou | **Investigação obrigatória** |
| ⚠️ WARNING | Atenção requerida | Revisar e avaliar |
| ⏭️ SKIP | Não aplicável | Nenhuma (ex: primeiro snapshot) |

### Exemplo de Output

#### Output PASS ✅
```
modulo | validacao                    | status  | valor_esperado | valor_atual | detalhes
2.1    | Duplicatas de id_gestacao   | PASS ✅ | 0              | 0           | Nenhuma duplicata encontrada
```

#### Output FAIL ❌
```
modulo | validacao      | status                          | valor_esperado | valor_atual | detalhes
2.2    | Datas futuras | FAIL ❌ - 3 datas futuras encontradas | 0         | 3           | abc-1 (data_fim no futuro), abc-2 (data_fim no futuro), ...
```

#### Output WARNING ⚠️
```
modulo | validacao              | status                            | valor_esperado | valor_atual | detalhes
2.3    | Inflação de contagem  | WARNING ⚠️ - Distribuição atípica | 25000         | 28500       | Variação: 14.0% | Anterior (2024-06-30): 25000 | Atual: 28500
```

---

## 6. Problemas Comuns e Soluções

### Problema: "Table not found: _gestacoes_historico"

**Causa**: Procedimento 1 não foi executado ou falhou

**Solução**:
```sql
-- Execute o Procedimento 1 primeiro
CALL `rj-sms-sandbox.sub_pav_us.proced_1_gestacoes_historico`(DATE('2025-07-01'));
```

---

### Problema: FAIL em 2.1 (Duplicatas)

**Causa**: Múltiplos registros com mesmo id_gestacao no snapshot

**Solução**:
1. Descomente a query de detalhes no módulo 2.1 (linhas após a validação)
2. Execute para ver registros duplicados completos
3. Investigue lógica de criação de `id_gestacao` no Procedimento 1:
   ```sql
   CONCAT(i.id_paciente, '-', CAST(ROW_NUMBER() OVER (...) AS STRING))
   ```

---

### Problema: FAIL em 2.2 (Datas Futuras)

**Causa**: Eventos com data > data_referencia foram incluídos

**Solução**:
1. Descomente a query de detalhes no módulo 2.2
2. Identifique quais datas estão no futuro (data_inicio, data_fim, data_fim_efetiva)
3. **Correção mais comum**: Verificar filtro temporal na CTE `finais`:
   ```sql
   -- Deve ter este filtro:
   WHERE situacao_cid = 'RESOLVIDO'
     AND data_evento <= data_referencia  -- ✅ Essencial!
   ```

---

### Problema: WARNING em 2.3 (Inflação de Contagem)

**Causa**: Variação de 10-20% em gestações ativas comparado ao snapshot anterior

**Solução**:
1. Avaliar se variação é esperada (ex: campanha de cadastramento, mudança no sistema)
2. Se não esperada:
   - Compare contagem manual:
     ```sql
     SELECT
         data_snapshot,
         COUNTIF(fase_atual = 'Gestação') AS gestacoes_ativas
     FROM _gestacoes_historico
     WHERE data_snapshot IN (data_anterior, data_atual)
     GROUP BY data_snapshot
     ORDER BY data_snapshot;
     ```
   - Investigue mudanças no código do Procedimento 1 entre os snapshots

---

### Problema: FAIL em 2.4 (Classificação de Fases)

**Causa**: Lógica de classificação de fases não está correta

**Solução**:
1. Descomente a query de detalhes no módulo 2.4
2. Revise registros com fase_atual != fase_esperada
3. Verifique lógica no Procedimento 1 (linhas 224-251):
   - Gestação: data_inicio ≤ data_ref AND (data_fim NULL OR data_fim ≥ data_ref) AND ≤299 dias
   - Puerpério: data_fim < data_ref ≤ (data_fim + 42 dias)
   - Encerrada: data_ref > (data_fim + 42 dias) OR > 299 dias sem data_fim

---

### Problema: FAIL em 4.1 (DUM fora da Janela 340 dias)

**Causa**: Filtro temporal aplicado ANTES de calcular data_inicio (DUM)

**Solução**:
**CRÍTICO**: Filtro temporal deve ser aplicado APÓS calcular data_inicio (MODA)

Verificar no Procedimento 1:
```sql
-- ❌ ERRADO: Filtro temporal em eventos_brutos
eventos_brutos AS (
    SELECT ...
    WHERE data_evento >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
)

-- ✅ CORRETO: Filtro temporal APÓS calcular DUM
filtrado_temporal AS (
    SELECT *
    FROM gestacoes_com_fase
    WHERE data_inicio >= DATE_SUB(data_referencia, INTERVAL 340 DAY)
)
```

---

### Problema: WARNING em 4.2 (Janela 60 dias)

**Causa**: Gestações da mesma paciente separadas por <60 dias

**Solução**:
1. Verificar se são casos clínicos reais (ex: gestação gemelar registrada 2x)
2. Se >10 casos, revisar lógica de agrupamento no Procedimento 1:
   ```sql
   -- Verifica janela de 60 dias
   WHEN DATE_DIFF(data_evento, LAG(data_evento) OVER (...), DAY) > 60 THEN 1
   ```

---

## 7. Critérios de Aprovação

### ✅ APROVAÇÃO COMPLETA

**Requisitos**:
- Todas as 4 validações críticas (2.1-2.4): **PASS ✅**
- Nenhum FAIL ❌ em validações de qualidade (3.1-3.5)
- Nenhum FAIL ❌ em validações de negócio (4.1-4.4)

**Ação**: Dados aprovados para uso em análises e dashboards

---

### ⚠️ APROVAÇÃO CONDICIONAL

**Requisitos**:
- Todas as 4 validações críticas (2.1-2.4): **PASS ✅**
- ≤2 WARNING ⚠️ em validações não-críticas (3.x ou 4.x)
- Nenhum FAIL ❌ em qualquer validação

**Ação**:
- Documentar warnings encontrados
- Avaliar impacto nos casos de uso específicos
- Monitorar em próximos snapshots

---

### ❌ REPROVAÇÃO

**Requisitos (qualquer um):**
- Qualquer FAIL ❌ em validações críticas (2.1-2.4)
- >2 FAIL ❌ em validações não-críticas
- >5 WARNING ⚠️ em validações não-críticas

**Ação**:
- **NÃO usar dados** para análises ou dashboards
- Corrigir problemas identificados no Procedimento 1
- Re-executar procedimento após correção
- Re-executar validação

---

## 8. Checklist de Validação

### Antes de Executar

- [ ] Procedimento 1 foi executado para a data desejada
- [ ] Tabela `_gestacoes_historico` tem dados para data_snapshot
- [ ] Configurei `data_referencia` corretamente no script (linha 15)
- [ ] Tenho acesso de leitura às tabelas necessárias

### Durante Execução

- [ ] Script executou sem erros de sintaxe
- [ ] Todos os 14 módulos retornaram resultados
- [ ] Output foi salvo ou copiado para análise

### Após Execução

- [ ] Revisados resultados da SEÇÃO 2 (Validações Críticas)
- [ ] Investigados todos os FAIL ❌ usando queries de detalhes
- [ ] Documentados todos os WARNING ⚠️ encontrados
- [ ] Aplicados critérios de aprovação (seção 7)

### Próximos Passos

Se **APROVADO**:
- [ ] Dados podem ser usados em análises
- [ ] Executar Procedimentos 2-6 se necessário
- [ ] Atualizar dashboards com novos dados

Se **REPROVADO**:
- [ ] Identificadas causas raiz dos FAILs
- [ ] Corrigido código do Procedimento 1
- [ ] Re-executado Procedimento 1
- [ ] Re-executada validação completa

---

## 9. Referências

### Documentos Relacionados
- `1_gestacoes_historico_CORRIGIDO.sql` - Procedimento validado
- `EXPLICACAO_GESTACOES_HISTORICO.md` - Explicação detalhada da lógica
- `README_HISTORICO_COMPLETO.md` - Documentação completa do sistema
- `README_TESTES.md` - Guia de testes dos procedimentos 3-6
- `CLAUDE.md` - Contexto do projeto e convenções

### Lógica de Negócio
- **DUM (Data da Última Menstruação)**: Calculada como MODA de data_diagnostico
- **Janela 60 dias**: Separação mínima entre gestações da mesma paciente
- **Auto-encerramento**: 299 dias de duração máxima de gestação
- **Puerpério**: 42 dias após data_fim
- **Filtro temporal**: 340 dias = 299 (gestação) + 42 (puerpério) - 1

### Contato e Suporte
- Para dúvidas sobre lógica de negócio: Consultar equipe de Atenção Primária
- Para problemas técnicos no BigQuery: Equipe de Engenharia de Dados
- Para correções no código: Manter histórico de mudanças documentado

---

## 10. Histórico de Versões

| Versão | Data | Autor | Mudanças |
|--------|------|-------|----------|
| 1.0 | 2025-12-08 | Sistema de Validação | Versão inicial com 14 módulos de validação |

---

**Última atualização**: 2025-12-08
