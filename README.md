# Claude Usage — widget de macOS

Widget nativo de WidgetKit más un ítem de barra de menú que muestran el consumo del plan
Claude Max: la ventana de sesión de 5 horas, el límite semanal de todos los modelos y el
límite semanal del modelo que la cuenta contabiliza aparte.

Renderiza el prototipo de Claude Design *Claude Usage Widget*
(`8a9ca1c1-6dc8-45be-8ca2-87dca5cad9b4`) contra datos reales.

## Qué se ve

<p align="center">
  <img src="docs/popover.png" alt="Popover de barra de menú" width="290">
  <img src="docs/large.png" alt="Widget grande" width="350">
</p>
<p align="center">
  <img src="docs/small.png" alt="Widget pequeño" width="165">
  <img src="docs/medium.png" alt="Widget mediano" width="350">
</p>

Capturas renderizadas con datos reales de la cuenta.

| Pieza | Tamaño | Contenido |
|---|---|---|
| Barra de menú | — | Chispa teñida + % de sesión; el popover trae las tres barras, el gráfico de 7 días y el toggle de refresco |
| `systemSmall` | 170×170 | % de sesión en grande, barra, cuenta atrás de reinicio y barra semanal |
| `systemMedium` | 364×170 | Anillo de sesión, semanal total, semanal por modelo y ambas cuentas atrás |
| `systemLarge` | 364×382 | Tres tiles de límite, gráfico apilado de 7 días, leyenda por modelo y contadores |

## El modelo que aparece no está fijado en el código

El prototipo dibujaba «Weekly · Opus». La cuenta hoy contabiliza **Fable** aparte, y
mañana puede ser otro. El widget no elige: `/api/oauth/usage` devuelve un array `limits`
con una entrada por ventana activa, etiquetada `session`, `weekly_all` o `weekly_scoped`,
y esta última trae el nombre del modelo en `scope.model.display_name`. La UI imprime ese
nombre. Cuando Anthropic cambie qué modelo tiene presupuesto propio, el widget lo refleja
sin recompilar.

Las claves antiguas de nivel superior (`five_hour`, `seven_day`, `seven_day_opus`,
`seven_day_sonnet`) se siguen leyendo como respaldo por si una cuenta no trae `limits`.

## Requisitos

Xcode no hace falta, pero las Command Line Tools deben corresponder al sistema en uso:

```sh
xcrun --show-sdk-version   # debe reportar la versión del macOS actual
```

## Instalación

```sh
./build.sh
```

Compila los dos binarios con `swiftc`, arma `Claude Usage.app` con la extensión en
`Contents/PlugIns`, firma todo ad-hoc, copia la app a `/Applications` y la registra en
LaunchServices. Después:

1. Abre **Claude Usage** una vez — macOS solo ofrece el widget cuando la app contenedora
   ya se ejecutó. Queda como accesorio: barra de menú, sin icono en el Dock.
2. macOS pedirá permiso para leer el llavero (ver más abajo). Elige **Permitir siempre**.
3. Clic derecho en el escritorio → *Editar widgets* → busca **Uso de Claude**.

`INSTALL_DIR=~/Applications ./build.sh` instala solo para tu usuario.

## De dónde salen los datos

Dos fuentes, y la UI distingue cuál es cuál porque miden cosas distintas.

**Los límites del plan** vienen de `https://api.anthropic.com/api/oauth/usage`, la misma
información que muestran `/usage` y el panel de claude.ai. No hay que pegar ninguna cookie
ni crear ningún token: la app lee el token OAuth que **Claude Code ya guarda** en el
llavero, bajo el ítem `Claude Code-credentials`. Claude Code lo renueva mientras se usa,
así que leerlo en cada poll basta.

Nunca se escribe nada de vuelta. Rotar el refresh token invalidaría la copia de Claude
Code y cerraría la sesión del CLI del usuario, así que un token caducado se reporta como
un aviso —«abre Claude Code una vez»— en lugar de renovarse por cuenta propia.

**El histórico de tokens** (gráfico de 7 días, leyenda por modelo, contadores del pie) se
agrega de los transcripts de Claude Code en `~/.claude/projects/**/*.jsonl`. La API
reporta porcentajes contra el plan, no tokens, y no dice qué modelo los gastó.

