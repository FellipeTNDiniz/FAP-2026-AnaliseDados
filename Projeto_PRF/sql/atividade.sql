-- ==============================================================================
-- Autor: Fellipe Diniz
-- Ferramenta: DuckDB
-- Fontes de Dados: datatran2023.csv, datatran2024.csv, datatran2025.csv
-- Objetivo: Análise Histórica e Identificação de Fatores de Acidentes Fatais
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Parte 1: Ingestão e Integração de Dados
-- Criação de uma única tabela principal unindo os dados dos três anos
-- ------------------------------------------------------------------------------
CREATE OR REPLACE TABLE acidentes_prf_historico AS
SELECT * FROM read_csv_auto(
    '/workspaces/FAP-2026-AnaliseDados/Projeto_PRF/dados_brutos/datatran2023.csv', delim = ';', header = true, encoding = 'latin-1', sample_size = -1
)
UNION ALL
SELECT * FROM read_csv_auto(
    '/workspaces/FAP-2026-AnaliseDados/Projeto_PRF/dados_brutos/datatran2024.csv', delim = ';', header = true, encoding = 'latin-1', sample_size = -1
)
UNION ALL
SELECT * FROM read_csv_auto(
    '/workspaces/FAP-2026-AnaliseDados/Projeto_PRF/dados_brutos/datatran2025.csv', delim = ';', header = true, encoding = 'latin-1', sample_size = -1
);

-- ------------------------------------------------------------------------------
-- Parte 2: Limpeza e Seleção de Colunas
-- Descarta colunas administrativas e geodésicas não utilizadas na modelagem
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_acidentes_limpa AS
SELECT * EXCLUDE (latitude, longitude, regional, delegacia, uop)
FROM acidentes_prf_historico;

-- ------------------------------------------------------------------------------
-- Parte 3: Engenharia de Recursos (Criação de Novas Colunas)
-- Criação de flags e mapeamento exato de datas comemorativas e feriados
-- ------------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_acidentes_enriquecida AS
SELECT 
    *,
    -- Variável-alvo binária: 1 se for fatal, 0 caso contrário
    CASE WHEN mortos >= 1 THEN 1 ELSE 0 END AS acidente_fatal,
    
    -- Extração de ano e mês
    EXTRACT(YEAR FROM CAST(data_inversa AS DATE)) AS ano_acidente,
    EXTRACT(MONTH FROM CAST(data_inversa AS DATE)) AS mes_acidente,
    
    -- Flag de fim de semana (tratando a string para evitar problemas de caixa)
    CASE WHEN LOWER(dia_semana) IN ('sábado', 'domingo', 'sabado') THEN 1 ELSE 0 END AS fim_de_semana,
    
    -- Classificação exata de feriados e períodos festivos (2023, 2024, 2025)
    CASE 
        -- Fim de Ano (20/12 a 02/01 - engloba Natal e Confraternização Universal)
        WHEN (EXTRACT(MONTH FROM CAST(data_inversa AS DATE)) = 12 AND EXTRACT(DAY FROM CAST(data_inversa AS DATE)) >= 20) OR
             (EXTRACT(MONTH FROM CAST(data_inversa AS DATE)) = 1 AND EXTRACT(DAY FROM CAST(data_inversa AS DATE)) <= 2) 
             THEN 'Fim de Ano'
             
        -- Carnaval (Sábado de Zé Pereira até Quarta-feira de Cinzas)
        WHEN CAST(data_inversa AS DATE) IN (
            '2023-02-18', '2023-02-19', '2023-02-20', '2023-02-21', '2023-02-22',
            '2024-02-10', '2024-02-11', '2024-02-12', '2024-02-13', '2024-02-14',
            '2025-03-01', '2025-03-02', '2025-03-03', '2025-03-04', '2025-03-05'
        ) THEN 'Carnaval'
        
        -- Outros Feriados Nacionais e Religiosos
        WHEN CAST(data_inversa AS DATE) IN (
            -- 2023
            '2023-04-07', '2023-04-21', '2023-05-01', '2023-06-08', '2023-09-07', '2023-10-12', '2023-11-02', '2023-11-15', '2023-11-20',
            -- 2024
            '2024-03-29', '2024-04-21', '2024-05-01', '2024-05-30', '2024-09-07', '2024-10-12', '2024-11-02', '2024-11-15', '2024-11-20',
            -- 2025
            '2025-04-18', '2025-04-21', '2025-05-01', '2025-06-19', '2025-09-07', '2025-10-12', '2025-11-02', '2025-11-15', '2025-11-20'
        ) THEN 'Feriado Nacional'
        
        ELSE 'Normal'
    END AS data_comemorativa
