# 🧪 Instruções para Executar Testes dos Procedimentos 3-6

## ✅ O Que Foi Criado

Todos os procedimentos foram parametrizados e estão prontos para teste:

### Arquivos de Procedimentos
1. ✅ `3_visitas_acs_gestacao_historico.sql` - Visitas de ACS (1 substituição CURRENT_DATE)
2. ✅ `4_consultas_emergenciais_historico.sql` - Consultas emergenciais (2 substituições CURRENT_DATE)
3. ✅ `5_encaminhamentos_historico.sql` - Encaminhamentos SISREG (11 substituições CURRENT_DATE)
4. ✅ `6_linha_tempo_historico.sql` - Linha do tempo agregada (21 substituições CURRENT_DATE)

### Arquivos de Teste e Documentação
- ✅ `teste_procedimentos_3_a_6.sql` - Script completo de teste automatizado
- ✅ `README_TESTES.md` - Guia detalhado de testes com validações
- ✅ `construir_historico_completo.sql` - Exemplos de execução completa
- ✅ `CLAUDE.md` - Atualizado com informações de teste

## 🚀 Como Executar os Testes no BigQuery

### PASSO 1: Criar os Procedimentos no BigQuery

Você precisa executar cada arquivo SQL para criar os procedimentos:

#### 1.1. Criar Procedimento 3 (Visitas ACS)
```
1. Abra o BigQuery Console
2. Abra o arquivo: 3_visitas_acs_gestacao_historico.sql
3. Copie TODO o conteúdo (Ctrl+A, Ctrl+C)
4. Cole no editor do BigQuery
5. Clique em "Run" ou pressione Ctrl+Enter
6. Aguarde mensagem de sucesso
```

#### 1.2. Criar Procedimento 4 (Consultas Emergenciais)
```
1. Abra o arquivo: 4_consultas_emergenciais_historico.sql
2. Copie TODO o conteúdo
3. Cole no editor do BigQuery
4. Execute
5. Aguarde confirmação
```

#### 1.3. Criar Procedimento 5 (Encaminhamentos)
```
1. Abra o arquivo: 5_encaminhamentos_historico.sql
2. Copie TODO o conteúdo
3. Cole no editor do BigQuery
4. Execute
5. Aguarde confirmação
```

#### 1.4. Criar Procedimento 6 (Linha do Tempo)
```
1. Abra o arquivo: 6_linha_tempo_historico.sql
2. Copie TODO o conteúdo
3. Cole no editor do BigQuery
4. Execute
5. Aguarde confirmação
```

### PASSO 2: Executar Script de Teste Completo

Agora execute o script de teste automatizado:

```
1. Abra o arquivo: teste_procedimentos_3_a_6.sql
2. Copie TODO o conteúdo
3. Cole no editor do BigQuery
4. Clique em "Run"
5. Aguarde conclusão (pode levar 5-15 minutos)
```

O script irá:
- ✅ Validar se procedimentos 1 e 2 foram executados
- ✅ Executar procedimento 3 e validar resultados
- ✅ Executar procedimento 4 e validar resultados
- ✅ Executar procedimento 5 e validar resultados
- ✅ Executar procedimento 6 e validar resultados
- ✅ Verificar consistência entre todas as tabelas
- ✅ Gerar resumo final consolidado

### PASSO 3: Interpretar Resultados

O script gerará múltiplos resultados. Procure por:

#### ✅ Sucessos Esperados
- Todas as tabelas com registros > 0
- Nenhuma "gestação órfã" (sem referência na tabela base)
- Contadores consistentes entre linha do tempo e tabelas fonte
- Indicadores de cobertura dentro de valores razoáveis (30-70%)

#### ⚠️ Problemas Possíveis

**Se aparecer "0 registros" na pré-validação:**
```
Problema: Procedimentos 1 e 2 não foram executados
Solução: Execute primeiro:
  CALL proced_1_gestacoes_historico(DATE('2024-10-31'));
  CALL proced_2_atd_prenatal_aps_historico(DATE('2024-10-31'));
```

