---
lastSync: Sun Nov 15 2026 11:10:46 GMT-0300 (Argentina Standard Time)
---
# Cobble Recode — paquete Linux

Cliente listo para usar en **Linux x64**. Un solo archivo `.so`, sin instalar
nada más, sin sudo, sin Wine.

## Qué hay aquí

| Archivo | Para qué sirve |
|---|---|
| `cobble.so` | El cliente. Se mete en la partida que ya está corriendo. |
| `inyectar.sh` | Detecta el PID del juego solo y lo inyecta. |
| `lunar-attach-wrapper.sh` | Envoltorio para el «Wrapper Command» de Lunar: permite que `inyectar.sh` se adjunte al juego. |
| `lunar-widen.jar` | Agente que el envoltorio añade al arrancar: hace públicos los accesos de las clases del juego para que cobble.so pueda retransformarlas después sin fallo. |
| `scripts/` | Ejemplos de Lua (se copian solos a tu carpeta la primera vez). |
| `CrewXAttach.class` | Ayudante que usa `inyectar.sh` para adjuntar el `.so`. |
| `README.md` | Este archivo. |

## Requisitos

- Linux x64 con **glibc 2.35 o superior** (Ubuntu 22.04 / Debian 12 o más
  nuevos; Fedora 36+, Arch, Mint 21+…). No hace falta libcrypto ni nada de
  OpenSSL: todo está dentro del `.so`.
- **CheatBreaker 1.8.9** abierto, dentro de un mundo o servidor.
- Un **JDK** para el adjuntador (no el del juego): `openjdk-21-jdk`,
  Temurin 21, o cualquier `java` ≥ 9 con el módulo `jdk.attach`. Si solo
  tienes Java 8, sirve también si su `lib/tools.jar` existe.
  *No hace falta JDK para usarlo con Lunar Client (ver más abajo).*

## Uso con CheatBreaker

```bash
tar xzf cobble-linux.tar.gz
cd cobble-linux
./inyectar.sh
```

El script solo busca la partida en marcha y la inyecta. Si tienes varias
ventanas de Java abiertas, elige a mano:

```bash
./inyectar.sh --listar     # ver las JVMs adjuntables
./inyectar.sh 12345        # inyectar en ese PID
```

Comprueba el registro (también sirve `tail -f`):

```bash
cat ~/.local/share/cobble/cobble.log
```

Deberías ver `bootstrap loaded` y luego el juego arrancando el cliente.

### Controles

| Tecla | Qué hace |
|---|---|
| <kbd>Insert</kbd> | Abre/cierra el menú (ClickGUI). |
| <kbd>End</kbd> mantenido 0.6 s | Descarga el cliente y deja el juego limpio. |

## Uso con Lunar Client

1. En Lunar → ajustes del perfil **Minecraft 1.8** → **Opciones avanzadas** →
   **Wrapper Command**, escribe:

   ```
   /home/nikox/Desktop/cobble-linux/lunar-attach-wrapper.sh
   ```

2. Arranca la versión y entra a un mundo.
3. En una terminal:

   ```bash
   cd ~/Desktop/cobble-linux
   ./inyectar.sh
   ```

El envoltorio le quita al proceso del juego `-XX:+DisableAttachMechanism` y las
variables `_JAVA_OPTIONS`/`JAVA_TOOL_OPTIONS`/`JDK_JAVA_OPTIONS` (y también el
`-agentpath` de cobble, si lo dejaste puesto), así que `inyectar.sh` puede
adjuntarse sin el `AttachNotSupportedException`.

Además añade `-javaagent:lunar-widen.jar`. Ese agente hace públicos los
accesos de las clases del juego (`net/minecraft/**`) cuando se cargan; sin él,
al adjuntar cobble con el juego ya en marcha, su fijador tendría que
retransformar clases ya cargadas y Java 17 rechaza el cambio de modificadores
(`JVMTI_ERROR_UNSUPPORTED_REDEFINITION_METHOD_MODIFIERS_CHANGED`, error 71).
Solo ensancha `net/minecraft`: hacer lo mismo con las clases de Lunar
(`com/moonsworth/**`) rompe su arranque (`Failed to construct managers!`).

