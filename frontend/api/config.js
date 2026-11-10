module.exports = (request, response) => {
  response.setHeader('Cache-Control', 'no-store');

  if (request.method !== 'GET') {
    response.setHeader('Allow', 'GET');
    return response.status(405).json({ error: 'Método não permitido.' });
  }

  const url = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
  const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '';
  if (!url || !anonKey) {
    return response.status(500).json({ error: 'Configure SUPABASE_URL e SUPABASE_PUBLISHABLE_KEY no Vercel.' });
  }

  return response.status(200).json({ url, anonKey });
};
