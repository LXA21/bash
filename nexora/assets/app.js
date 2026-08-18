/* =========================================================
   SISTEMA DE FACTURACIÓN
   BUSCADOR DE PRODUCTOS - VENTAS Y COMPRAS
   ========================================================= */

let productModalRow = null;
let productModalMode = 'sale';
let productModalInitialized = false;
let lastSaleTotal = 0;


/* =========================================================
   UTILIDADES
   ========================================================= */

function esc(value) {
    return String(value ?? '').replace(/[&<>"']/g, function (m) {
        return {
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
        }[m];
    });
}


function normalizeSearch(value) {
    return String(value ?? '')
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .trim()
        .toLowerCase();
}


function fmt(value) {
    return '$' + Number(value || 0).toLocaleString('en-US', {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2
    });
}


/* =========================================================
   CREAR MODAL AUTOMÁTICAMENTE
   ========================================================= */

function ensureProductModal() {

    /* Si ya lo inicializamos una vez, no lo vuelvas a crear */
    if (productModalInitialized) {
        return;
    }

    /* IMPORTANTE:
       Elimina cualquier modal viejo o duplicado que venga
       de PHP (_footer.php, _header.php, index.php, etc.)
       para evitar que bloquee la creación del modal real
       y que sus clases/CSS no coincidan con style.css. */

    const oldModal = document.getElementById('productModal');

    if (oldModal) {

        oldModal.remove();

    }

    const modal = document.createElement('div');

    modal.id = 'productModal';
    modal.className = 'product-modal';
    modal.setAttribute('aria-hidden', 'true');

    modal.innerHTML = `

        <div class="product-modal-box">

            <div class="product-modal-header">

                <div class="product-modal-title-wrap">

                    <div class="product-modal-icon">
                        🔎
                    </div>

                    <div>

                        <h2 id="productModalTitle">
                            Seleccionar producto
                        </h2>

                        <p id="productModalSubtitle">
                            Busca el producto por nombre o código
                        </p>

                    </div>

                </div>

                <button
                    type="button"
                    id="productModalClose"
                    class="product-modal-close"
                    aria-label="Cerrar"
                    title="Cerrar"
                >
                    ×
                </button>

            </div>


            <div class="product-search">

                <div class="product-search-box">

                    <span class="product-search-icon">
                        🔍
                    </span>

                    <input
                        type="text"
                        id="productSearch"
                        autocomplete="off"
                        placeholder="Buscar por nombre o código..."
                    >

                    <button
                        type="button"
                        id="productSearchClear"
                        class="product-search-clear"
                        title="Limpiar búsqueda"
                    >
                        ×
                    </button>

                </div>


                <div class="product-search-meta">

                    <span>
                        Escribe para buscar
                    </span>

                    <span id="productResultCount">
                        0 productos
                    </span>

                </div>

            </div>


            <div
                id="productResults"
                class="product-results"
            ></div>

        </div>

    `;

    document.body.appendChild(modal);


    /* =====================================================
       CERRAR CON X
       ===================================================== */

    const closeButton =
        document.getElementById('productModalClose');

    if (closeButton) {

        closeButton.addEventListener('click', function (event) {

            event.preventDefault();
            event.stopPropagation();

            closeProductModal();

        });

    }


    /* =====================================================
       CERRAR HACIENDO CLIC EN EL FONDO
       ===================================================== */

    modal.addEventListener('click', function (event) {

        if (event.target === modal) {

            closeProductModal();

        }

    });


    /* =====================================================
       BUSCAR
       ===================================================== */

    const search =
        document.getElementById('productSearch');

    if (search) {

        search.addEventListener('input', function () {

            renderProductResults(this.value);

            updateSearchClear();

        });


        /* ENTER */

        search.addEventListener('keydown', function (event) {

            if (event.key !== 'Enter') {
                return;
            }

            event.preventDefault();

            const first =
                document.querySelector(
                    '#productResults .product-result'
                );

            if (first) {

                selectProductFromModal(
                    first.dataset.productId
                );

            }

        });

    }


    /* =====================================================
       LIMPIAR BÚSQUEDA
       ===================================================== */

    const clearButton =
        document.getElementById('productSearchClear');

    if (clearButton) {

        clearButton.addEventListener('click', function (event) {

            event.preventDefault();
            event.stopPropagation();

            if (search) {

                search.value = '';

                renderProductResults('');

                updateSearchClear();

                search.focus();

            }

        });

    }


    /* =====================================================
       ESC
       ===================================================== */

    document.addEventListener('keydown', function (event) {

        if (
            event.key === 'Escape' &&
            modal.getAttribute('aria-hidden') === 'false'
        ) {

            closeProductModal();

        }

    });


    /* =====================================================
       CLIC EN PRODUCTO
       ===================================================== */

    const results =
        document.getElementById('productResults');

    if (results) {

        results.addEventListener('click', function (event) {

            const product =
                event.target.closest('.product-result');

            if (!product) {
                return;
            }

            event.preventDefault();

            selectProductFromModal(
                product.dataset.productId
            );

        });

    }

    productModalInitialized = true;

}