> **Nota:** este `.so` ya sirve para **Lunar 1.8.9** la  compatibilidad para versiones 1.21.11 o 1.7.10 no esta compatible con este metodo.
> Teoricamente andaria si se completa la compatibilidad en (`COLD_ENABLE_MODERN=ON`

## Cómo se ve el registro cuando va bien

```
[      0.000] INFO  [native] bootstrap loaded
[      0.041] INFO  [native] VM ready; attaching
```

Si pasan 2 minutos sin encontrar el juego:

```
[    120.149] ERROR [native] the Minecraft class was never loaded
[    120.150] ERROR [native] start failed; unloading
```

Eso **no** rompe nada: el juego sigue igual y el `.so` se descarga solo.
Significa que se inyectó antes de entrar a un mundo (o que no era una
partida). Vuelve a inyectar ya dentro del mundo.

## Problemas típicos

| Síntoma | Causa / arreglo |
|---|---|
| Pantalla de info de Lunar (`Username: … UUID: …`) y no arranca | Hay **dos** `-agentpath` o la ruta no existe. Deja **una sola** línea con la ruta real y verifica con `ls -l` ese archivo. |
| Lunar casca con `Failed to construct managers!` / `Failed to boot Minecraft` | El `.so` cargado desde el inicio con `-agentpath` rompe el arranque de Lunar. Quita el `-agentpath`, usa el **Wrapper Command** `lunar-attach-wrapper.sh` e inyecta con `./inyectar.sh` ya dentro del mundo. |
| `The VM does not support the attach mechanism` | Lunar desactiva el adjuntado (`DisableAttachMechanism`). Usa el **Wrapper Command** `lunar-attach-wrapper.sh` (o activa el ajuste oculto «Enable Attach» del launcher) y luego `./inyectar.sh`. |
| `RetransformClasses failed: 71` / `attempted to change method modifiers` | El `.so` necesita retransformar clases ya cargadas y Java 17 no permite cambiar modificadores. Arranca el juego con `-javaagent:lunar-widen.jar` (el envoltorio lo añade solo) y vuelve a inyectar. |
| No sale el menú al presionar <kbd>Insert</kbd> | El menú solo abre **sin ninguna pantalla del juego abierta** (en el menú principal o en pausa no funciona). Entra a un mundo, espera a que cargue y pulsa <kbd>Insert</kbd>. |
| `no hay ninguna partida corriendo` | Abre CheatBreaker 1.8.9 y entra a un mundo antes de inyectar. |
| `no hay un JDK con el que adjuntar` | Instala un JDK 21 o exporta `JAVA_HOME=/ruta/al/jdk`. |
| El juego no arranca el cliente | Mira `~/.local/share/cobble/cobble.log`; ahí está el motivo exacto. |
| `IllegalAccessError` al entrar al mundo | El `.so` se ha reconstruido con un fijador nativo de clase que abre los miembros privados/protegidos al vuelo (antes la compilación usaba `tools/Widen.java`). Esto sucede cuando Lunar usa sus propias copias de las clases del juego con el acceso original. El fíjador se activa automáticamente al cargar cada clase y normaliza los flags de acceso al instante. |
| `ClassCastException: BlockAir cannot be cast to BlockLeaves` al arrancar | El cliente se registró antes de que Lunar terminara de inicializar los bloques. Esta versión espera a que el juego esté listo (`waiting for the game to finish starting` en el log) antes de cargar los módulos; vuelve a descomprimir el tarball nuevo y no reutilices el `.so` viejo. |
| Se inyecta y no aparece nada | Espera ~5 s; si dice *never loaded*, estabas en el menú principal. |


## Notas de seguridad e instalación

- Todo vive en la carpeta de donde ejecutes el tarball; no se instala nada
  en el sistema ni se pide sudo.
- El registro y la configuración se guardan en `~/.local/share/cobble/`.
- El `.so` no depende de `libcrypto.so.3` ni de versiones nuevas de
  `libstdc++`: está enlazado estático y solo pide `libc`, `libm` y `ld-linux`.