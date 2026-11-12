
<?php
$arquivo = "produtos.json";

$produtos = file_exists($arquivo)
    ? json_decode(file_get_contents($arquivo), true)
    : [];

if (!is_array($produtos)) {
    $produtos = [];
}

$alterado = false;
$alertas = [];

foreach ($produtos as &$produto) {
    $quantidade = (int) ($produto["quantidade"] ?? 0);
    $minimo = (int) ($produto["estoque_minimo"] ?? 0);

    if ($quantidade <= $minimo) {
        if (empty($produto["data_baixa"])) {
            $produto["data_baixa"] = date("d/m/Y");
            $alterado = true;
        }

        $alertas[] = $produto;
    } elseif (!empty($produto["data_baixa"])) {
        $produto["data_baixa"] = "";
        $alterado = true;
    }
}
unset($produto);

if ($alterado) {
    file_put_contents(
        $arquivo,
        json_encode(
            $produtos,
            JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE
        ),
        LOCK_EX
    );
}
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Alertas de Estoque</title>
    <link rel="stylesheet" href="../frontend/alertas.css">
</head>
<body>

<main class="container">
    <header>
        <h1>🔔 Central de Alertas</h1>
        <p>Produtos que precisam de reposição.</p>
    </header>

    <section class="painel">
        <h2>Estoque baixo</h2>

        <?php if (empty($alertas)): ?>
            <p class="vazio">Nenhum produto com estoque baixo.</p>
        <?php else: ?>
            <div class="tabela">
                <table>
                    <thead>
                        <tr>
                            <th>Produto</th>
                            <th>Categoria</th>
                            <th>Fornecedor</th>
                            <th>Data da baixa</th>
                            <th>Quantidade</th>
                        </tr>
                    </thead>
                    <tbody>
                    <?php foreach ($alertas as $produto): ?>
                        <tr>
                            <td><?= htmlspecialchars($produto["nome"] ?? "") ?></td>
                            <td><?= htmlspecialchars($produto["categoria"] ?? "") ?></td>
                            <td><?= htmlspecialchars($produto["fornecedor"] ?? "") ?></td>
                            <td><?= htmlspecialchars($produto["data_baixa"] ?? "") ?></td>
                            <td>
                                <span class="quantidade">
                                    <?= (int) ($produto["quantidade"] ?? 0) ?>
                                </span>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
    </section>

    <a class="voltar" href="produtos.php">← Voltar aos produtos</a>
</main>

</body>
</html>