/* =========================================================
   ABRIR MODAL
   ========================================================= */

function openProductModal(row, mode = 'sale') {

    if (!row) {

        console.error(
            'No se encontró la fila del producto.'
        );

        return;

    }


    /* Asegurar que exista el modal */

    ensureProductModal();


    const modal =
        document.getElementById('productModal');

    const search =
        document.getElementById('productSearch');


    if (!modal || !search) {

        console.error(
            'No se pudo crear el selector de productos.'
        );

        return;

    }


    /* Guardar fila */

    productModalRow = row;


    /* Guardar modo */

    productModalMode =
        mode === 'purchase'
            ? 'purchase'
            : 'sale';


    /* Limpiar búsqueda */

    search.value = '';


    /* Abrir */

    modal.setAttribute(
        'aria-hidden',
        'false'
    );


    modal.classList.add('show');


    document.body.classList.add(
        'product-modal-open'
    );


    /* Mostrar mensaje inicial */

    renderProductResults('');


    updateSearchClear();


    /* Enfocar */

    setTimeout(function () {

        search.focus();

    }, 50);

}


/* =========================================================
   CERRAR MODAL
   ========================================================= */

function closeProductModal() {

    const modal =
        document.getElementById('productModal');

    const search =
        document.getElementById('productSearch');

    const clear =
        document.getElementById('productSearchClear');


    if (search) {

        search.value = '';

        search.blur();

    }


    if (modal) {

        modal.classList.remove('show');

        modal.setAttribute(
            'aria-hidden',
            'true'
        );

    }


    if (clear) {

        clear.classList.remove(
            'visible'
        );

    }


    document.body.classList.remove(
        'product-modal-open'
    );


    /* IMPORTANTE:
       NO borrar la fila antes de terminar
       la selección. */

    productModalRow = null;

    productModalMode = 'sale';

}


/* =========================================================
   X DEL BUSCADOR
   ========================================================= */

function updateSearchClear() {

    const input =
        document.getElementById(
            'productSearch'
        );

    const clear =
        document.getElementById(
            'productSearchClear'
        );


    if (!input || !clear) {
        return;
    }


    if (input.value.trim() !== '') {

        clear.classList.add(
            'visible'
        );

    } else {

        clear.classList.remove(
            'visible'
        );

    }

}


/* =========================================================
   MOSTRAR RESULTADOS
   ========================================================= */

