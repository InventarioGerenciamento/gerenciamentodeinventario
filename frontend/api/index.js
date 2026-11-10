const fields = {
  produtos: ['nome', 'categoria', 'fornecedor', 'marca', 'local', 'quantidade', 'minimo', 'status'],
  categorias: ['nome', 'descricao', 'produtos', 'status'],
  fornecedores: ['nome', 'contato', 'email', 'telefone', 'categoria', 'status'],
  locais: ['nome', 'categoria', 'setor', 'itens', 'responsavel', 'status'],
  usuarios: ['nome', 'cpf', 'email', 'cargo', 'status'],
};

const initialInventory = {
  produtos: [
    { nome: 'Notebook Dell Inspiron 15', categoria: 'Eletrônicos', fornecedor: 'TechSupply Brasil', marca: 'Dell', local: 'Estoque principal', quantidade: '18', minimo: '5', status: 'Disponível' },
    { nome: 'Cadeira ergonômica Pro', categoria: 'Mobiliário', fornecedor: 'Office Center', marca: 'Flexform', local: 'Sala de equipamentos', quantidade: '4', minimo: '6', status: 'Estoque baixo' },
    { nome: 'Papel sulfite A4 · caixa', categoria: 'Escritório', fornecedor: 'Papelaria Horizonte', marca: 'Chamex', local: 'Estoque principal', quantidade: '32', minimo: '10', status: 'Disponível' },
    { nome: 'Monitor LED 24 polegadas', categoria: 'Eletrônicos', fornecedor: 'TechSupply Brasil', marca: 'LG', local: 'Sala de equipamentos', quantidade: '11', minimo: '4', status: 'Disponível' },
    { nome: 'Kit teclado e mouse sem fio', categoria: 'Eletrônicos', fornecedor: 'TechSupply Brasil', marca: 'Logitech', local: 'Estoque secundário', quantidade: '3', minimo: '5', status: 'Estoque baixo' },
  ],
  categorias: [
    { nome: 'Eletrônicos', descricao: 'Equipamentos e acessórios de tecnologia', produtos: '3', status: 'Ativa' },
    { nome: 'Escritório', descricao: 'Materiais de uso cotidiano', produtos: '1', status: 'Ativa' },
    { nome: 'Mobiliário', descricao: 'Móveis para ambientes de trabalho', produtos: '1', status: 'Ativa' },
    { nome: 'Limpeza', descricao: 'Materiais de limpeza e conservação', produtos: '0', status: 'Ativa' },
  ],
  fornecedores: [
    { nome: 'TechSupply Brasil', contato: 'Rafael Costa', email: 'vendas@techsupply.com.br', telefone: '(11) 3456-7800', categoria: 'Tecnologia', status: 'Ativo' },
    { nome: 'Office Center', contato: 'Paula Mendes', email: 'paula@officecenter.com.br', telefone: '(11) 3988-1200', categoria: 'Mobiliário', status: 'Ativo' },
    { nome: 'Papelaria Horizonte', contato: 'Lucas Ribeiro', email: 'contato@horizonte.com.br', telefone: '(21) 2444-9010', categoria: 'Papelaria', status: 'Ativo' },
  ],
  locais: [
    { nome: 'Estoque principal', categoria: 'Geral', setor: 'Prédio A · Térreo', itens: '50', responsavel: 'Mariana Alves', status: 'Ativo' },
    { nome: 'Estoque secundário', categoria: 'Geral', setor: 'Prédio B · Sala 12', itens: '18', responsavel: 'João Pedro', status: 'Ativo' },
    { nome: 'Sala de equipamentos', categoria: 'Eletrônicos', setor: 'Prédio A · 2º andar', itens: '15', responsavel: 'Ana Costa', status: 'Ativo' },
  ],
  usuarios: [
    { nome: 'Mariana Alves', cpf: '•••.•••.•••-42', email: 'mariana.alves@empresa.com', cargo: 'Administradora', status: 'Ativo' },
    { nome: 'João Pedro Santos', cpf: '•••.•••.•••-18', email: 'joao.santos@empresa.com', cargo: 'Supervisor', status: 'Ativo' },
    { nome: 'Ana Costa Lima', cpf: '•••.•••.•••-73', email: 'ana.lima@empresa.com', cargo: 'Funcionária', status: 'Ativo' },
  ],
};

