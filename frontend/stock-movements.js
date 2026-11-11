let activeStockMovement = null;
const stockMovementDialog = document.getElementById('stock-movement-dialog');
const stockMovementForm = document.getElementById('stock-movement-form');
const stockMovementQuantity = document.getElementById('stock-movement-quantity');
const stockMovementFeedback = document.getElementById('stock-movement-feedback');
function openStockMovement(productIndex, type) {
  const product = data.produtos[productIndex];
  if (!product) return;
  activeStockMovement = { productIndex, type };
  const isEntry = type === 'entrada';
  const stock = Number(product.quantidade) || 0;
  document.getElementById('stock-movement-title').textContent = isEntry ? 'Registrar entrada' : 'Registrar saída';
  document.getElementById('stock-movement-eyebrow').textContent = isEntry ? 'ENTRADA DE ESTOQUE' : 'SAÍDA DE ESTOQUE';
  document.getElementById('stock-movement-description').textContent = `${product.nome} · saldo atual: ${stock} ${stock === 1 ? 'unidade' : 'unidades'}.`;
  stockMovementQuantity.value = '';
  stockMovementQuantity.max = isEntry ? '' : String(stock);
  stockMovementFeedback.textContent = '';
  document.getElementById('stock-movement-submit').classList.toggle('stock-movement-out', !isEntry);
  stockMovementDialog.showModal();
  stockMovementQuantity.focus();
}
document.getElementById('content').addEventListener('click', event => {
  const button = event.target.closest('[data-stock-movement]');
  if (button) openStockMovement(Number(button.dataset.product), button.dataset.stockMovement);
});
document.getElementById('stock-movement-close').addEventListener('click', () => stockMovementDialog.close());
document.getElementById('stock-movement-cancel').addEventListener('click', () => stockMovementDialog.close());
stockMovementDialog.addEventListener('click', event => { if (event.target === stockMovementDialog) stockMovementDialog.close(); });
stockMovementForm.addEventListener('submit', async event => {
  event.preventDefault();
  if (!activeStockMovement) return;
  const amount = Number(stockMovementQuantity.value);
  if (!Number.isSafeInteger(amount) || amount <= 0) { stockMovementFeedback.textContent = 'Informe uma quantidade inteira maior que zero.'; return; }
  const { productIndex, type } = activeStockMovement;
  const product = data.produtos[productIndex];
  if (!product) { stockMovementFeedback.textContent = 'Este produto não está mais disponível.'; return; }
  const current = Number(product.quantidade) || 0;
  if (type === 'saida' && amount > current) { stockMovementFeedback.textContent = `A saída não pode exceder o saldo atual de ${current} unidades.`; return; }
  const previous = JSON.parse(JSON.stringify(data));
  const balance = type === 'entrada' ? current + amount : current - amount;
  product.quantidade = String(balance);
  const minimum = Number(product.minimo) || 0;
  product.status = balance <= minimum ? 'Estoque baixo' : 'Disponível';
  syncDerivedCounts();
  const submit = document.getElementById('stock-movement-submit');
  submit.disabled = true;
  try {
    if (!await persist()) { data = previous; return; }
    stockMovementDialog.close();
    render();
    const direction = type === 'entrada' ? 'Entrada registrada' : 'Saída registrada';
    const tone = balance <= minimum ? 'stock-alert' : type === 'saida' ? 'stock-warning' : '';
    recordStockNotification(type==='entrada'?'Entrada de estoque':'Saída de estoque',product.nome+': '+(type==='entrada'?'+':'−')+amount+' '+(amount===1?'unidade':'unidades')+'. Saldo: '+balance+'.',tone); notify(`${direction}: ${amount} ${amount === 1 ? 'unidade' : 'unidades'} de ${product.nome}. Saldo: ${balance}.`, tone);
  } finally { submit.disabled = false; }
});