function renderProductResults(text = '') {

    const container =
        document.getElementById(
            'productResults'
        );


    const countElement =
        document.getElementById(
            'productResultCount'
        );


    if (!container) {
        return;
    }


    const products =
        Array.isArray(window.products)
            ? window.products
            : [];


    const search =
        normalizeSearch(text);


    /* =====================================================
       SIN TEXTO
       ===================================================== */

    if (!search) {

        container.innerHTML = `

            <div class="product-no-results">

                <div style="font-size:28px;margin-bottom:8px;">
                    🔎
                </div>

                Escribe el nombre o código
                del producto que deseas buscar.

            </div>

        `;


        if (countElement) {

            countElement.textContent =
                products.length +
                (
                    products.length === 1
                        ? ' producto'
                        : ' productos'
                );

        }

        return;

    }


    /* =====================================================
       FILTRAR
       ===================================================== */

    const results =
        products.filter(function (product) {

            const codigo =
                normalizeSearch(
                    product.codigo
                );

            const nombre =
                normalizeSearch(
                    product.nombre
                );

            return (
                codigo.includes(search) ||
                nombre.includes(search)
            );

        });


    /* =====================================================
       CONTADOR
       ===================================================== */

    if (countElement) {

        countElement.textContent =
            results.length +
            (
                results.length === 1
                    ? ' resultado'
                    : ' resultados'
            );

    }


    /* =====================================================
       SIN RESULTADOS
       ===================================================== */

    if (!results.length) {

        container.innerHTML = `

            <div class="product-no-results">

                <div style="font-size:28px;margin-bottom:8px;">
                    📦
                </div>

                No se encontraron productos
                con esa búsqueda.

            </div>

        `;

        return;

    }


    /* =====================================================
       CREAR RESULTADOS
       ===================================================== */

    container.innerHTML =
        results.map(function (product) {

            const stock =
                Number(
                    product.stock || 0
                );


            let price = 0;

            let label = 'Precio';


            if (
                productModalMode ===
                'purchase'
            ) {

                price =
                    Number(
                        product.costo_promedio || 0
                    );

                label = 'Costo';

            } else {

                price =
                    Number(
                        product.precio_venta || 0
                    );

            }


            let imageHTML = '';


            if (product.imagen) {

                imageHTML = `

                    <img
                        src="${esc(product.imagen)}"
                        alt="${esc(product.nombre)}"
                        class="product-modal-image"
                    >

                `;

            } else {

                imageHTML = `

                    <div class="product-modal-image-placeholder">
                        📦
                    </div>

                `;

            }


            return `

                <button
                    type="button"
                    class="product-result"
                    data-product-id="${esc(product.id_producto)}"
                >

                    <div class="product-result-main">

                        <div class="product-result-image">

                            ${imageHTML}

                        </div>


                        <div class="product-result-content">

                            <div class="product-result-name">

                                ${esc(product.nombre)}

                            </div>


                            <div class="product-result-code">

                                Código:
                                ${esc(product.codigo)}

                            </div>


                            <div class="product-result-info">

                                <span class="product-result-stock">

                                    Stock:
                                    ${stock}

                                </span>


                                <span class="product-result-price">

                                    ${label}:
                                    ${fmt(price)}

                                </span>

                            </div>

                        </div>

                    </div>

                </button>

            `;

        }).join('');

}


/* =========================================================
   SELECCIONAR PRODUCTO
   ========================================================= */

