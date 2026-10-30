# Senai Estoque · Gestão de Inventário

## 📌 Escopo do Projeto

### Problema
A falta de controle adequado do estoque pode causar erros nos registros de produtos, dificuldades para acompanhar entradas e saídas, perda de materiais e falta de informações atualizadas sobre as quantidades disponíveis.

### Objetivo
Desenvolver um aplicativo web para facilitar o gerenciamento de inventário, permitindo controlar produtos, fornecedores, categorias, locais de armazenamento e movimentações de estoque.

### Público-alvo
Empresas, administradores, funcionários e responsáveis pelo gerenciamento e controle de estoque.

### Solução
O sistema oferece uma plataforma web em português, desenvolvida com PHP, HTML, CSS e JavaScript, integrada ao banco de dados Supabase. Permite cadastrar, consultar, editar e excluir informações, além de controlar o acesso dos usuários por autenticação.

### Principais funcionalidades
- Cadastro, consulta, edição e exclusão de produtos.
- Gerenciamento de categorias e fornecedores.
- Cadastro de locais de armazenamento.
- Gerenciamento interno de usuários.
- Autenticação de usuários pelo Supabase Auth.
- Controle de acesso por e-mails autorizados.
- Integração com banco de dados Supabase.
- Importação inicial dos dados do SQLite para o Supabase.
- Instalação como aplicativo PWA.
- Interface adaptada para computadores e dispositivos móveis.

## 🎨 Design System

### Cores
- Cor primária: Azul, utilizada nos principais elementos da interface.
- Cor secundária: Cinza, utilizada em elementos complementares.
- Cor de fundo: Branco e tons claros de cinza.
- Cor de texto: Preto e cinza-escuro.

### 🔤 Tipografia
- Fonte principal: Fonte sem serifa.
- Títulos: Fonte em negrito para destacar seções.
- Subtítulos: Fonte com destaque intermediário.
- Texto: Fonte simples e de fácil leitura.

### 🔷 Logotipo
O logotipo representa o sistema Senai Estoque – Gestão de Inventário. Deve ser utilizado no cabeçalho e nas áreas de identificação do aplicativo, mantendo a identidade visual do projeto.

## 🛠️ Tecnologias
- HTML
- CSS
- JavaScript
- PHP 8 ou superior
- Supabase
- Supabase Auth
- PostgreSQL
- SQLite (origem da migração inicial)
- PWA (Progressive Web App)
- Service Worker
- JSON
- Git e GitHub

## 👥 Equipe
-Felipe Luiz Bozze
-Thiago Carneiro 
- Felipe Fermino
- Christian

## 📁 Organização das pastas

- `frontend/`: HTML, estilos, JavaScript, manifesto, service worker e ícones do PWA.
- `backend/`: API e roteador PHP, integração Supabase e configuração privada do servidor.
- `backend/data/`: banco SQLite antigo, mantido como origem da migração inicial para o Supabase.

## ⚙️ Configurar Supabase e acesso de usuários

1. No Supabase, crie as contas em **Authentication → Users → Add user**. O aplicativo não permite cadastro público.
2. Em **Authentication → URL Configuration**, adicione o endereço do site às URLs permitidas. Para uso local, utilize `http://localhost:8000`.
3. Copie a **Project URL**, a chave pública **anon/publishable** e a chave secreta do servidor (`service_role` ou `sb_secret_`).
4. Copie `backend/.env.example` para `backend/.env` e preencha `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY` e `SUPABASE_ALLOWED_EMAILS`.
5. No **SQL Editor**, execute `backend/supabase-schema.sql`.

A API valida cada sessão com Supabase Auth. Contas fora da lista de e-mails autorizados são bloqueadas.

A chave secreta nunca deve ser colocada no frontend ou publicada no GitHub. O arquivo `.env` está excluído do Git.

## ▶️ Executar localmente

Instale PHP 8 ou mais recente com as extensões OpenSSL, PDO e PDO_SQLite habilitadas.

Execute o servidor na raiz do projeto:

```bash
php -S localhost:8000 -t frontend backend/router.php
```

Abra o endereço:

`http://localhost:8000`

A API PHP utiliza a chave secreta apenas no servidor e comunica-se com o Supabase por HTTPS.

Na primeira leitura, o sistema transfere os dados atuais do SQLite local para o Supabase, caso o banco ainda esteja sem inventário. Depois disso, o Supabase passa a ser a fonte dos dados.

## 📱 Instalar como aplicativo

Abra o sistema em um endereço HTTPS no Chrome ou Edge e utilize a opção **Instalar app**.

No Android, abra o endereço HTTPS no Chrome.

No iPhone ou iPad, abra o endereço HTTPS no Safari, toque em **Compartilhar** e escolha **Adicionar à Tela de Início**.

A interface pode abrir offline, mas a leitura e o salvamento dos dados exigem internet e conexão com o Supabase.

## 📋 Cadastros disponíveis

- **Produtos:** nome, categoria, marca, fornecedor, local, quantidade e nível mínimo.
- **Categorias:** organização dos produtos por tipo.
- **Fornecedores:** contatos, e-mail, telefone e especialidade.
- **Locais de armazenamento:** setor, categoria e responsável.
- **Usuários:** nome, CPF ou crachá, e-mail e cargo.

Os formulários permitem incluir, editar, buscar e excluir cadastros.

## 🔄 Reiniciar os dados

Para recomeçar com os exemplos, limpe as tabelas do Supabase e defina `inicializado` como `false` em `configuracao_inventario`.

Na próxima leitura, o sistema importará novamente os dados locais.

**Atenção:** a rotina de reinicialização exige cuidado para não sobrescrever dados existentes.