function validateInventory(inventory) {
  if (!inventory || typeof inventory !== 'object' || Array.isArray(inventory)) return false;
  for (const [table, tableFields] of Object.entries(fields)) {
    if (!Array.isArray(inventory[table])) return false;
    for (const row of inventory[table]) {
      if (!row || typeof row !== 'object' || Array.isArray(row)) return false;
      for (const field of tableFields) {
        if (!(field in row) || !['string', 'number', 'boolean'].includes(typeof row[field])) return false;
      }
      for (const field of ['quantidade', 'minimo']) {
        if (table === 'produtos' && (!/^\d+$/.test(String(row[field])) || Number(row[field]) > 2147483647)) return false;
      }
    }
  }
  return true;
}

async function supabaseFetch(path, token, method = 'GET', payload) {
  const baseUrl = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';
  const headers = { apikey: anonKey, Authorization: `Bearer ${token}`, Accept: 'application/json' };
  const options = { method, headers };
  if (payload !== undefined) {
    headers['Content-Type'] = 'application/json';
    options.body = JSON.stringify(payload);
  }
  const result = await fetch(`${baseUrl}${path}`, options);
  const text = await result.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch {}
  return { response: result, data };
}

module.exports = async (request, response) => {
  response.setHeader('Cache-Control', 'no-store');
  if (!['GET', 'POST'].includes(request.method)) {
    response.setHeader('Allow', 'GET, POST');
    return response.status(405).json({ error: 'Método não permitido.' });
  }

  const url = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';
  const allowedEmails = (process.env.SUPABASE_ALLOWED_EMAILS || '').split(',').map(email => email.trim().toLowerCase()).filter(Boolean);
  if (!url || !anonKey || allowedEmails.length === 0) {
    return response.status(500).json({ error: 'Configure as variáveis do Supabase no Vercel.' });
  }

  const match = /^Bearer\s+(.+)$/i.exec(request.headers.authorization || '');
  if (!match) return response.status(401).json({ error: 'Entre com sua conta para continuar.' });
  const token = match[1];

  try {
    const auth = await supabaseFetch('/auth/v1/user', token);
    if (auth.response.status === 401 || auth.response.status === 403) {
      return response.status(401).json({ error: 'Sua sessão expirou ou não é válida. Entre novamente.' });
    }
    if (!auth.response.ok || !auth.data?.email) {
      return response.status(502).json({ error: 'Não foi possível validar sua sessão no Supabase Auth.' });
    }
    if (!allowedEmails.includes(auth.data.email.toLowerCase())) {
      return response.status(403).json({ error: 'Sua conta não está autorizada a acessar o inventário.' });
    }

    if (request.method === 'GET') {
      let loaded = await supabaseFetch('/rest/v1/rpc/carregar_inventario', token);
      if (!loaded.response.ok || !loaded.data) {
        return response.status(502).json({ error: 'Não foi possível carregar o inventário do Supabase.' });
      }
      if (loaded.data.inicializado !== true) {
        const saved = await supabaseFetch('/rest/v1/rpc/salvar_inventario', token, 'POST', { dados: initialInventory });
        if (!saved.response.ok) {
          return response.status(502).json({ error: 'Não foi possível inicializar o inventário no Supabase.' });
        }
        loaded = { data: { inicializado: true, dados: initialInventory } };
      }
      return response.status(200).json(loaded.data.dados);
    }

    let body = request.body;
    if (typeof body === 'string') {
      try { body = JSON.parse(body); } catch { body = null; }
    }
    if (!validateInventory(body)) return response.status(400).json({ error: 'Dados de inventário inválidos.' });

    const saved = await supabaseFetch('/rest/v1/rpc/salvar_inventario', token, 'POST', { dados: body });
    if (!saved.response.ok) {
      return response.status(502).json({ error: 'Não foi possível salvar os dados no Supabase.' });
    }
    return response.status(200).json({ saved: true });
  } catch (error) {
    console.error('Falha na API do inventário:', error);
    return response.status(502).json({ error: 'Falha de conexão com o Supabase. Tente novamente.' });
  }
};