function selectProductFromModal(productId) {

    const products =
        Array.isArray(window.products)
            ? window.products
            : [];


    const product =
        products.find(function (p) {

            return Number(
                p.id_producto
            ) === Number(productId);

        });


    if (!product) {

        console.error(
            'Producto no encontrado:',
            productId
        );

        return;

    }


    if (!productModalRow) {

        console.error(
            'No existe una fila seleccionada.'
        );

        return;

    }


    /* =====================================================
       GUARDAR REFERENCIAS ANTES DE CERRAR
       ===================================================== */

    const row =
        productModalRow;

    const mode =
        productModalMode;


    /* =====================================================
       ID DEL PRODUCTO
       ===================================================== */

    const hidden =
        row.querySelector(
            '.product-id'
        );


    if (hidden) {

        hidden.value =
            product.id_producto;

    }


    /* =====================================================
       BOTÓN DE PRODUCTO
       ===================================================== */

    const button =
        row.querySelector(
            '.select-product-btn'
        );


    if (button) {

        button.classList.add(
            'has-product'
        );


        button.innerHTML = `

            <span class="selected-product">

                <strong>
                    ${esc(product.nombre)}
                </strong>

                <small>
                    Código: ${esc(product.codigo)}
                </small>

            </span>

            <span class="selected-product-arrow">
                ›
            </span>

        `;

    }


    /* =====================================================
       VENTA
       ===================================================== */

    if (mode === 'sale') {

        const stock =
            row.querySelector(
                '.stock'
            );


        const price =
            row.querySelector(
                '.price'
            );


        if (stock) {

            stock.textContent =
                Number(
                    product.stock || 0
                );

            stock.classList.toggle(
                'low-stock',
                Number(product.stock || 0) <= 5
            );

        }


        if (price) {

            price.value =
                Number(
                    product.precio_venta || 0
                ).toFixed(2);

        }


        calcSale();

    }


    /* =====================================================
       COMPRA
       ===================================================== */

    if (mode === 'purchase') {

        const cost =
            row.querySelector(
                '.cost'
            );


        if (cost) {

            cost.value =
                Number(
                    product.costo_promedio || 0
                ).toFixed(2);

        }


        calcPurchase();

    }


    /* =====================================================
       CERRAR INMEDIATAMENTE
       ===================================================== */

    closeProductModal();

}


/* =========================================================
   VENTAS
   ========================================================= */

function addSaleRow() {

    const tbody =
        document.querySelector(
            '#saleTable tbody'
        );


    if (!tbody) {
        return;
    }


    const tr =
        document.createElement('tr');


    tr.innerHTML = `

        <td class="product-cell">

            <input
                type="hidden"
                name="product_id[]"
                class="product-id"
                value=""
            >

            <button
                type="button"
                class="select-product-btn"
            >

                <span class="product-placeholder">
                    Seleccionar producto
                </span>

            </button>

        </td>


        <td class="stock">
            -
        </td>


        <td>

            <input
                name="price[]"
                class="price"
                type="number"
                step="0.01"
                min="0"
                value="0"
            >

        </td>


        <td>

            <input
                name="quantity[]"
                class="qty"
                type="number"
                min="0.001"
                step="0.001"
                value="1"
            >

        </td>


        <td class="line">
            $0.00
        </td>


        <td>

            <button
                type="button"
                class="btn sm danger remove-sale"
                title="Eliminar producto"
            >
                ×
            </button>

        </td>

    `;


    tbody.appendChild(tr);

    calcSale();

}


/* =========================================================
   CALCULAR VENTA
   ========================================================= */



function calcSale() {

    let subtotal = 0;


    document
        .querySelectorAll(
            '#saleTable tbody tr'
        )
        .forEach(function (tr) {

            const qty =
                Number(
                    tr.querySelector(
                        '.qty'
                    )?.value || 0
                );


            const price =
                Number(
                    tr.querySelector(
                        '.price'
                    )?.value || 0
                );


            const total =
                qty * price;


            subtotal += total;


            const line =
                tr.querySelector(
                    '.line'
                );


            if (line) {

                line.textContent =
                    fmt(total);

            }

        });


    const form =
        document.getElementById(
            'saleForm'
        );


    const discount =
        Number(
            form?.querySelector(
                '[name="descuento"]'
            )?.value || 0
        );


    const tax =
        Number(
            form?.querySelector(
                '[name="impuesto"]'
            )?.value || 0
        );


    const subtotalElement =
        document.getElementById(
            'saleSubtotal'
        );


    const totalElement =
        document.getElementById(
            'saleTotal'
        );


    const totalValue =
        Math.max(
            0,
            subtotal -
            discount +
            tax
        );


    if (subtotalElement) {

        subtotalElement.textContent =
            fmt(subtotal);

    }


        if (totalElement) {

        totalElement.textContent =
            fmt(totalValue);

    }


    lastSaleTotal = totalValue;

    renderSaleConversions(totalValue);


    /* Si ya hay métodos de pago elegidos, actualiza
       sus montos automáticamente con el nuevo total */

    document
        .querySelectorAll('#paymentsTable tbody tr')
        .forEach(function (row) {

            syncPaymentRow(row);

        });

}

