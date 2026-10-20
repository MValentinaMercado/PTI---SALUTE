#!/usr/bin/env python3
"""
Correcciones mecánicas de accesibilidad para Salute (WCAG 2.1 AA).

Uso (desde la raíz del proyecto):
    python3 tools/a11y_codemod.py lib            # solo muestra qué cambiaría
    python3 tools/a11y_codemod.py lib --apply    # aplica los cambios

Qué hace:
  1. CONTRASTE (WCAG 1.4.3 / 1.4.11): reemplaza los grises claros de texto e
     íconos (Colors.grey[400|500|600], Colors.grey.shade400|500|600) por
     SaluteColors.textMuted (#5F6368, >= 4,5:1 sobre blanco y fondos de la
     app). Saltea bordes, divisores, fondos y estados "completado".
     Agrega el import de colors.dart si hace falta.
  2. NOMBRES ACCESIBLES (WCAG 4.1.2): agrega `tooltip:` a los IconButton que
     no lo tienen, cuando el ícono tiene un significado claro. Los demás se
     listan para completarlos a mano.

Respeta los saltos de línea (CRLF/LF) de cada archivo. No toca nada más.
Revisá el diff (`git diff`) antes de commitear.
"""
import re
import sys
from pathlib import Path

GREY = re.compile(r'Colors\.grey(?:\[(?:400|500|600)\]|\.shade(?:400|500|600))!?')
SKIP_LINE = re.compile(r'[Bb]order|[Dd]ivider|fillColor|[Bb]ackground|shadow|done\s*\?|disabled', re.I)
COLOR_CTX = re.compile(r'color\s*:|\?\s*$|:\s*$')

ICON_LABELS = {
    'visibility_off_outlined': 'Mostrar u ocultar contraseña',
    'visibility_outlined': 'Mostrar u ocultar contraseña',
    'visibility_off': 'Mostrar u ocultar contraseña',
    'visibility': 'Mostrar u ocultar contraseña',
    'arrow_back': 'Volver',
    'arrow_back_ios': 'Volver',
    'chevron_left': 'Anterior',
    'chevron_right': 'Siguiente',
    'remove_circle_outline': 'Disminuir',
    'add_circle_outline': 'Aumentar',
    'delete_outline': 'Eliminar',
    'delete': 'Eliminar',
    'close': 'Cerrar',
    'close_rounded': 'Cerrar',
    'swap_horiz': 'Cambiar',
    'edit_outlined': 'Editar',
    'edit': 'Editar',
    'search': 'Buscar',
    'send_rounded': 'Enviar',
    'send': 'Enviar',
}


def fix_contrast(text):
    out, n, skipped = [], 0, []
    for i, line in enumerate(text.split('\n'), 1):
        if GREY.search(line):
            if not SKIP_LINE.search(line) and 'color' in line:
                new, c = GREY.subn('SaluteColors.textMuted', line)
                n += c
                line = new
            else:
                skipped.append(i)
        out.append(line)
    return '\n'.join(out), n, skipped


def matching_paren(s, open_idx):
    depth, i, in_str = 0, open_idx, None
    while i < len(s):
        ch = s[i]
        if in_str:
            if ch == '\\':
                i += 1
            elif ch == in_str:
                in_str = None
        elif ch in ('"', "'"):
            in_str = ch
        elif ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def fix_tooltips(text, rel):
    added, pending = 0, []
    pos = 0
    while True:
        m = re.compile(r'\bIconButton\(').search(text, pos)
        if not m:
            break
        open_idx = m.end() - 1
        close = matching_paren(text, open_idx)
        if close < 0:
            pos = m.end()
            continue
        body = text[open_idx:close]
        line_no = text.count('\n', 0, m.start()) + 1
        if 'tooltip:' not in body:
            icon = re.search(r'Icons\.(\w+)', body)
            label = ICON_LABELS.get(icon.group(1)) if icon else None
            if label:
                if text[m.end()] == '\n':  # IconButton( con argumentos en líneas aparte
                    line_start = text.rfind('\n', 0, m.start()) + 1
                    indent = re.match(r'[ \t]*', text[line_start:]).group(0) + '  '
                    ins = f"\n{indent}tooltip: '{label}',"
                else:  # IconButton(onPressed: ..., icon: ...) en una sola línea
                    ins = f"tooltip: '{label}', "
                text = text[:m.end()] + ins + text[m.end():]
                added += 1
                pos = m.end() + len(ins)
                continue
            pending.append(f"{rel}:{line_no} ({icon.group(1) if icon else 'ícono no literal'})")
        pos = m.end()
    return text, added, pending


def ensure_colors_import(text):
    if 'SaluteColors' not in text:
        return text
    if re.search(r"import\s+'package:saluteapp/core/colors\.dart';", text):
        return text
    if re.search(r"import\s+'(?:\.\./)*(?:core/)?colors\.dart';", text):
        return text
    imp = "import 'package:saluteapp/core/colors.dart';\n"
    lines = text.split('\n')
    last = max((i for i, l in enumerate(lines) if l.startswith('import ')), default=-1)
    lines.insert(last + 1, imp.rstrip('\n'))
    return '\n'.join(lines)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    apply = '--apply' in sys.argv
    root = Path(args[0] if args else 'lib')
    total_c = total_t = 0
    pending_all = []
    review_all = []
    for f in sorted(root.rglob('*.dart')):
        if f.name == 'colors.dart':
            continue
        raw = f.read_bytes().decode('utf-8')
        crlf = '\r\n' in raw
        text = raw.replace('\r\n', '\n')
        new, c, skipped = fix_contrast(text)
        new, t, pending = fix_tooltips(new, str(f))
        pending_all += pending
        review_all += [f"{f}:{ln} (gris claro, revisar si es texto/ícono)" for ln in skipped]
        if c or t:
            new = ensure_colors_import(new)
            total_c += c
            total_t += t
            print(f"{f}: contraste {c}, tooltips {t}")
            if apply:
                f.write_bytes((new.replace('\n', '\r\n') if crlf else new).encode('utf-8'))
    print(f"\nTotal: {total_c} colores de bajo contraste, {total_t} tooltips agregados "
          f"({'APLICADO' if apply else 'simulación: usá --apply'}).")
    if pending_all:
        print("\nIconButton que siguen sin etiqueta (completar a mano):")
        for p in pending_all:
            print("  -", p)
    if review_all:
        print("\nGrises claros que se saltearon a propósito (bordes, deshabilitados, ternarios):")
        for p in review_all:
            print("  -", p)


if __name__ == '__main__':
    main()
