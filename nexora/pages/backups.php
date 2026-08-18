<?php admin_only();$files=glob(__DIR__.'/../storage/backups/*.sql')?:[];?>
<section class="panel"><h2>Respaldos</h2><p class="muted">Crea una copia SQL de todas las tablas.</p><form method="post" action="actions.php"><input type="hidden" name="csrf" value="<?=e(csrf())?>"><input type="hidden" name="action" value="backup"><input type="hidden" name="return_page" value="backups"><button class="btn primary">Crear respaldo ahora</button></form></section>
<section class="panel"><h2>Archivos creados</h2><ul><?php foreach($files as $f):?><li><?=e(basename($f))?></li><?php endforeach;?></ul></section>
