-- VIEWS

-------------------------------------------------
-- 1) View para mostrar principais informações sobre os emprestimos feitos, como o valor em aberto, 
-- o cliente, taxa de juros e a data de quitacao
DROP VIEW view_emprestimos_ativos;
CREATE OR REPLACE VIEW view_emprestimos_ativos AS
SELECT cli.nome AS "Nome Cliente",
	   telcli.telefone AS "Telefone Cliente",
	   emp.valor AS "Valor Emprestimo",
	   emp.taxajuros AS "Taxa de Juros",
	   emp.valorrestante AS "Valor Restante",
	   rea.dataemprestimo AS "Data do Emprestimo",
	   emp.dataquitacao AS "Data da Quitacao",
	   func.nome AS "Nome Funcionario" 
	FROM cliente cli
	INNER JOIN telefonecliente telcli ON telcli.idcliente = cli.id
	INNER JOIN realiza rea ON rea.idcliente = cli.id
	INNER JOIN emprestimo emp ON emp.id = rea.idemprestimo
	INNER JOIN funcionario func ON func.cpf = rea.cpffuncionario;

SELECT * FROM view_emprestimos_ativos;


-- 2) Estatistica de emprestimos gerados por cada funcionário
-- É retornado o valor total emprestado, a média de valor, a média da taxa de juros 
-- e o tempo médio de duração dos empréstimos de cada funcionário.
DROP VIEW view_relatorio_funcionarios;
CREATE OR REPLACE VIEW view_relatorio_funcionarios AS
SELECT func.nome AS "Funcionario",
	   COUNT(emp.id) AS "Quant. Emprestimos",
	   SUM(emp.valor) AS "Valor total emprestado",
	   ROUND(AVG(emp.valor),2) AS "Media valor",
	   ROUND(AVG(emp.taxajuros), 3) AS "Media de Taxa de Juros",
	   AVG(AGE(rea.dataemprestimo, emp.dataquitacao)) AS "Media de duração do emprestimo"
FROM funcionario func
INNER JOIN realiza rea ON rea.cpffuncionario = func.cpf
INNER JOIN emprestimo emp ON emp.id = rea.idemprestimo
GROUP BY func.nome;

SELECT * FROM view_relatorio_funcionarios;


-- 3) Listagem de emprestimos realizados
-- É retornado o ID do emprestimo, nome do cliente e do funcionário, valor do emprestimo, taxa de juros e data de realização
DROP VIEW view_emprestimos_realizados;
CREATE OR REPLACE VIEW view_emprestimos_realizados AS
SELECT emp.id AS "ID",
	   cli.nome AS "Cliente",
	   func.nome AS "Funcionario",
	   emp.valor AS "Valor",
	   emp.taxajuros AS "Taxa de juros",
	   rea.dataemprestimo AS "Data do emprestimo"
FROM emprestimo emp
INNER JOIN realiza rea ON rea.idemprestimo = emp.id
INNER JOIN cliente cli ON cli.id = rea.idcliente
INNER JOIN funcionario func ON func.cpf = rea.cpffuncionario;

SELECT * FROM view_emprestimos_realizados;


-- FUNCOES

-------------------------------------------------
-- Função 01 - Adiciona clientes na base de dados passando somente os valores.
DROP FUNCTION func_inserir_cliente;
CREATE OR REPLACE FUNCTION func_inserir_cliente(
	idcliente numeric(9),
	nome_cliente varchar(50),
	data_nascimento date,
	vlogradouro varchar(40),
	numero_rua numeric(4),
	vbairro varchar(30),
	vcidade varchar(30),
	vestado char(2))

RETURNS TABLE (
	id NUMERIC(9),
	nome VARCHAR(50),
	dataNascimento DATE,
	logradouro VARCHAR(40),
	numeroRua NUMERIC(4),
	bairro VARCHAR(30),
	cidade VARCHAR(30),
	estado CHAR(2))
AS $$
BEGIN
    INSERT INTO cliente(
		id,
		nome,
		dataNascimento,
		logradouro,
		numeroRua,
		bairro,
		cidade,
		estado)
	VALUES(
		idcliente,
		nome_cliente,
		data_nascimento,
		vlogradouro,
		numero_rua,
		vbairro,
		vcidade,
		vestado);
END;
$$ LANGUAGE plpgsql;

