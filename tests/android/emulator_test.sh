#!/bin/bash
# Prueba del APK en un emulador Android (la ejecuta .github/workflows/android-test.yml).
# Instala el APK, activa la prueba automática interna, abre el juego, espera el
# resultado y recoge informe, capturas y registro del sistema en ./android_out
set -u
PKG=com.julianfarks.teletimo
OUT=android_out
mkdir -p $OUT
adb wait-for-device
adb shell getprop ro.product.cpu.abilist > $OUT/abis.txt
echo "ABIs: $(cat $OUT/abis.txt)"
adb shell cat /proc/meminfo | head -3 >> $OUT/abis.txt
if ! adb install -r -g TeleTimo3D-debug.apk > $OUT/install.txt 2>&1; then
  echo "FALLO: no se pudo instalar"; cat $OUT/install.txt; exit 1
fi
echo "APK instalado"; cat $OUT/install.txt
adb shell pm grant $PKG android.permission.RECORD_AUDIO || true
adb shell run-as $PKG mkdir -p files
adb shell run-as $PKG touch files/autotest.flag
adb logcat -c
adb shell monkey -p $PKG -c android.intent.category.LAUNCHER 1
START=$(date +%s)
N=0
while true; do
  sleep 30
  N=$((N+1))
  adb exec-out screencap -p > $OUT/pantalla_$(printf %03d $N).png 2>/dev/null || true
  if ! adb shell pidof $PKG > /dev/null; then
    echo "La app no está en ejecución (¿cierre inesperado?)"
    echo "CIERRE" > $OUT/estado.txt
    break
  fi
  if adb shell run-as $PKG cat files/autotest/terminado.txt > $OUT/terminado.txt 2>/dev/null && [ -s $OUT/terminado.txt ]; then
    echo "Prueba interna terminada: $(cat $OUT/terminado.txt)"
    echo "TERMINADO" > $OUT/estado.txt
    break
  fi
  adb shell run-as $PKG cat files/autotest/resultado.txt 2>/dev/null | tail -2
  if [ $(( $(date +%s) - START )) -gt 4800 ]; then echo "Tiempo agotado"; echo "TIEMPO" > $OUT/estado.txt; break; fi
done
adb exec-out run-as $PKG cat files/autotest/resultado.txt > $OUT/resultado.txt 2>/dev/null || true
for f in 01_inicio 02_oficina 03_oferta 04_llamada 05_venta 06_resumen 07_evaluacion; do
  adb exec-out run-as $PKG cat files/autotest/$f.png > $OUT/$f.png 2>/dev/null || true
done
adb logcat -d > $OUT/logcat_completo.txt || true
grep -E "godot|Godot|AUTOTEST|nobodywho|FATAL|AndroidRuntime|DEBUG   :" $OUT/logcat_completo.txt > $OUT/logcat_juego.txt || true
cat $OUT/resultado.txt || true
exit 0