**Se aparecer erro "Procedure not found":**
```
Problema: Procedimento não foi criado
Solução: Volte ao PASSO 1 e crie o procedimento correspondente
```

**Se aparecer "gestacoes_orfas > 0":**
```
Problema: Inconsistência entre tabelas
Solução: Re-execute TODOS os procedimentos na ordem correta
```

## 📊 Resultados Esperados

### Procedimento 3: Visitas ACS
- Total de visitas > 0
- Taxa de cobertura: 30-70% das gestações
- Média de visitas por gestação: 2-5

### Procedimento 4: Consultas Emergenciais
- Total de consultas >= 0 (pode ser 0, é normal)
- Taxa de emergência: 10-30% das gestações
- Idade gestacional média: 20-28 semanas

### Procedimento 5: Encaminhamentos
- Total de encaminhamentos >= 0
- Taxa de encaminhamento: 15-40% das gestações
- Apenas procedimentos específicos: '0703844','0703886','0737024','0710301','0710128'

### Procedimento 6: Linha do Tempo
- Total de gestações = ativas + puerpério
- Indicador de consulta no 1º trimestre: 50-75%
- Adequação de 6 consultas: 40-70%
- Prevalência de HAS: 5-15%
- Prevalência de Diabetes: 3-10%

## 🔧 Teste Rápido Individual

Se preferir testar um procedimento por vez, use este template:

```sql
-- Substitua [3-6] pelo número do procedimento que quer testar
DECLARE data_ref DATE DEFAULT DATE('2024-10-31');

-- Executar procedimento
CALL `rj-sms-sandbox.sub_pav_us.proced_[3-6]_[nome]_historico`(data_ref);

-- Validar
SELECT
    COUNT(*) AS total_registros,
    COUNT(DISTINCT id_paciente) AS total_pacientes
FROM `rj-sms-sandbox.sub_pav_us._[nome_tabela]_historico`
WHERE data_snapshot = data_ref;
```

Exemplos específicos estão no `README_TESTES.md`.

## 📝 Checklist de Execução

Marque conforme for completando:

### Criação de Procedimentos
- [ ] Procedimento 3 criado no BigQuery
- [ ] Procedimento 4 criado no BigQuery
- [ ] Procedimento 5 criado no BigQuery
- [ ] Procedimento 6 criado no BigQuery

### Execução de Testes
- [ ] Script de teste completo executado
- [ ] Todos os procedimentos executados sem erro
- [ ] Validações passaram com sucesso
- [ ] Consistência verificada entre tabelas

### Resultados
- [ ] Procedimento 3: Dados de visitas ACS gerados
- [ ] Procedimento 4: Dados de emergências gerados
- [ ] Procedimento 5: Dados de encaminhamentos gerados
- [ ] Procedimento 6: Linha do tempo agregada gerada
- [ ] Resumo final consolidado verificado

## 📚 Documentação de Referência

Consulte esses documentos para mais detalhes:

- **`README_TESTES.md`**: Guia completo de testes com validações detalhadas
- **`README_HISTORICO_COMPLETO.md`**: Documentação completa do sistema
- **`CLAUDE.md`**: Referência técnica para desenvolvedores
- **`construir_historico_completo.sql`**: Exemplos de uso em produção

## ⏭️ Próximos Passos Após Testes

Se todos os testes passarem com sucesso:

1. **Testar múltiplas datas**: Execute para diferentes snapshots
2. **Criar tabelas acumuladas**: Use exemplo 2 do `construir_historico_completo.sql`
3. **Gerar série histórica mensal**: Use exemplo 3 do `construir_historico_completo.sql`
4. **Análises temporais**: Explore evolução de indicadores ao longo do tempo

## 🆘 Suporte

Se encontrar problemas:

1. Consulte seção "Troubleshooting" no `README_TESTES.md`
2. Verifique seção "Common Issues" no `CLAUDE.md`
3. Execute queries de validação de consistência
4. Re-execute pipeline completo se necessário

---

**Boa sorte com os testes! 🚀**
