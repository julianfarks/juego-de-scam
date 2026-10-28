# Clave de firma de DEPURACIÓN

`teletimo-debug.keystore` (contraseña `android`, alias `androiddebugkey`) firma los APK de
depuración que compila GitHub Actions. Es siempre la misma para que cada versión nueva se
instale **encima** de la anterior: con una clave distinta Android obliga a desinstalar, y al
desinstalar se borran los modelos de IA descargados (3 GB).

- Es una clave de **depuración**, como la que genera Android Studio; no sirve para publicar
  en Google Play ni protege nada valioso. Para una versión de tienda hay que crear una
  clave de publicación propia y guardarla fuera del repositorio.
- Si se añade el secreto `ANDROID_DEBUG_KEYSTORE_B64` (keystore en base64) en
  *Settings → Secrets → Actions*, el flujo lo usa en lugar de este archivo.
