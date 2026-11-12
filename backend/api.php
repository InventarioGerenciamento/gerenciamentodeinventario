<?php
declare(strict_types=1);

const DB_FILE = __DIR__ . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'inventory.sqlite';
const LEGACY_DATA_FILE = __DIR__ . DIRECTORY_SEPARATOR . 'data' . DIRECTORY_SEPARATOR . 'inventory.json';

function supabase_credentials(): array
{
    $environmentFile = __DIR__ . DIRECTORY_SEPARATOR . '.env';
    if (is_file($environmentFile)) {
        $lines = file($environmentFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
        if ($lines === false) {
            throw new RuntimeException('Não foi possível ler o arquivo backend/.env.');
        }
        foreach ($lines as $line) {
            $line = trim($line);
            if ($line === '' || str_starts_with($line, '#')) {
                continue;
            }
            $separator = strpos($line, '=');
            if ($separator === false) {
                continue;
            }
            $name = trim(substr($line, 0, $separator));
            $value = trim(substr($line, $separator + 1));
            if (in_array($name, ['SUPABASE_URL', 'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY', 'SUPABASE_SECRET_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_ALLOWED_EMAILS'], true) && getenv($name) === false) {
                putenv($name . '=' . trim($value, " \t\n\r\0\x0B\"'"));
            }
        }
    }

    $url = rtrim((string)getenv('SUPABASE_URL'), '/');
    $key = (string)(getenv('SUPABASE_SECRET_KEY') ?: getenv('SUPABASE_SERVICE_ROLE_KEY'));
    $anonKey = (string)(getenv('SUPABASE_PUBLISHABLE_KEY') ?: getenv('SUPABASE_ANON_KEY'));
    $allowedEmails = (string)getenv('SUPABASE_ALLOWED_EMAILS');
    if ($url === '' || $key === '' || $anonKey === '') {
        throw new RuntimeException('Configure SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY e SUPABASE_SECRET_KEY em backend/.env.');
    }
    if (filter_var($url, FILTER_VALIDATE_URL) === false || strtolower((string)parse_url($url, PHP_URL_SCHEME)) !== 'https') {
        throw new RuntimeException('SUPABASE_URL precisa ser a URL HTTPS do projeto Supabase.');
    }

    return [$url, $key, $anonKey, $allowedEmails];
}

function authenticated_user(): array
{
    $token = request_access_token();
    if ($token === null) {
        throw new UnauthorizedException('Entre com sua conta para continuar.');
    }
    [$url, , $anonKey, $allowedEmails] = supabase_credentials();
    $allowed = array_values(array_filter(array_map(static fn (string $email): string => strtolower(trim($email)), explode(',', $allowedEmails))));
    if ($allowed === []) {
        throw new RuntimeException('Configure SUPABASE_ALLOWED_EMAILS com os e-mails autorizados em backend/.env.');
    }
    $context = stream_context_create(['http' => [
        'method' => 'GET',
        'header' => "apikey: " . $anonKey . "\r\nAuthorization: Bearer " . $token . "\r\nAccept: application/json",
        'ignore_errors' => true,
        'timeout' => 10,
    ]]);
    set_error_handler(static fn (): bool => true, E_WARNING);
    try {
        $response = file_get_contents($url . '/auth/v1/user', false, $context);
    } finally {
        restore_error_handler();
    }
    $status = 0;
    foreach ($http_response_header ?? [] as $header) {
        if (preg_match('/^HTTP\\/\\S+\\s+(\\d{3})/', $header, $statusMatch) === 1) {
            $status = (int)$statusMatch[1];
        }
    }
    if ($status === 401 || $status === 403) {
        throw new UnauthorizedException('Sua sessão expirou ou não é válida. Entre novamente.');
    }
    if ($response === false || $status !== 200) {
        throw new RuntimeException('Não foi possível validar sua sessão no Supabase Auth. Tente novamente.');
    }
    $user = json_decode($response, true);
    if (!is_array($user) || !is_string($user['email'] ?? null)) {
        throw new UnauthorizedException('O Supabase não retornou uma conta válida.');
    }
    if (!in_array(strtolower($user['email']), $allowed, true)) {
        throw new UnauthorizedException('Sua conta não está autorizada a acessar o inventário.');
    }
    return $user;
}

function request_access_token(): ?string
{
    $authorization = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
    return preg_match('/^Bearer\\s+(.+)$/i', trim($authorization), $matches) === 1 ? $matches[1] : null;
}

final class UnauthorizedException extends RuntimeException {}

function supabase_request(string $endpoint, string $method = 'GET', ?array $payload = null, ?string $accessToken = null): array|null
{
    [$url, $key] = supabase_credentials();
    $headers = [
        'Accept: application/json',
        'apikey: ' . $key,
    ];
    if ($accessToken !== null) {
        $headers[] = 'Authorization: Bearer ' . $accessToken;
    } elseif (!str_starts_with($key, 'sb_secret_')) {
        $headers[] = 'Authorization: Bearer ' . $key;
    }
    $options = [
        'method' => $method,
        'header' => implode("\r\n", $headers),
        'ignore_errors' => true,
        'timeout' => 15,
    ];
    if ($payload !== null) {
        $options['header'] .= "\r\nContent-Type: application/json";
        $options['content'] = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
    }

    $context = stream_context_create(['http' => $options]);
    set_error_handler(static function (int $severity, string $message): bool {
        throw new RuntimeException('Falha de conexão com o Supabase: ' . $message);
    }, E_WARNING);
    try {
        $response = file_get_contents($url . '/rest/v1/' . $endpoint, false, $context);
    } finally {
        restore_error_handler();
    }
    $status = 0;
    foreach ($http_response_header ?? [] as $header) {
        if (preg_match('/^HTTP\/\S+\s+(\d{3})/', $header, $matches) === 1) {
            $status = (int)$matches[1];
        }
    }
    if ($response === false || $status < 200 || $status >= 300) {
        $details = $response === false ? 'Sem resposta do Supabase.' : $response;
        error_log('Falha na API Supabase (' . $status . '): ' . $details);
        if (str_contains($details, 'Registre uma saída antes de excluir')) {
            throw new RuntimeException('Registre uma saída de estoque antes de excluir um produto que ainda tem saldo.');
        }
        throw new RuntimeException('Não foi possível acessar o Supabase. Confira a URL, a chave secreta e se o esquema SQL foi executado.');
    }
    if ($response === '') {
        return null;
    }

    try {
        $decoded = json_decode($response, true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException $error) {
        error_log('A API Supabase retornou JSON inválido: ' . $error->getMessage());
        throw new RuntimeException('O Supabase retornou uma resposta inválida.');
    }
    if (!is_array($decoded)) {
        throw new RuntimeException('O Supabase retornou dados em um formato inesperado.');
    }

    return $decoded;
}

function migrate_local_inventory(): array
{
    if (is_file(LEGACY_DATA_FILE)) {
        $contents = file_get_contents(LEGACY_DATA_FILE);
        $legacy = $contents === false ? null : json_decode($contents, true);
        if (is_array($legacy) && array_diff(array_keys(table_fields()), array_keys($legacy)) === []) {
            return $legacy;
        }
        throw new RuntimeException('O arquivo JSON antigo existe, mas não contém dados válidos para importar.');
    }

    if (is_file(DB_FILE)) {
        return load_data(database());
    }

    return initial_data();
}

function load_supabase_data(string $accessToken): array
{
    $result = supabase_request('rpc/carregar_inventario', 'GET', null, $accessToken);
    if (!is_array($result) || !isset($result['inicializado'], $result['dados']) || !is_array($result['dados'])) {
        throw new RuntimeException('A resposta do Supabase não tem o formato esperado. Execute backend/supabase-schema.sql no projeto.');
    }

    if ($result['inicializado'] !== true) {
        $seed = migrate_local_inventory();
        validate_data($seed);
        supabase_request('rpc/salvar_inventario', 'POST', ['dados' => $seed], $accessToken);
        return $seed;
    }

    return $result['dados'];
}

function validate_data(array &$payload): void
{
    $products = is_array($payload['produtos'] ?? null) ? $payload['produtos'] : [];
    foreach ((is_array($payload['categorias'] ?? null) ? $payload['categorias'] : []) as $index => $category) {
        if (is_array($category)) {
            $payload['categorias'][$index]['produtos'] = (string)count(array_filter($products, static fn ($product): bool => is_array($product) && ($product['categoria'] ?? null) === ($category['nome'] ?? null)));
        }
    }
    foreach ((is_array($payload['locais'] ?? null) ? $payload['locais'] : []) as $index => $location) {
        if (is_array($location)) {
            $payload['locais'][$index]['itens'] = (string)count(array_filter($products, static fn ($product): bool => is_array($product) && ($product['local'] ?? null) === ($location['nome'] ?? null)));
        }
    }
    $expected = table_fields();
    if (array_diff(array_keys($expected), array_keys($payload)) !== []) {
        throw new InvalidArgumentException('Dados de inventário inválidos.');
    }

    foreach ($expected as $table => $fields) {
        if (!is_array($payload[$table])) {
            throw new InvalidArgumentException('A lista ' . $table . ' precisa ser válida.');
        }
        foreach ($payload[$table] as $record) {
            if (!is_array($record)) {
                throw new InvalidArgumentException('A lista ' . $table . ' contém um registro inválido.');
            }
            foreach ($fields as $field) {
                if (!array_key_exists($field, $record)) {
                    throw new InvalidArgumentException('O campo ' . $field . ' está ausente em um registro de ' . $table . '.');
                }
                $value = $record[$field];
                if (!is_scalar($value)) {
                    throw new InvalidArgumentException('O campo ' . $field . ' contém um valor inválido.');
                }
                if (in_array($field, ['quantidade', 'minimo'], true) && (!ctype_digit((string)$value) || (int)$value > 2147483647)) {
                    throw new InvalidArgumentException('Os campos de quantidade precisam ser números inteiros não negativos.');
                }
            }
        }
    }
}

function initial_data(): array
{
    return [
        'produtos' => [
            ['nome'=>'Notebook Dell Inspiron 15','categoria'=>'Eletrônicos','fornecedor'=>'TechSupply Brasil','marca'=>'Dell','local'=>'Estoque principal','quantidade'=>'18','minimo'=>'5','status'=>'Disponível'],
            ['nome'=>'Cadeira ergonômica Pro','categoria'=>'Mobiliário','fornecedor'=>'Office Center','marca'=>'Flexform','local'=>'Sala de equipamentos','quantidade'=>'4','minimo'=>'6','status'=>'Estoque baixo'],
            ['nome'=>'Papel sulfite A4 · caixa','categoria'=>'Escritório','fornecedor'=>'Papelaria Horizonte','marca'=>'Chamex','local'=>'Estoque principal','quantidade'=>'32','minimo'=>'10','status'=>'Disponível'],
            ['nome'=>'Monitor LED 24 polegadas','categoria'=>'Eletrônicos','fornecedor'=>'TechSupply Brasil','marca'=>'LG','local'=>'Sala de equipamentos','quantidade'=>'11','minimo'=>'4','status'=>'Disponível'],
            ['nome'=>'Kit teclado e mouse sem fio','categoria'=>'Eletrônicos','fornecedor'=>'TechSupply Brasil','marca'=>'Logitech','local'=>'Estoque secundário','quantidade'=>'3','minimo'=>'5','status'=>'Estoque baixo'],
        ],
        'categorias' => [
            ['nome'=>'Eletrônicos','descricao'=>'Equipamentos e acessórios de tecnologia','produtos'=>'3','status'=>'Ativa'],
            ['nome'=>'Escritório','descricao'=>'Materiais de uso cotidiano','produtos'=>'1','status'=>'Ativa'],
            ['nome'=>'Mobiliário','descricao'=>'Móveis para ambientes de trabalho','produtos'=>'1','status'=>'Ativa'],
            ['nome'=>'Limpeza','descricao'=>'Materiais de limpeza e conservação','produtos'=>'0','status'=>'Ativa'],
        ],
        'fornecedores' => [
            ['nome'=>'TechSupply Brasil','contato'=>'Rafael Costa','email'=>'vendas@techsupply.com.br','telefone'=>'(11) 3456-7800','categoria'=>'Tecnologia','status'=>'Ativo'],
            ['nome'=>'Office Center','contato'=>'Paula Mendes','email'=>'paula@officecenter.com.br','telefone'=>'(11) 3988-1200','categoria'=>'Mobiliário','status'=>'Ativo'],
            ['nome'=>'Papelaria Horizonte','contato'=>'Lucas Ribeiro','email'=>'contato@horizonte.com.br','telefone'=>'(21) 2444-9010','categoria'=>'Papelaria','status'=>'Ativo'],
        ],
        'locais' => [
            ['nome'=>'Estoque principal','categoria'=>'Geral','setor'=>'Prédio A · Térreo','itens'=>'50','responsavel'=>'Mariana Alves','status'=>'Ativo'],
            ['nome'=>'Estoque secundário','categoria'=>'Geral','setor'=>'Prédio B · Sala 12','itens'=>'18','responsavel'=>'João Pedro','status'=>'Ativo'],
            ['nome'=>'Sala de equipamentos','categoria'=>'Eletrônicos','setor'=>'Prédio A · 2º andar','itens'=>'15','responsavel'=>'Ana Costa','status'=>'Ativo'],
        ],
        'usuarios' => [
            ['nome'=>'Mariana Alves','cpf'=>'•••.•••.•••-42','email'=>'mariana.alves@empresa.com','cargo'=>'Administradora','status'=>'Ativo'],
            ['nome'=>'João Pedro Santos','cpf'=>'•••.•••.•••-18','email'=>'joao.santos@empresa.com','cargo'=>'Supervisor','status'=>'Ativo'],
            ['nome'=>'Ana Costa Lima','cpf'=>'•••.•••.•••-73','email'=>'ana.lima@empresa.com','cargo'=>'Funcionária','status'=>'Ativo'],
        ],
    ];
}

function table_fields(): array
{
    return [
        'produtos' => ['nome', 'categoria', 'fornecedor', 'marca', 'local', 'quantidade', 'minimo', 'status'],
        'categorias' => ['nome', 'descricao', 'produtos', 'status'],
        'fornecedores' => ['nome', 'contato', 'email', 'telefone', 'categoria', 'status'],
        'locais' => ['nome', 'categoria', 'setor', 'itens', 'responsavel', 'status'],
        'usuarios' => ['nome', 'cpf', 'email', 'cargo', 'status'],
    ];
}

function database(): PDO
{
    $directory = dirname(DB_FILE);
    if (!is_dir($directory) && !mkdir($directory, 0775, true) && !is_dir($directory)) {
        throw new RuntimeException('Não foi possível preparar a pasta do banco de dados.');
    }

    $pdo = new PDO('sqlite:' . DB_FILE);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec('PRAGMA foreign_keys = ON');

    $schema = [
        'produtos' => 'id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, categoria TEXT NOT NULL, fornecedor TEXT NOT NULL, marca TEXT NOT NULL, local TEXT NOT NULL, quantidade INTEGER NOT NULL, minimo INTEGER NOT NULL, status TEXT NOT NULL',
        'categorias' => 'id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, descricao TEXT NOT NULL, produtos TEXT NOT NULL, status TEXT NOT NULL',
        'fornecedores' => 'id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, contato TEXT NOT NULL, email TEXT NOT NULL, telefone TEXT NOT NULL, categoria TEXT NOT NULL, status TEXT NOT NULL',
        'locais' => 'id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, categoria TEXT NOT NULL, setor TEXT NOT NULL, itens TEXT NOT NULL, responsavel TEXT NOT NULL, status TEXT NOT NULL',
        'usuarios' => 'id INTEGER PRIMARY KEY AUTOINCREMENT, nome TEXT NOT NULL, cpf TEXT NOT NULL, email TEXT NOT NULL, cargo TEXT NOT NULL, status TEXT NOT NULL',
    ];

    foreach ($schema as $table => $columns) {
        $pdo->exec('CREATE TABLE IF NOT EXISTS ' . $table . ' (' . $columns . ')');
    }
    $pdo->exec('CREATE TABLE IF NOT EXISTS configuracoes (chave TEXT PRIMARY KEY, valor TEXT NOT NULL)');

    $initialized = $pdo->query("SELECT valor FROM configuracoes WHERE chave = 'dados_inicializados'")->fetchColumn();
    if ($initialized === false) {
        $seed = initial_data();
        if (is_file(LEGACY_DATA_FILE)) {
            $contents = file_get_contents(LEGACY_DATA_FILE);
            $legacy = $contents === false ? null : json_decode($contents, true);
            $expected = array_keys(table_fields());
            if (!is_array($legacy) || array_diff($expected, array_keys($legacy))) {
                throw new RuntimeException('O arquivo JSON antigo existe, mas não contém dados válidos para importar.');
            }
            foreach ($expected as $table) {
                if (!is_array($legacy[$table])) {
                    throw new RuntimeException('A lista ' . $table . ' no arquivo JSON antigo é inválida.');
                }
            }
            $seed = $legacy;
        }

        $pdo->beginTransaction();
        try {
            save_data($pdo, $seed);
            $statement = $pdo->prepare("INSERT INTO configuracoes (chave, valor) VALUES ('dados_inicializados', '1')");
            $statement->execute();
            $pdo->commit();
        } catch (Throwable $error) {
            if ($pdo->inTransaction()) {
                $pdo->rollBack();
            }
            throw $error;
        }
    }

    return $pdo;
}

function load_data(PDO $pdo): array
{
    $data = [];
    foreach (table_fields() as $table => $fields) {
        $columns = implode(', ', $fields);
        $statement = $pdo->query('SELECT ' . $columns . ' FROM ' . $table . ' ORDER BY id');
        $data[$table] = array_map(
            static fn (array $row): array => array_map(static fn ($value): string => (string)$value, $row),
            $statement->fetchAll(PDO::FETCH_ASSOC)
        );
    }
    return $data;
}

function save_data(PDO $pdo, array $payload): void
{
    foreach (table_fields() as $table => $fields) {
        $pdo->exec('DELETE FROM ' . $table);
        $columns = implode(', ', $fields);
        $placeholders = implode(', ', array_fill(0, count($fields), '?'));
        $statement = $pdo->prepare('INSERT INTO ' . $table . ' (' . $columns . ') VALUES (' . $placeholders . ')');

        foreach ($payload[$table] as $record) {
            if (!is_array($record)) {
                throw new InvalidArgumentException('A lista ' . $table . ' contém um registro inválido.');
            }
            $values = [];
            foreach ($fields as $field) {
                $value = $record[$field] ?? '';
                if (!is_scalar($value)) {
                    throw new InvalidArgumentException('O campo ' . $field . ' contém um valor inválido.');
                }
                $values[] = (string)$value;
            }
            $statement->execute($values);
        }
    }
}

if (isset($_GET['api']) || in_array(parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH), ['/api', '/api/config'], true)) {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    $method = $_SERVER['REQUEST_METHOD'];
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH);

    if ($path === '/api/config') {
        if ($method !== 'GET') {
            http_response_code(405);
            header('Allow: GET');
            echo json_encode(['error' => 'Método não permitido.']);
            exit;
        }
        try {
            [$url, , $anonKey] = supabase_credentials();
            echo json_encode(['url' => $url, 'anonKey' => $anonKey], JSON_UNESCAPED_SLASHES);
        } catch (RuntimeException $error) {
            http_response_code(500);
            echo json_encode(['error' => $error->getMessage()], JSON_UNESCAPED_UNICODE);
        }
        exit;
    }

    if (!in_array($method, ['GET', 'POST'], true)) {
        http_response_code(405);
        header('Allow: GET, POST');
        echo json_encode(['error' => 'Método não permitido.']);
        exit;
    }

    try {
        authenticated_user();
        $accessToken = request_access_token();
        if ($method === 'GET') {
            echo json_encode(load_supabase_data($accessToken), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            exit;
        }

        $payload = json_decode((string)file_get_contents('php://input'), true);
        if (!is_array($payload)) {
            throw new InvalidArgumentException('Dados de inventário inválidos.');
        }

        if (($payload['action'] ?? null) === 'configure_stock_pin') {
            $newPin = (string)($payload['newPin'] ?? '');
            $currentPin = isset($payload['currentPin']) ? (string)$payload['currentPin'] : null;
            if (preg_match('/^\\d{4}$/', $newPin) !== 1 || ($currentPin !== null && preg_match('/^\\d{4}$/', $currentPin) !== 1)) {
                throw new InvalidArgumentException('O PIN precisa ter 4 dígitos.');
            }
            $result = supabase_request('rpc/configurar_pin_estoque', 'POST', ['novo_pin' => $newPin, 'pin_atual' => $currentPin], $accessToken);
            if (($result['ok'] ?? false) !== true) {
                http_response_code(($result['code'] ?? '') === 'PIN_LOCKED' ? 423 : 400);
                echo json_encode(['error' => $result['error'] ?? 'Não foi possível configurar o PIN.'], JSON_UNESCAPED_UNICODE);
                exit;
            }
            echo json_encode(['configured' => true]);
            exit;
        }

        if (($payload['action'] ?? null) === 'stock_movement') {
            $pin = (string)($payload['pin'] ?? '');
            $productCode = (string)($payload['productCode'] ?? '');
            $type = (string)($payload['type'] ?? '');
            $quantity = filter_var($payload['quantity'] ?? null, FILTER_VALIDATE_INT);
            if (preg_match('/^\\d{4}$/', $pin) !== 1 || $productCode === '' || !in_array($type, ['entrada', 'saida'], true) || $quantity === false || $quantity <= 0) {
                throw new InvalidArgumentException('Dados da movimentação inválidos.');
            }
            $result = supabase_request('rpc/registrar_movimentacao_estoque', 'POST', [
                'pin' => $pin, 'codigo_produto' => $productCode, 'tipo' => $type, 'quantidade' => $quantity,
            ], $accessToken);
            if (($result['ok'] ?? false) !== true) {
                $code = $result['code'] ?? '';
                http_response_code($code === 'PIN_NOT_SET' || $code === 'STOCK_CONFLICT' ? 409 : ($code === 'PIN_LOCKED' ? 423 : 400));
                echo json_encode(['error' => $result['error'] ?? 'Não foi possível registrar a movimentação.'], JSON_UNESCAPED_UNICODE);
                exit;
            }
            echo json_encode(['quantity' => $result['quantidade'], 'status' => $result['status']], JSON_UNESCAPED_UNICODE);
            exit;
        }
        validate_data($payload);
        supabase_request('rpc/salvar_inventario', 'POST', ['dados' => $payload], $accessToken);
        echo json_encode(['saved' => true]);
        exit;
    } catch (UnauthorizedException $error) {
        http_response_code(401);
        echo json_encode(['error' => $error->getMessage()], JSON_UNESCAPED_UNICODE);
        exit;
    } catch (InvalidArgumentException $error) {
        http_response_code(400);
        echo json_encode(['error' => $error->getMessage()], JSON_UNESCAPED_UNICODE);
        exit;
    } catch (PDOException $error) {
        error_log('Erro ao importar o banco SQLite antigo: ' . $error->getMessage());
        http_response_code(500);
        echo json_encode(['error' => 'Falha ao importar os dados locais antigos. Verifique se a extensão PDO_SQLite está habilitada e se o banco local pode ser lido.'], JSON_UNESCAPED_UNICODE);
        exit;
    } catch (RuntimeException $error) {
        error_log('Erro ao inicializar o banco de dados do inventário: ' . $error->getMessage());
        http_response_code(500);
        echo json_encode(['error' => $error->getMessage()], JSON_UNESCAPED_UNICODE);
        exit;
    }
}
