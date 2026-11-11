CREATE SEQUENCE IF NOT EXISTS public.produtos_codigo_seq;

CREATE TABLE IF NOT EXISTS public.produtos (
    ordem integer PRIMARY KEY,
    codigo text NOT NULL UNIQUE DEFAULT ('PRD-' || to_char(nextval('public.produtos_codigo_seq'), 'FM000000')),
    nome text NOT NULL,
    categoria text NOT NULL,
    fornecedor text NOT NULL,
    marca text NOT NULL,
    "local" text NOT NULL,
    quantidade integer NOT NULL CHECK (quantidade >= 0),
    minimo integer NOT NULL CHECK (minimo >= 0),
    status text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.categorias (
    ordem integer PRIMARY KEY,
    nome text NOT NULL,
    descricao text NOT NULL,
    produtos text NOT NULL,
    status text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.fornecedores (
    ordem integer PRIMARY KEY,
    nome text NOT NULL,
    contato text NOT NULL,
    email text NOT NULL,
    telefone text NOT NULL,
    categoria text NOT NULL,
    status text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.locais (
    ordem integer PRIMARY KEY,
    nome text NOT NULL,
    categoria text NOT NULL,
    setor text NOT NULL,
    itens text NOT NULL,
    responsavel text NOT NULL,
    status text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.usuarios (
    ordem integer PRIMARY KEY,
    nome text NOT NULL,
    cpf text NOT NULL,
    email text NOT NULL,
    cargo text NOT NULL,
    status text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.configuracao_inventario (
    id boolean PRIMARY KEY DEFAULT true CHECK (id),
    inicializado boolean NOT NULL DEFAULT false
);

INSERT INTO public.configuracao_inventario (id, inicializado)
VALUES (true, false)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fornecedores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.locais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.configuracao_inventario ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.produtos, public.categorias, public.fornecedores,
    public.locais, public.usuarios, public.configuracao_inventario
FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.produtos, public.categorias, public.fornecedores,
    public.locais, public.usuarios, public.configuracao_inventario
TO service_role;

CREATE OR REPLACE FUNCTION public.carregar_inventario()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    SELECT jsonb_build_object(
        'inicializado', configuracao.inicializado,
        'dados', jsonb_build_object(
            'produtos', COALESCE(
                (SELECT jsonb_agg(to_jsonb(item) - 'ordem' ORDER BY item.ordem) FROM public.produtos AS item),
                '[]'::jsonb
            ),
            'categorias', COALESCE(
                (SELECT jsonb_agg(to_jsonb(item) - 'ordem' ORDER BY item.ordem) FROM public.categorias AS item),
                '[]'::jsonb
            ),
            'fornecedores', COALESCE(
                (SELECT jsonb_agg(to_jsonb(item) - 'ordem' ORDER BY item.ordem) FROM public.fornecedores AS item),
                '[]'::jsonb
            ),
            'locais', COALESCE(
                (SELECT jsonb_agg(to_jsonb(item) - 'ordem' ORDER BY item.ordem) FROM public.locais AS item),
                '[]'::jsonb
            ),
            'usuarios', COALESCE(
                (SELECT jsonb_agg(to_jsonb(item) - 'ordem' ORDER BY item.ordem) FROM public.usuarios AS item),
                '[]'::jsonb
            )
        )
    )
    FROM public.configuracao_inventario AS configuracao
    WHERE configuracao.id = true;
$$;

CREATE OR REPLACE FUNCTION public.salvar_inventario(dados jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
    IF jsonb_typeof(dados) <> 'object'
        OR jsonb_typeof(dados -> 'produtos') <> 'array'
        OR jsonb_typeof(dados -> 'categorias') <> 'array'
        OR jsonb_typeof(dados -> 'fornecedores') <> 'array'
        OR jsonb_typeof(dados -> 'locais') <> 'array'
        OR jsonb_typeof(dados -> 'usuarios') <> 'array' THEN
        RAISE EXCEPTION 'O inventário deve conter uma lista válida de cada cadastro.';
    END IF;

    DELETE FROM public.produtos WHERE true;
    INSERT INTO public.produtos (ordem, codigo, nome, categoria, fornecedor, marca, "local", quantidade, minimo, status)
    SELECT registro.ordem::integer, COALESCE(NULLIF(btrim(item.codigo), ''), 'PRD-' || to_char(nextval('public.produtos_codigo_seq'), 'FM000000')), item.nome, item.categoria, item.fornecedor, item.marca,
        item."local", item.quantidade, item.minimo, item.status
    FROM jsonb_array_elements(dados -> 'produtos') WITH ORDINALITY AS registro(valor, ordem)
    CROSS JOIN LATERAL jsonb_to_record(registro.valor) AS item(
        codigo text, nome text, categoria text, fornecedor text, marca text, "local" text,
        quantidade integer, minimo integer, status text
    );

    DELETE FROM public.categorias WHERE true;
    INSERT INTO public.categorias (ordem, nome, descricao, produtos, status)
    SELECT registro.ordem::integer, item.nome, item.descricao, item.produtos, item.status
    FROM jsonb_array_elements(dados -> 'categorias') WITH ORDINALITY AS registro(valor, ordem)
    CROSS JOIN LATERAL jsonb_to_record(registro.valor) AS item(
        nome text, descricao text, produtos text, status text
    );

    DELETE FROM public.fornecedores WHERE true;
    INSERT INTO public.fornecedores (ordem, nome, contato, email, telefone, categoria, status)
    SELECT registro.ordem::integer, item.nome, item.contato, item.email, item.telefone, item.categoria, item.status
    FROM jsonb_array_elements(dados -> 'fornecedores') WITH ORDINALITY AS registro(valor, ordem)
    CROSS JOIN LATERAL jsonb_to_record(registro.valor) AS item(
        nome text, contato text, email text, telefone text, categoria text, status text
    );

    DELETE FROM public.locais WHERE true;
    INSERT INTO public.locais (ordem, nome, categoria, setor, itens, responsavel, status)
    SELECT registro.ordem::integer, item.nome, item.categoria, item.setor, item.itens, item.responsavel, item.status
    FROM jsonb_array_elements(dados -> 'locais') WITH ORDINALITY AS registro(valor, ordem)
    CROSS JOIN LATERAL jsonb_to_record(registro.valor) AS item(
        nome text, categoria text, setor text, itens text, responsavel text, status text
    );

    DELETE FROM public.usuarios WHERE true;
    INSERT INTO public.usuarios (ordem, nome, cpf, email, cargo, status)
    SELECT registro.ordem::integer, item.nome, item.cpf, item.email, item.cargo, item.status
    FROM jsonb_array_elements(dados -> 'usuarios') WITH ORDINALITY AS registro(valor, ordem)
    CROSS JOIN LATERAL jsonb_to_record(registro.valor) AS item(
        nome text, cpf text, email text, cargo text, status text
    );

    UPDATE public.configuracao_inventario
    SET inicializado = true
    WHERE id = true;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.carregar_inventario() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.salvar_inventario(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carregar_inventario() TO service_role;
GRANT EXECUTE ON FUNCTION public.salvar_inventario(jsonb) TO service_role;

-- O Vercel envia o JWT do usuário às RPCs. O RLS permite acesso apenas às contas autorizadas.
DO $$
DECLARE
    table_name text;
    allowed_emails text := 'admin@empresa.com.br,estoque@empresa.com.br';
BEGIN
    FOREACH table_name IN ARRAY ARRAY['produtos', 'categorias', 'fornecedores', 'locais', 'usuarios', 'configuracao_inventario'] LOOP
        EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.%I TO authenticated', table_name);
        EXECUTE format('DROP POLICY IF EXISTS inventory_email_allowlist ON public.%I', table_name);
        EXECUTE format(
            'CREATE POLICY inventory_email_allowlist ON public.%I FOR ALL TO authenticated USING (lower(coalesce(auth.jwt()->>''email'', '''')) = ANY (string_to_array(%L, '',''))) WITH CHECK (lower(coalesce(auth.jwt()->>''email'', '''')) = ANY (string_to_array(%L, '','')))',
            table_name, allowed_emails, allowed_emails
        );
    END LOOP;
END $$;
GRANT USAGE, SELECT ON SEQUENCE public.produtos_codigo_seq TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.carregar_inventario() TO authenticated;
GRANT EXECUTE ON FUNCTION public.salvar_inventario(jsonb) TO authenticated;
