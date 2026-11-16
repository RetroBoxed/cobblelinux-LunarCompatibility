#!/usr/bin/env bash
# Inyecta cobble.so en la partida que ya está corriendo (CheatBreaker).
#
#   ./inyectar.sh              detecta el PID del juego solo
#   ./inyectar.sh <pid>        inyecta en ese PID
#   ./inyectar.sh --listar     muestra las JVMs a las que se puede adjuntar
#
# El registro queda en ~/.local/share/cobble/cobble.log
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SO="$DIR/cobble.so"
LOG="$HOME/.local/share/cobble/cobble.log"

[ -f "$SO" ] || { echo "ERROR: no existe $SO" >&2; exit 1; }
[ -f "$DIR/CrewXAttach.class" ] || { echo "ERROR: falta CrewXAttach.class junto al .so" >&2; exit 1; }

# ---------------------------------------------------------------- java ------
# El adjuntador (Attach API) vive en el JDK, no en el JRE del juego: hace
# falta un java >= 9 con el módulo jdk.attach, o un java 8 con tools.jar.
java_adjuntable() {
    local bin="$1"
    [ -x "$bin" ] || return 1
    local ver
    ver="$("$bin" -version 2>&1 | head -1)" || return 1
    case "$ver" in
        *1.8.*)
            # Con Java 8 el cliente de attach está en tools.jar, al lado del jre.
            local real dir
            real="$(readlink -f "$bin")"
            dir="$(dirname "$(dirname "$real")")"
            [ -f "$dir/lib/tools.jar" ] || return 1
            ;;
        *)
            "$bin" --list-modules 2>/dev/null | grep -q '^jdk\.attach@' || return 1
            ;;
    esac
}

JAVA_BIN=""
CANDIDATES=()
[ -n "${JAVA_HOME:-}" ] && CANDIDATES+=("$JAVA_HOME/bin/java")
CANDIDATES+=("$(command -v java || true)")
CANDIDATES+=("$HOME/.local/opt/jdk21/bin/java" "/usr/bin/java")
for base in /usr/lib/jvm/*/bin /opt/java*/bin; do
    CANDIDATES+=("$base/java")
done
for candidate in "${CANDIDATES[@]}"; do
    if java_adjuntable "$candidate"; then
        JAVA_BIN="$candidate"
        break
    fi
done

if [ -z "$JAVA_BIN" ]; then
    echo "ERROR: no hay un JDK con el que adjuntar la partida." >&2
    echo "       Instala uno (openjdk-21-jdk / temurin-21) o exporta JAVA_HOME." >&2
    exit 1
fi

# Java 8 necesita tools.jar en el classpath; los demás, no.
CP="$DIR"
case "$("$JAVA_BIN" -version 2>&1 | head -1)" in
    *1.8.*)
        REAL="$(readlink -f "$JAVA_BIN")"
        CP="$CP:$(dirname "$(dirname "$REAL")")/lib/tools.jar"
        ;;
esac

# ------------------------------------------------------------ candidatos ----
# Las JVMs adjuntables primero (lo que el propio JVM publica); si eso sale
# vacío, se barre /proc buscando procesos java cuyo comando nombre el juego.
candidatos() {
    # Fuera el propio adjuntador (esta JVM es la que lista) y este script.
    "$JAVA_BIN" -cp "$CP" CrewXAttach --list 2>/dev/null |
        awk 'NR>1 && $1 ~ /^[0-9]+$/ {print $1 "\t" $2}' |
        grep -viE 'CrewXAttach|inyectar' || true
}

es_juego() {
    # El nombre que la JVM publica (display name) o su /proc/<pid>/cmdline.
    printf '%s' "$1" | grep -qiE 'cheatbreaker|lunarclient|net\.minecraft|launchwrapper|minecraft-|client\.jar|\.minecraft'
}

pid_de_juego() {
    local lista pid nombre
    lista="$(candidatos)"
    if [ -n "$lista" ]; then
        while IFS=$'\t' read -r pid nombre; do
            es_juego "$nombre" && printf '%s\n' "$pid" && return 0
        done <<< "$lista"
        # Ninguno nombrado como juego: si hay uno solo, es probablemente ese.
        local n
        n="$(printf '%s\n' "$lista" | grep -c . || true)"
        if [ "$n" = "1" ]; then
            echo "Aviso: el juego no se reconoció por el nombre; uso el único JVM adjuntable." >&2
            printf '%s\n' "$lista" | head -1 | cut -f1
            return 0
        fi
        if [ -n "$lista" ]; then
            echo "Hay varios JVM y ninguno parece el juego; elige uno:" >&2
            printf '%s\n' "$lista" >&2
        fi
        return 1
    fi
    # Fallback: /proc, sin -f para no matchear a este propio script.
    local self="$$"
    for cmd in /proc/[0-9]*/cmdline; do
        pid="${cmd#/proc/}"; pid="${pid%/cmdline}"
        [ "$pid" = "$self" ] && continue
        [ -r "$cmd" ] || continue
        nombre="$(tr '\0' ' ' < "$cmd" 2>/dev/null || true)"
        case "$nombre" in
            *java*|*jre*|*jvm*) ;;
            *) continue ;;
        esac
        case "$nombre" in
            *inyectar.sh*|*CrewXAttach*) continue ;;
        esac
        if es_juego "$nombre"; then
            echo "$pid"
            return 0
        fi
    done
    return 1
}

# -------------------------------------------------------------- ejecutar ----
case "${1:-}" in
    --listar)
        echo "JVMs adjuntables:"
        candidatos || true
        echo
        echo "Uso: ./inyectar.sh          (detecta el juego solo)"
        echo "     ./inyectar.sh <pid>"
        exit 0
        ;;
    "")
        PID="$(pid_de_juego)" || {
            echo "ERROR: no hay ninguna partida corriendo (CheatBreaker 1.8.9)." >&2
            echo "       Abre el juego y entra a un mundo o servidor, luego repite." >&2
            echo "       Con ./inyectar.sh --listar ves las JVMs que hay." >&2
            exit 1
        }
        echo "Partida detectada: PID $PID"
        ;;
    *)
        PID="$1"
        case "$PID" in
            *[!0-9]*) echo "ERROR: el PID debe ser numérico: $PID" >&2; exit 1 ;;
        esac
        ;;
esac

# El listado y la inyección van en JVMs distintos: comprobamos que siga vivo.
[ -d "/proc/$PID" ] || { echo "ERROR: el proceso $PID ya no existe" >&2; exit 1; }

echo "Inyectando $SO en PID $PID ..."
"$JAVA_BIN" -cp "$CP" CrewXAttach --inject "$PID" "$SO"

echo
echo "Listo. Mira el registro:"
echo "  tail -f $LOG"
echo "Si el juego estaba en el menú principal, espera a entrar a un mundo."