Esto implica un alcance que conviene tener claro, y que la UI etiqueta: **el gráfico cubre
Claude Code en este Mac**. El trabajo hecho en la web de claude.ai cuenta para las barras
de límite de arriba pero no deja transcript aquí, así que no aparece en el gráfico.

### Cómo fluyen

La extensión nunca toca la red ni el llavero. La app contenedora consulta, escribe
`status.json` y llama a `WidgetCenter.reloadAllTimelines()`; la extensión solo lee el
archivo. Eso evita los App Groups, que exigirían una identidad de firma de pago.

```
LaunchAgent (5 min) ──▶ ClaudeUsage --refresh ──┬──▶ llavero → api.anthropic.com/api/oauth/usage
                                                └──▶ ~/.claude/projects/**/*.jsonl
                                 │
                                 ├──▶ ~/Library/Application Support/ClaudeUsageWidget/status.json
                                 └──▶ ~/Library/Containers/io.diegopuerto.claudeusage.widget/…/status.json
                                                               │
                                                     ClaudeUsageWidget.appex (solo lectura)
```

## El permiso del llavero

El ítem `Claude Code-credentials` lo creó Claude Code, y su ACL solo autoriza en silencio
a los binarios que ya lista. Cualquier otra app pide permiso la primera vez. Al elegir
**Permitir siempre**, macOS añade este binario a la ACL y no vuelve a preguntar.

Con firma ad-hoc la autorización va atada al hash del binario, así que **un `./build.sh`
nuevo vuelve a pedirla una vez**. Es el precio de no tener un Developer ID de pago.

El refresco en segundo plano no puede atender un diálogo: `launchd` correría un proceso
colgado en un cuadro que nadie ve, cada cinco minutos. Por eso `--refresh` desactiva la
interacción y falla rápido, y el mensaje pide abrir el menú y pulsar *Actualizar ahora*,
que sí puede mostrar el diálogo.

## Números y su significado

- **Sesión** — ventana móvil de 5 horas. Es la que corta el trabajo en el día.
- **Semanal · todos** — ventana de 7 días sobre todos los modelos.
- **Semanal · \<modelo\>** — el presupuesto semanal propio del modelo que la cuenta separe.
- **Racha** — días consecutivos con actividad. Topada a 7: no se carga nada más antiguo.
- **Hora pico** — la hora local que más tokens acumuló en la ventana.
- El punto de estado y el tinte de la barra de menú siguen a la **ventana más llena**, no
  solo a la sesión, para que un semanal casi agotado no pase desapercibido una tarde
  tranquila.

Los umbrales de color son los del prototipo: naranja por debajo de 70 %, ámbar desde 70 %,
rojo desde 90 %.

## El flag de compilación no obvio

Una app extension debe entrar por `NSExtensionMain` de Foundation, que Xcode consigue con
`-e _NSExtensionMain` en los flags del linker. Sin él, WidgetKit llega a
ExtensionFoundation sin identidad de extensión y aborta con *Unrecognized extension type*;
la consulta de descriptores de `chronod` muere y purga la extensión. El síntoma es una
ausencia completamente silenciosa de la galería de widgets.

Para confirmar el punto de entrada de cualquier extensión compilada:

```sh
nm -u "ClaudeUsageWidget.appex/Contents/MacOS/ClaudeUsageWidget" | grep NSExtensionMain
```

## Límites conocidos

- WidgetKit dibuja snapshots estáticos: el punto de estado pulsa en el popover, no en el
  widget de escritorio.
- La firma ad-hoc hace la app local: no se puede distribuir a otro Mac sin Developer ID.
- El gráfico de 7 días no ve el uso de la web de claude.ai (ver arriba).
- La racha nunca reporta más de 7 días.

## Crédito

La ruta de datos parte de [ClaudeUsageBar](https://github.com/Artzainnn/ClaudeUsageBar)
(MIT), que resolvió antes qué endpoints reportan el uso y que `Fable` vive dentro de
`limits[]` y no como clave propia. Este proyecto cambia la autenticación —token OAuth del
llavero en lugar de una cookie pegada a mano— y añade el widget de escritorio y el
histórico local por modelo.
