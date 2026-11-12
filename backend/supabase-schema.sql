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
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    inicializacao_inicial boolean;
BEGIN
    IF auth.uid() IS NULL OR lower(coalesce(auth.jwt() ->> 'email', '')) <> ALL (ARRAY['admin@empresa.com.br', 'estoque@empresa.com.br']) THEN
        RAISE EXCEPTION 'Conta não autorizada.';
    END IF;
    IF jsonb_typeof(dados) <> 'object'
        OR jsonb_typeof(dados -> 'produtos') <> 'array'
        OR jsonb_typeof(dados -> 'categorias') <> 'array'
        OR jsonb_typeof(dados -> 'fornecedores') <> 'array'
        OR jsonb_typeof(dados -> 'locais') <> 'array'
        OR jsonb_typeof(dados -> 'usuarios') <> 'array' THEN
        RAISE EXCEPTION 'O inventário deve conter uma lista válida de cada cadastro.';
    END IF;

    LOCK TABLE public.produtos IN EXCLUSIVE MODE;
    SELECT NOT EXISTS (SELECT 1 FROM public.configuracao_inventario WHERE id = true AND inicializado)
        AND NOT EXISTS (SELECT 1 FROM public.produtos)
    INTO inicializacao_inicial;

    IF NOT inicializacao_inicial AND EXISTS (
        SELECT 1
        FROM public.produtos AS produto
        WHERE produto.quantidade > 0
          AND NOT EXISTS (
              SELECT 1
              FROM jsonb_array_elements(dados -> 'produtos') AS registro(valor)
              WHERE NULLIF(btrim(registro.valor ->> 'codigo'), '') = produto.codigo
          )
    ) THEN
        RAISE EXCEPTION 'Registre uma saída antes de excluir um produto com saldo em estoque.';
    END IF;

    DROP TABLE IF EXISTS pg_temp.inventory_stock_snapshot;
    CREATE TEMP TABLE inventory_stock_snapshot ON COMMIT DROP AS
        SELECT codigo, quantidade FROM public.produtos;

    DELETE FROM public.produtos WHERE true;
    INSERT INTO public.produtos (ordem, codigo, nome, categoria, fornecedor, marca, "local", quantidade, minimo, status)
    SELECT registro.ordem::integer, COALESCE(NULLIF(btrim(item.codigo), ''), 'PRD-' || to_char(nextval('public.produtos_codigo_seq'), 'FM000000')), item.nome, item.categoria, item.fornecedor, item.marca,
        item."local", CASE WHEN inicializacao_inicial THEN item.quantidade ELSE COALESCE(snapshot.quantidade, 0) END, item.minimo, item.status
    FROM jsonb_array_elements(dados -> 'produtos') WITH ORDINALITY AS registro(valor, ordem)
    CROSS JOIN LATERAL jsonb_to_record(registro.valor) AS item(
        codigo text, nome text, categoria text, fornecedor text, marca text, "local" text,
        quantidade integer, minimo integer, status text
    )
    LEFT JOIN pg_temp.inventory_stock_snapshot AS snapshot
        ON snapshot.codigo = NULLIF(btrim(item.codigo), '');

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
        EXECUTE format('GRANT SELECT ON TABLE public.%I TO authenticated', table_name);
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

