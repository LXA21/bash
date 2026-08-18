<?php admin_only();$base=base_currency();?>
<section class="panel"><h2>Configuración</h2><div class="notice"><b>Moneda base:</b> <?=e($base['codigo'])?> (<?=e($base['simbolo'])?>). Las monedas adicionales y sus tasas se gestionan desde Métodos de pago.</div><p class="clean">Recomendación: realiza respaldos periódicos y cambia la contraseña inicial del administrador.</p></section>
