#!/usr/bin/env bash
# Envoltorio para el «Wrapper Command» de Lunar Client.
#
# Lunar invoca el juego así:
#   <este script> <java> <argumentos de la JVM...>
#
# Lunar desactiva el mecanismo de adjuntado de la JVM (necesario para
# inyectar cobble.so con inyectar.sh) de dos formas:
#   * la opción   -XX:+DisableAttachMechanism
#   * las variables _JAVA_OPTIONS, JAVA_TOOL_OPTIONS y JDK_JAVA_OPTIONS
#
# Este script las elimina antes de arrancar la JVM de verdad, y con eso
# inyectar.sh puede adjuntarse al proceso del juego.
#
# Además, si sigue configurado el -agentpath de cobble.so (que hace
# crashear Lunar al arranque), lo quita también: la inyección se hace
# después, con inyectar.sh, una vez dentro del mundo.
#
# Y añade -javaagent con lunar-widen.jar, que ensancha los accesos de las
# clases del juego al cargarse. Sin eso, cuando cobble.so se adjunta con
# el juego ya en marcha, su fijador necesita retransformar clases cargadas
# y Java 17 lo rechaza (JVMTI_ERROR_UNSUPPORTED_REDEFINITION_METHOD_MODIFIERS_CHANGED).
# Con las clases ya públicas, la retransformación solo cambia el cuerpo de
# los métodos y sí está permitida.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Registro de depuración del arranque (no afecta al juego).
DBG="$HOME/.local/share/cobble/wrapper.log"
mkdir -p "$(dirname "$DBG")"
{
    echo "=== $(date '+%F %T') ==="
    echo "java: $1"
    printf 'arg: %s\n' "${@:2}"
} >> "$DBG"

unset _JAVA_OPTIONS JAVA_TOOL_OPTIONS JDK_JAVA_OPTIONS

JAVA_BIN="$1"
shift

args=("-javaagent:$DIR/lunar-widen.jar")
# El agente solo ensancha net/minecraft por defecto; WIDEN_MODE es para depurar.
args+=("-Dwiden.mode=${WIDEN_MODE:-mc}")
for a in "$@"; do
    case "$a" in
        -XX:+DisableAttachMechanism) continue ;;
        -agentpath:*cobble*|-agentlib:*cobble*) continue ;;
    esac
    args+=("$a")
done

exec "$JAVA_BIN" "${args[@]}"