-- PINs pessoais para movimentação de estoque; a tabela não fica exposta pela API.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE TABLE IF NOT EXISTS private.stock_pin_credentials (
    user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    pin_hash text NOT NULL,
    failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    locked_until timestamptz,
    updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.stock_pin_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.stock_pin_credentials FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE private.stock_pin_credentials TO postgres;

CREATE OR REPLACE FUNCTION public.configurar_pin_estoque(novo_pin text, pin_atual text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    uid uuid := auth.uid();
    email text := lower(coalesce(auth.jwt() ->> 'email', ''));
    credencial private.stock_pin_credentials%ROWTYPE;
    tentativas integer;
BEGIN
    IF uid IS NULL OR email <> ALL (ARRAY['admin@empresa.com.br', 'estoque@empresa.com.br']) THEN
        RAISE EXCEPTION 'Conta não autorizada.';
    END IF;
    IF novo_pin IS NULL OR novo_pin !~ '^[0-9]{4}$' THEN
        RETURN jsonb_build_object('ok', false, 'code', 'INVALID_PIN', 'error', 'O PIN precisa ter exatamente 4 dígitos.');
    END IF;

    SELECT * INTO credencial FROM private.stock_pin_credentials WHERE user_id = uid FOR UPDATE;
    IF FOUND THEN
        IF credencial.locked_until > now() THEN
            RETURN jsonb_build_object('ok', false, 'code', 'PIN_LOCKED', 'error', 'Muitas tentativas. Aguarde 15 minutos e tente novamente.');
        END IF;
        IF pin_atual IS NULL OR pin_atual !~ '^[0-9]{4}$' OR extensions.crypt(pin_atual, credencial.pin_hash) <> credencial.pin_hash THEN
            tentativas := CASE WHEN credencial.locked_until IS NOT NULL AND credencial.locked_until <= now() THEN 1 ELSE credencial.failed_attempts + 1 END;
            UPDATE private.stock_pin_credentials
            SET failed_attempts = tentativas,
                locked_until = CASE WHEN tentativas >= 5 THEN now() + interval '15 minutes' ELSE NULL END
            WHERE user_id = uid;
            RETURN jsonb_build_object('ok', false, 'code', CASE WHEN tentativas >= 5 THEN 'PIN_LOCKED' ELSE 'PIN_INVALID' END,
                'error', CASE WHEN tentativas >= 5 THEN 'Muitas tentativas. Aguarde 15 minutos.' ELSE 'PIN atual incorreto.' END);
        END IF;
        UPDATE private.stock_pin_credentials
        SET pin_hash = extensions.crypt(novo_pin, extensions.gen_salt('bf', 10)), failed_attempts = 0, locked_until = NULL, updated_at = now()
        WHERE user_id = uid;
    ELSE
        INSERT INTO private.stock_pin_credentials (user_id, pin_hash)
        VALUES (uid, extensions.crypt(novo_pin, extensions.gen_salt('bf', 10)));
    END IF;
    RETURN jsonb_build_object('ok', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.registrar_movimentacao_estoque(pin text, codigo_produto text, tipo text, quantidade integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    uid uuid := auth.uid();
    email text := lower(coalesce(auth.jwt() ->> 'email', ''));
    credencial private.stock_pin_credentials%ROWTYPE;
    tentativas integer;
    novo_saldo integer;
    novo_status text;
BEGIN
    IF uid IS NULL OR email <> ALL (ARRAY['admin@empresa.com.br', 'estoque@empresa.com.br']) THEN
        RAISE EXCEPTION 'Conta não autorizada.';
    END IF;
    IF pin IS NULL OR pin !~ '^[0-9]{4}$' OR tipo IS NULL OR tipo NOT IN ('entrada', 'saida') OR quantidade IS NULL OR quantidade <= 0 THEN
        RETURN jsonb_build_object('ok', false, 'code', 'INVALID_INPUT', 'error', 'Informe um PIN válido, tipo e quantidade maior que zero.');
    END IF;

    SELECT * INTO credencial FROM private.stock_pin_credentials WHERE user_id = uid FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'code', 'PIN_NOT_SET', 'error', 'Configure seu PIN de movimentação antes de continuar.');
    END IF;
    IF credencial.locked_until > now() THEN
        RETURN jsonb_build_object('ok', false, 'code', 'PIN_LOCKED', 'error', 'Muitas tentativas. Aguarde 15 minutos e tente novamente.');
    END IF;
    IF extensions.crypt(pin, credencial.pin_hash) <> credencial.pin_hash THEN
        tentativas := CASE WHEN credencial.locked_until IS NOT NULL AND credencial.locked_until <= now() THEN 1 ELSE credencial.failed_attempts + 1 END;
        UPDATE private.stock_pin_credentials
        SET failed_attempts = tentativas,
            locked_until = CASE WHEN tentativas >= 5 THEN now() + interval '15 minutes' ELSE NULL END
        WHERE user_id = uid;
        RETURN jsonb_build_object('ok', false, 'code', CASE WHEN tentativas >= 5 THEN 'PIN_LOCKED' ELSE 'PIN_INVALID' END,
            'error', CASE WHEN tentativas >= 5 THEN 'Muitas tentativas. Aguarde 15 minutos.' ELSE 'PIN incorreto.' END);
    END IF;
    UPDATE private.stock_pin_credentials SET failed_attempts = 0, locked_until = NULL WHERE user_id = uid;

    IF tipo = 'entrada' THEN
        UPDATE public.produtos AS produto
        SET quantidade = produto.quantidade + registrar_movimentacao_estoque.quantidade,
            status = CASE WHEN produto.quantidade + registrar_movimentacao_estoque.quantidade <= produto.minimo THEN 'Estoque baixo' ELSE 'Disponível' END
        WHERE produto.codigo = registrar_movimentacao_estoque.codigo_produto
          AND produto.quantidade <= 2147483647 - registrar_movimentacao_estoque.quantidade
        RETURNING produto.quantidade, produto.status INTO novo_saldo, novo_status;
    ELSE
        UPDATE public.produtos AS produto
        SET quantidade = produto.quantidade - registrar_movimentacao_estoque.quantidade,
            status = CASE WHEN produto.quantidade - registrar_movimentacao_estoque.quantidade <= produto.minimo THEN 'Estoque baixo' ELSE 'Disponível' END
        WHERE produto.codigo = registrar_movimentacao_estoque.codigo_produto
          AND produto.quantidade >= registrar_movimentacao_estoque.quantidade
        RETURNING produto.quantidade, produto.status INTO novo_saldo, novo_status;
    END IF;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'code', 'STOCK_CONFLICT', 'error', 'Produto não encontrado ou quantidade indisponível. Atualize a tela e tente novamente.');
    END IF;
    RETURN jsonb_build_object('ok', true, 'quantidade', novo_saldo, 'status', novo_status);
END;
$$;

REVOKE ALL ON FUNCTION public.configurar_pin_estoque(text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.registrar_movimentacao_estoque(text, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.configurar_pin_estoque(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registrar_movimentacao_estoque(text, text, text, integer) TO authenticated;

-- Shared stock notifications and per-user read state.
CREATE TABLE IF NOT EXISTS public.stock_notifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    title text NOT NULL,
    message text NOT NULL,
    tone text NOT NULL DEFAULT '' CHECK (tone IN ('', 'stock-alert', 'stock-warning')),
    actor_user_id uuid DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE SET NULL,
    actor_email text NOT NULL DEFAULT COALESCE(auth.jwt() ->> 'email', ''),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS stock_notifications_created_at_idx ON public.stock_notifications (created_at DESC);
ALTER TABLE public.stock_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.stock_notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.stock_notifications TO authenticated;
DROP POLICY IF EXISTS stock_notifications_read_allowlist ON public.stock_notifications;
CREATE POLICY stock_notifications_read_allowlist ON public.stock_notifications FOR SELECT TO authenticated USING (lower(coalesce(auth.jwt()->>'email','')) = ANY (string_to_array('admin@empresa.com.br,estoque@empresa.com.br', ',')));
DROP POLICY IF EXISTS stock_notifications_insert_allowlist ON public.stock_notifications;
CREATE POLICY stock_notifications_insert_allowlist ON public.stock_notifications FOR INSERT TO authenticated WITH CHECK (lower(coalesce(auth.jwt()->>'email','')) = ANY (string_to_array('admin@empresa.com.br,estoque@empresa.com.br', ',')) AND actor_user_id = (select auth.uid()) AND lower(actor_email) = lower(coalesce(auth.jwt()->>'email','')));
CREATE TABLE IF NOT EXISTS public.stock_notification_reads (
    user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    notification_id uuid NOT NULL REFERENCES public.stock_notifications(id) ON DELETE CASCADE,
    read_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, notification_id)
);
ALTER TABLE public.stock_notification_reads ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.stock_notification_reads FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.stock_notification_reads TO authenticated;
DROP POLICY IF EXISTS stock_notification_reads_own_rows ON public.stock_notification_reads;
CREATE POLICY stock_notification_reads_own_rows ON public.stock_notification_reads FOR SELECT TO authenticated USING ((select auth.uid()) = user_id);
DROP POLICY IF EXISTS stock_notification_reads_insert_own_rows ON public.stock_notification_reads;
CREATE POLICY stock_notification_reads_insert_own_rows ON public.stock_notification_reads FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = user_id);