FROM vw_acidentes_limpa;


-- ==============================================================================
-- Parte 4: Questões de Negócio (Consultas Analíticas)
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- Nível 1: Visão Geral e Temporal
-- ------------------------------------------------------------------------------

-- 1. Tendência Anual e Severidade: Verifica a proporção de acidentes fatais ao longo dos anos
SELECT 
    ano_acidente AS "Ano",
    COUNT(id) AS "Total de Acidentes",
    SUM(mortos) AS "Total de Vítimas Fatais",
    REPLACE(PRINTF('%.2f%%', (SUM(acidente_fatal) * 100.0) / COUNT(id)), '.', ',') AS "Taxa Global de Letalidade"
FROM vw_acidentes_enriquecida
GROUP BY ano_acidente
ORDER BY ano_acidente;

-- 2. Sazonalidade Mensal das Ocorrências: Identifica qual mês tem a maior taxa de letalidade
SELECT 
    mes_acidente AS "Mês",
    COUNT(id) AS "Total de Acidentes",
    SUM(acidente_fatal) AS "Acidentes Fatais",
    REPLACE(PRINTF('%.2f%%', (SUM(acidente_fatal) * 100.0) / COUNT(id)), '.', ',') AS "Taxa de Letalidade"
FROM vw_acidentes_enriquecida
GROUP BY mes_acidente
ORDER BY (SUM(acidente_fatal) * 100.0) / COUNT(id) DESC;

-- 3. A Influência da Luminosidade: Avalia se a proporção de acidentes fatais é maior à noite
SELECT 
    fase_dia AS "Fase do Dia",
    COUNT(id) AS "Total de Acidentes",
    SUM(acidente_fatal) AS "Acidentes Fatais",
    REPLACE(PRINTF('%.2f%%', (SUM(acidente_fatal) * 100.0) / COUNT(id)), '.', ',') AS "Taxa de Letalidade"
FROM vw_acidentes_enriquecida
GROUP BY fase_dia
ORDER BY (SUM(acidente_fatal) * 100.0) / COUNT(id) DESC;

-- 4. O Impacto dos Finais de Semana: Compara a letalidade de dias úteis com fins de semana
SELECT 
    CASE WHEN fim_de_semana = 1 THEN 'Fim de Semana' ELSE 'Dia Útil' END AS "Período da Semana",
    COUNT(id) AS "Total de Acidentes",
    SUM(acidente_fatal) AS "Acidentes Fatais",
    REPLACE(PRINTF('%.2f%%', (SUM(acidente_fatal) * 100.0) / COUNT(id)), '.', ',') AS "Taxa de Letalidade"
FROM vw_acidentes_enriquecida
GROUP BY fim_de_semana
ORDER BY (SUM(acidente_fatal) * 100.0) / COUNT(id) DESC;


-- ------------------------------------------------------------------------------
-- Nível 2: Análise de Risco (Cálculo de Lift e Fatores de Causa)
-- ------------------------------------------------------------------------------

-- 5. O Perigo Oculto na Dinâmica da Colisão: Dinâmica que mais eleva a letalidade (Lift)
WITH taxa_global AS (
    SELECT SUM(acidente_fatal) / CAST(COUNT(id) AS DOUBLE) AS tx_global 
    FROM vw_acidentes_enriquecida
)
SELECT 
    tipo_acidente AS "Tipo de Acidente",
    COUNT(id) AS "Total de Acidentes",
    SUM(acidente_fatal) AS "Acidentes Fatais",
    REPLACE(PRINTF('%.2f%%', ((SUM(acidente_fatal) * 100.0) / COUNT(id))), '.', ',') AS "Taxa de Letalidade",
    ROUND(((SUM(acidente_fatal) * 1.0) / COUNT(id)) / (SELECT tx_global FROM taxa_global), 2) AS "Lift"
FROM vw_acidentes_enriquecida
GROUP BY tipo_acidente
HAVING COUNT(id) >= 100
ORDER BY "Lift" DESC;

-- 6. Ranking de Causas Associadas à Letalidade: As 5 causas presumíveis com o maior Lift
WITH taxa_global AS (
    SELECT SUM(acidente_fatal) / CAST(COUNT(id) AS DOUBLE) AS tx_global 
    FROM vw_acidentes_enriquecida
)
SELECT 
    causa_acidente AS "Causa do Acidente",
    COUNT(id) AS "Total de Acidentes",
    SUM(acidente_fatal) AS "Acidentes Fatais",
    REPLACE(PRINTF('%.2f%%', ((SUM(acidente_fatal) * 100.0) / COUNT(id))), '.', ',') AS "Taxa de Letalidade",
    ROUND(((SUM(acidente_fatal) * 1.0) / COUNT(id)) / (SELECT tx_global FROM taxa_global), 2) AS "Lift"