/* =========================================================
   MOSTRAR CONVERSIÓN A OTRAS MONEDAS
   (el total del producto siempre se calcula en USD;
   esto solo muestra el equivalente informativo)
   ========================================================= */

function renderConversions(containerId, totalUsd) {

    const container =
        document.getElementById(
            containerId
        );

    if (!container) {
        return;
    }

    const currencies =
        window.currencies || [];

    const parts = [];

    currencies.forEach(function (c) {

        if (Number(c.es_moneda_base) === 1) {
            return;
        }

        const rate =
            Number(c.tasa_referencia || 0);

        if (rate <= 0) {
            return;
        }

        const converted =
            totalUsd / rate;

        parts.push(
            '≈ ' +
            (c.simbolo || '') +
            converted.toLocaleString('en-US', {
                minimumFractionDigits: 2,
                maximumFractionDigits: 2
            }) +
            ' ' + c.codigo
        );

    });

    container.textContent =
        parts.join('   ·   ');

}


function renderSaleConversions(totalUsd) {

    renderConversions('saleConversions', totalUsd);

}


function renderPurchaseConversions(totalUsd) {

    renderConversions('purchaseConversions', totalUsd);

}


/* =========================================================
   COMPRAS
   ========================================================= */

function addPurchaseRow() {

    const tbody =
        document.querySelector(
            '#purchaseTable tbody'
        );


    if (!tbody) {
        return;
    }


    const tr =
        document.createElement('tr');


    tr.innerHTML = `

        <td class="product-cell">

            <input
                type="hidden"
                name="product_id[]"
                class="product-id"
                value=""
            >

            <button
                type="button"
                class="select-product-btn"
            >

                <span class="product-placeholder">
                    Seleccionar producto
                </span>

            </button>

        </td>


        <td>

            <input
                name="cost[]"
                class="cost"
                type="number"
                step="0.01"
                min="0"
                value="0"
            >

        </td>


        <td>

            <input
                name="quantity[]"
                class="qty"
                type="number"
                min="0.001"
                step="0.001"
                value="1"
            >

        </td>


        <td class="line">
            $0.00
        </td>


        <td>

            <button
                type="button"
                class="btn sm danger remove-purchase"
                title="Eliminar producto"
            >
                ×
            </button>

        </td>

    `;


    tbody.appendChild(tr);

    calcPurchase();

}


/* =========================================================
   CALCULAR COMPRA
   ========================================================= */

function calcPurchase() {

    let subtotal = 0;


    document
        .querySelectorAll(
            '#purchaseTable tbody tr'
        )
        .forEach(function (tr) {

            const qty =
                Number(
                    tr.querySelector(
                        '.qty'
                    )?.value || 0
                );


            const cost =
                Number(
                    tr.querySelector(
                        '.cost'
                    )?.value || 0
                );


            const total =
                qty * cost;


            subtotal += total;


            const line =
                tr.querySelector(
                    '.line'
                );


            if (line) {

                line.textContent =
                    fmt(total);

            }

        });


    const form =
        document.getElementById(
            'purchaseForm'
        );


    const discount =
        Number(
            form?.querySelector(
                '[name="descuento"]'
            )?.value || 0
        );


    const tax =
        Number(
            form?.querySelector(
                '[name="impuesto"]'
            )?.value || 0
        );


    const subtotalElement =
        document.getElementById(
            'purchaseSubtotal'
        );


    const totalElement =
        document.getElementById(
            'purchaseTotal'
        );


    if (subtotalElement) {

        subtotalElement.textContent =
            fmt(subtotal);

    }


       const totalValue =
        Math.max(
            0,
            subtotal -
            discount +
            tax
        );


    if (totalElement) {

        totalElement.textContent =
            fmt(totalValue);

    }


    renderPurchaseConversions(totalValue);

}


