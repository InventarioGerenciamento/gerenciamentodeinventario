let activeStockMovement = null;
const stockMovementDialog = document.getElementById('stock-movement-dialog');
const stockMovementForm = document.getElementById('stock-movement-form');
const stockMovementQuantity = document.getElementById('stock-movement-quantity');
const stockMovementPin = document.getElementById('stock-movement-pin');
const stockMovementFeedback = document.getElementById('stock-movement-feedback');
new MutationObserver(() => {
  const quantityField = document.querySelector('#form-fields input[name="quantidade"]');
  if (quantityField) {
    if (!quantityField.value) quantityField.value = '0';
    quantityField.readOnly = true;
    quantityField.title = 'Altere o saldo pelos botões de entrada e saída, com seu PIN.';
    const field = quantityField.closest('.form-field');
    if (field && !field.querySelector('.stock-balance-help')) {
      const help = document.createElement('small');
      help.className = 'stock-balance-help';
      help.textContent = document.getElementById('dialog-title').textContent.startsWith('Cadastrar')
        ? 'O saldo começa em zero. Após salvar, use Entrada na lista de produtos e confirme com seu PIN.'
        : 'Para alterar o saldo, use Entrada ou Saída na lista de produtos e confirme com seu PIN.';
      field.append(help);
    }
  }
}).observe(document.getElementById('form-fields'), { childList: true, subtree: true });
document.getElementById('content').addEventListener('click', event => {
  if (!(event.target instanceof Element)) return;
  const button = event.target.closest('[data-delete][data-key="produtos"]');
  if (!button) return;
  const product = data.produtos[Number(button.dataset.delete)];
  if (!product || Number(product.quantidade) <= 0) return;
  event.stopImmediatePropagation();
  notify(`Registre uma saída de estoque antes de excluir ${product.nome}. O saldo precisa chegar a zero.`);
}, true);
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
  stockMovementPin.value = '';
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
stockMovementDialog.addEventListener('close', () => { stockMovementPin.value = ''; });
stockMovementForm.addEventListener('submit', async event => {
  event.preventDefault();
  if (!activeStockMovement) return;
  const amount = Number(stockMovementQuantity.value);
  if (!Number.isSafeInteger(amount) || amount <= 0) { stockMovementFeedback.textContent = 'Informe uma quantidade inteira maior que zero.'; return; }
  if (!/^\d{4}$/.test(stockMovementPin.value)) { stockMovementFeedback.textContent = 'Informe seu PIN de 4 dígitos.'; return; }
  const { productIndex, type } = activeStockMovement;
  const product = data.produtos[productIndex];
  if (!product) { stockMovementFeedback.textContent = 'Este produto não está mais disponível.'; return; }
  const submit = document.getElementById('stock-movement-submit');
  submit.disabled = true;
  try {
    const result = await apiRequest({method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'stock_movement',productCode:product.codigo,type,quantity:amount,pin:stockMovementPin.value})});
    product.quantidade = String(result.quantity);
    product.status = result.status;
    const balance = result.quantity;
    stockMovementDialog.close();
    render();
    const direction = type === 'entrada' ? 'Entrada registrada' : 'Saída registrada';
    const minimum = Number(product.minimo) || 0;
    const tone = balance <= minimum ? 'stock-alert' : type === 'saida' ? 'stock-warning' : '';
    await recordStockNotification(type==='entrada'?'Entrada de estoque':'Saída de estoque',product.nome+': '+(type==='entrada'?'+':'−')+amount+' '+(amount===1?'unidade':'unidades')+'. Saldo: '+balance+'.',tone); notify(`${direction}: ${amount} ${amount === 1 ? 'unidade' : 'unidades'} de ${product.nome}. Saldo: ${balance}.`, tone);
  } catch (error) {
    stockMovementFeedback.textContent = error instanceof Error ? error.message : 'Não foi possível registrar a movimentação.';
    if (/configure seu PIN/i.test(stockMovementFeedback.textContent)) document.getElementById('stock-pin-dialog').showModal();
  } finally { submit.disabled = false; }
});

const stockPinDialog = document.getElementById('stock-pin-dialog');
document.getElementById('stock-pin-open').addEventListener('click', () => { document.getElementById('stock-pin-form').reset(); document.getElementById('stock-pin-feedback').textContent = ''; stockPinDialog.showModal(); });
document.getElementById('stock-pin-close').addEventListener('click', () => stockPinDialog.close());
document.getElementById('stock-pin-cancel').addEventListener('click', () => stockPinDialog.close());
stockPinDialog.addEventListener('click', event => { if (event.target === stockPinDialog) stockPinDialog.close(); });
stockPinDialog.addEventListener('close', () => { document.getElementById('stock-pin-form').reset(); });
document.getElementById('stock-pin-form').addEventListener('submit', async event => {
  event.preventDefault();
  const form = new FormData(event.currentTarget);
  const currentPin = String(form.get('pin_atual') || '');
  const newPin = String(form.get('novo_pin') || '');
  const confirmation = String(form.get('confirmar_pin') || '');
  const feedback = document.getElementById('stock-pin-feedback');
  const submit = document.getElementById('stock-pin-submit');
  if (!/^\d{4}$/.test(newPin)) { feedback.textContent = 'O PIN precisa ter 4 dígitos.'; return; }
  if (newPin !== confirmation) { feedback.textContent = 'Os PINs não coincidem.'; return; }
  submit.disabled = true;
  feedback.textContent = '';
  try {
    await apiRequest({method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'configure_stock_pin',currentPin:currentPin||null,newPin})});
    stockPinDialog.close();
    notify('PIN de movimentação salvo para esta conta.');
  } catch (error) {
    feedback.textContent = error instanceof Error ? error.message : 'Não foi possível salvar o PIN.';
  } finally { submit.disabled = false; }
});