SELECT * FROM func_inserir_cliente(52,'Rogerinho','1999-01-01','Feijão Queimado',4002,'Meu site','Cujubim','RO');
SELECT * from cliente where id = 52;

-------------------------------------------------
-- Função 02 - Deleta clientes da base de dados fornecendo apenas o ID
DROP FUNCTION func_delete_by_id;
CREATE OR REPLACE FUNCTION func_delete_by_id(idcliente numeric(9))

RETURNS void
AS $$
BEGIN
    DELETE FROM cliente WHERE id=idcliente;
END;
$$ LANGUAGE plpgsql;

SELECT func_delete_by_id(52);

-------------------------------------------------
-- Função 03 - Busca a quantidade de emprestimos e a data do ultimo emprestimo do cliente 
-- representado pelo ID informado.
DROP FUNCTION func_busca_emprestimos_por_cliente(numeric);
CREATE OR REPLACE FUNCTION func_busca_emprestimos_por_cliente(id_cliente numeric)
RETURNS TABLE("Cliente" VARCHAR(100), "Total de emprestimos" BIGINT, "Ultimo emprestimo" timestamp)
AS $$
	BEGIN
		RETURN QUERY
		SELECT cli.nome AS "Cliente", COUNT(rea.idemprestimo) AS "Total de emprestimos", MAX(rea.dataemprestimo) AS "Ultimo emprestimo"
		FROM cliente cli
		LEFT JOIN realiza rea ON rea.idcliente = cli.id
		WHERE cli.id = id_cliente
		GROUP BY "Cliente";
	END;
$$ LANGUAGE plpgsql;

SELECT * FROM func_busca_emprestimos_por_cliente(25)

-------------------------------------------------
-- Função 04 - Busca a quantidade de funcionarios e clientes por banco
DROP FUNCTION func_busca_cliente_funcionario_por_banco(numeric);
CREATE OR REPLACE FUNCTION func_busca_cliente_funcionario_por_banco(bancoNire numeric)
RETURNS TABLE (nomeBanco varchar(50),totalClientes bigint,totalFuncionarios bigint)
AS $$
	BEGIN
		RETURN QUERY
		SELECT 
		banco.nome AS "nomeBancos",
		COUNT(DISTINCT(cliente.id)) AS "totalClientes",
		COUNT(DISTINCT(funcionario.cpf)) AS "totalFuncionarios"
		FROM clienteconta
		LEFT JOIN agencia
		ON clienteconta.numeroagencia = agencia.numero
		LEFT JOIN banco
		ON clienteconta.nire = banco.nire
		LEFT JOIN cliente
		on clienteconta.idcliente = cliente.id
		LEFT JOIN funcionario
		ON banco.nire = funcionario.nire
		WHERE banco.nire = bancoNire GROUP BY banco.nome; 
	END;
$$ LANGUAGE plpgsql;

SELECT * FROM func_busca_cliente_funcionario_por_banco(1);

-- 5) Retorna a soma dos emprestimos de uma agencia informada pelo ID no mes e ano informado
DROP FUNCTION func_valor_total_emprestimos_agencia_mes;
CREATE OR REPLACE FUNCTION func_valor_total_emprestimos_agencia_mes(
    agencia_id INTEGER,
    mes INTEGER,
    ano INTEGER
) 
RETURNS NUMERIC
AS $$
DECLARE
    valor_total NUMERIC := 0;
    emprestimo_record RECORD;
BEGIN
    FOR emprestimo_record IN  SELECT * FROM emprestimo e 
	INNER JOIN realiza r ON e.id = r.idemprestimo
	INNER JOIN cliente cli ON cli.id = r.idcliente
	INNER JOIN clienteconta cc ON cc.idcliente = cli.id
	INNER JOIN agencia a ON a.numero = cc.numeroagencia 
	WHERE cc.numeroagencia = agencia_id 
		AND EXTRACT(MONTH FROM r.dataemprestimo) = mes 
		AND EXTRACT(YEAR FROM r.dataemprestimo) = ano LOOP
        valor_total := valor_total + emprestimo_record.valor;
    END LOOP;
    RETURN valor_total AS Valot_total;
END;
$$ LANGUAGE plpgsql;

SELECT * FROM func_valor_total_emprestimos_agencia_mes(2, 01, 2011);