FROM vw_acidentes_enriquecida
GROUP BY causa_acidente
HAVING COUNT(id) >= 50
ORDER BY "Lift" DESC
LIMIT 5;

-- 7. Análise da Infraestrutura: Letalidade em "Reta" vs "Curva"
SELECT 
    tracado_via AS "Traçado da Via",
    COUNT(id) AS "Total de Acidentes",
    SUM(acidente_fatal) AS "Acidentes Fatais",
    REPLACE(PRINTF('%.2f%%', (SUM(acidente_fatal) * 100.0) / COUNT(id)), '.', ',') AS "Taxa de Letalidade"
FROM vw_acidentes_enriquecida
WHERE tracado_via IN ('Reta', 'Curva')
GROUP BY tracado_via
HAVING COUNT(id) > 500
ORDER BY "Taxa de Letalidade" DESC;


-- ------------------------------------------------------------------------------
-- Nível 3: Análise Multivariada (Cruzamentos de Variáveis)
-- ------------------------------------------------------------------------------

-- 8. Condições Agravantes (Pista vs Clima): A pior combinação de letalidade
SELECT 
    tipo_pista AS "Tipo de Pista",
    condicao_metereologica AS "Condição Meteorológica",
    COUNT(id) AS "Total de Acidentes",
    SUM(acidente_fatal) AS "Acidentes Fatais",
    REPLACE(PRINTF('%.2f%%', (SUM(acidente_fatal) * 100.0) / COUNT(id)), '.', ',') AS "Taxa de Letalidade"
FROM vw_acidentes_enriquecida
GROUP BY tipo_pista, condicao_metereologica
HAVING COUNT(id) >= 50
ORDER BY (SUM(acidente_fatal) * 1.0) / COUNT(id) DESC;

-- 9. Pontos Críticos Noturnos: As 10 rodovias com mais vítimas fatais à noite
SELECT 
    br AS "Rodovia (BR)",
    SUM(mortos) AS "Total de Vítimas Fatais à Noite"
FROM vw_acidentes_enriquecida
WHERE LOWER(fase_dia) = 'plena noite'
GROUP BY br
ORDER BY "Total de Vítimas Fatais à Noite" DESC
LIMIT 10;

-- 10. O Efeito de Períodos Festivos: Compara total de acidentes e letalidade em feriados
SELECT 
    data_comemorativa AS "Período Sazonal",
    COUNT(id) AS "Total de Acidentes",
    SUM(mortos) AS "Total de Mortos",
    REPLACE(PRINTF('%.2f%%', (SUM(acidente_fatal) * 100.0) / COUNT(id)), '.', ',') AS "Taxa de Letalidade"
FROM vw_acidentes_enriquecida
GROUP BY data_comemorativa
ORDER BY (SUM(acidente_fatal) * 1.0) / COUNT(id) DESC;


-- ------------------------------------------------------------------------------
-- Nível 4: Casos Críticos e Foco Geográfico
-- ------------------------------------------------------------------------------

-- 11. Acidentes de Altíssima Gravidade: Estado e causa de acidentes com 3 ou mais mortos
SELECT 
    uf AS "Estado",
    causa_acidente AS "Principal Causa Relatada",
    COUNT(id) AS "Qtd. Acidentes (3+ Mortos)",
    SUM(mortos) AS "Total de Vítimas"
FROM vw_acidentes_enriquecida
WHERE mortos >= 3
GROUP BY uf, causa_acidente
ORDER BY "Qtd. Acidentes (3+ Mortos)" DESC, "Total de Vítimas" DESC
LIMIT 10;

-- 12. Direcionamento Regional em Pernambuco (PE): Top 5 municípios para alocação de viaturas (2024 e 2025)
SELECT 
    municipio AS "Município (PE)",
    COUNT(id) AS "Acidentes Fatais Absolutos",
    SUM(mortos) AS "Total de Vítimas Fatais"
FROM vw_acidentes_enriquecida
WHERE uf = 'PE' 
  AND ano_acidente IN (2024, 2025)
  AND acidente_fatal = 1
GROUP BY municipio
ORDER BY "Acidentes Fatais Absolutos" DESC
LIMIT 5;