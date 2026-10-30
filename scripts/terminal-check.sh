#!/bin/sh
# Run inside Terminal2 to check the real PTY and graphics renderer.
set -eu
printf '\033[2J\033[H\033]0;Terminal2\007'
printf '\033[1mTerminal2\033[0m\n\n'
printf '日本語 / 全角文字 / UTF-8  ✓\n'
printf 'e\314\201  café  →  ┌──────┐\n'
printf '               │ 端末 │\n'
printf '               └──────┘\n\n'
printf 'TrueColor  '
for color in '238;238;238' '180;180;180' '120;120;120' '80;80;80'; do
    printf '\033[48;2;%sm    \033[0m' "$color"
done
printf '\n\nPTY  '
stty size
printf 'https://github.com/fuba/terminal2\n\n'
printf 'Sixel\n'
printf '\033P0;1q"1;1;96;24#0;2;88;89;91#0!96~-$!96~-$!96~-$!96~\033\\\n\n'
if [ -n "${1:-}" ]; then
    printf 'iTerm2 inline image\n'
    printf '\033]1337;File=inline=1;width=80px;height=80px;preserveAspectRatio=1:'
    base64 < "$1" | tr -d '\n'
    printf '\007\n'
fi