/* =========================================================
   PAGOS
   ========================================================= */

function addPaymentRow() {

    const tbody =
        document.querySelector(
            '#paymentsTable tbody'
        );


    if (!tbody) {
        return;
    }


    const tr =
        document.createElement('tr');


    tr.innerHTML = `

        <td>

            <select
                name="payment_method[]"
                required
            >

                <option value="">
                    Seleccione
                </option>

                                ${(window.paymentMethods || [])
                    .map(function (m) {

                        return `
                            <option
                                value="${esc(m.id_metodo_pago)}"
                                data-tasa="${esc(m.tasa)}"
                                data-moneda="${esc(m.moneda)}"
                            >
                                ${esc(m.nombre)}
                                ·
                                ${esc(m.moneda)}
                            </option>
                        `;

                    })
                    .join('')}

            </select>

        </td>


        <td>

            <input
                name="payment_amount[]"
                type="number"
                step="0.01"
                min="0"
                value="0"
            >

        </td>


        <td>

            <input
                name="payment_rate[]"
                type="number"
                step="0.000001"
                min="0"
                value="1"
            >

        </td>


               <td class="payment-base">
            -
        </td>


               <td class="payment-base">
            -
        </td>


        <td>

            <button
                type="button"
                class="btn sm danger remove-payment"
                title="Eliminar pago"
            >
                ×
            </button>

        </td>

    `;


    tbody.appendChild(tr);

}


/* =========================================================
   SINCRONIZAR FILA DE PAGO
   (autocompleta monto según la moneda elegida y el total
   de la venta, y muestra el equivalente en USD como "Base")
   ========================================================= */

function syncPaymentRow(row, forceAmount = false) {

    if (!row) {
        return;
    }

    const select =
        row.querySelector('[name="payment_method[]"]');

    const amountInput =
        row.querySelector('[name="payment_amount[]"]');

    const rateInput =
        row.querySelector('[name="payment_rate[]"]');

    const baseCell =
        row.querySelector('.payment-base');

    if (!select) {
        return;
    }

    const selectedOption =
        select.options[select.selectedIndex];

    const tasa =
        Number(selectedOption?.dataset.tasa || 0);


    if (tasa > 0 && rateInput) {

        rateInput.value = tasa;

    }


    if (
        tasa > 0 &&
        amountInput &&
        (forceAmount || Number(amountInput.value || 0) === 0)
    ) {

        amountInput.value =
            (lastSaleTotal / tasa).toFixed(2);

    }


    if (baseCell) {

        const amount =
            Number(amountInput?.value || 0);

        const rate =
            Number(rateInput?.value || 0);

        baseCell.textContent =
            (amount && rate)
                ? fmt(amount * rate)
                : '-';

    }

}




/* =========================================================
   INICIALIZACIÓN
   ========================================================= */

function initBillingApp() {

    /* Crear modal PRIMERO */

    ensureProductModal();


    /* =====================================================
       VENTA
       ===================================================== */

    const saleBody =
        document.querySelector(
            '#saleTable tbody'
        );


    if (
        saleBody &&
        !saleBody.children.length
    ) {

        addSaleRow();

    }


    /* =====================================================
       PAGOS
       ===================================================== */

    const paymentBody =
        document.querySelector(
            '#paymentsTable tbody'
        );


    if (
        paymentBody &&
        !paymentBody.children.length
    ) {

        addPaymentRow();

    }


    /* =====================================================
       COMPRA
       ===================================================== */

    const purchaseBody =
        document.querySelector(
            '#purchaseTable tbody'
        );


    if (
        purchaseBody &&
        !purchaseBody.children.length
    ) {

        addPurchaseRow();

    }


    /* =====================================================
       CLICS GLOBALES
       ===================================================== */

    document.addEventListener(
        'click',
        function (event) {


            /* ---------------------------------------------
               SELECCIONAR PRODUCTO
               --------------------------------------------- */

            const selectButton =
                event.target.closest(
                    '.select-product-btn'
                );


            if (selectButton) {

                event.preventDefault();

                event.stopPropagation();


                const row =
                    selectButton.closest('tr');


                if (!row) {
                    return;
                }


                let mode = 'purchase';


                if (
                    document.querySelector(
                        '#saleTable'
                    )?.contains(row)
                ) {

                    mode = 'sale';

                }


                openProductModal(
                    row,
                    mode
                );


                return;

            }


            /* ---------------------------------------------
               RESULTADO DE PRODUCTO
               --------------------------------------------- */

            const result =
                event.target.closest(
                    '.product-result'
                );


            if (result) {

                event.preventDefault();

                selectProductFromModal(
                    result.dataset.productId
                );

                return;

            }


            /* ---------------------------------------------
               ELIMINAR VENTA
               --------------------------------------------- */

            const removeSale =
                event.target.closest(
                    '.remove-sale'
                );


            if (removeSale) {

                const row =
                    removeSale.closest('tr');


                if (row) {

                    row.remove();

                    calcSale();

                }


                return;

            }


            /* ---------------------------------------------
               ELIMINAR COMPRA
               --------------------------------------------- */

            const removePurchase =
                event.target.closest(
                    '.remove-purchase'
                );


            if (removePurchase) {

                const row =
                    removePurchase.closest('tr');


                if (row) {

                    row.remove();

                    calcPurchase();

                }


                return;

            }


            /* ---------------------------------------------
               ELIMINAR PAGO
               --------------------------------------------- */

            const removePayment =
                event.target.closest(
                    '.remove-payment'
                );


            if (removePayment) {

                const row =
                    removePayment.closest('tr');


                if (row) {

                    row.remove();

                }


                return;

            }

        }
    );


    /* =====================================================
       INPUTS
       ===================================================== */

    document.addEventListener(
        'input',
        function (event) {

            const target =
                event.target;


            if (
                target.matches(
                    '#saleTable .qty, ' +
                    '#saleTable .price, ' +
                    '#saleForm [name="descuento"], ' +
                    '#saleForm [name="impuesto"]'
                )
            ) {

                calcSale();

            }


            if (
                target.matches(
                    '#purchaseTable .qty, ' +
                    '#purchaseTable .cost, ' +
                    '#purchaseForm [name="descuento"], ' +
                    '#purchaseForm [name="impuesto"]'
                )
            ) {

                calcPurchase();

            }

        }
    );

}
    /* =====================================================
       CAMBIO DE MÉTODO DE PAGO
       ===================================================== */

    document.addEventListener(
        'change',
        function (event) {

            const select =
                event.target.closest(
                    '[name="payment_method[]"]'
                );

            if (select) {

                syncPaymentRow(
                    select.closest('tr'),
                    true
                );

            }

        }
    );


    /* =====================================================
       EDICIÓN MANUAL DE MONTO / TASA
       ===================================================== */

    document.addEventListener(
        'input',
        function (event) {

            const target =
                event.target;

            if (
                target.matches(
                    '[name="payment_amount[]"], [name="payment_rate[]"]'
                )
            ) {

                syncPaymentRow(
                    target.closest('tr')
                );

            }

        }
    );

/* =========================================================
   INICIAR
   ========================================================= */

if (
    document.readyState === 'loading'
) {

    document.addEventListener(
        'DOMContentLoaded',
        initBillingApp
    );

} else {

    initBillingApp();

}